# unreal-agent-guardrails - test suite entry point
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1
#
# Exits with 0 when every test passes, 1 otherwise.
# No Unreal Engine installation and no proprietary project are required.

[CmdletBinding()]
param(
    [string]$Filter
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$testRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $testRoot

. (Join-Path $testRoot 'TestHarness.ps1')

Import-Module (Join-Path $repoRoot 'src\unreal-agent-guardrails.psd1') -Force

$fixtures = Join-Path $testRoot 'fixtures'
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("uat-tests-" + [guid]::NewGuid().ToString('N'))

Write-Host ''
Write-Host '=============================================================='
Write-Host ' unreal-agent-guardrails test suite'
Write-Host " scratch: $scratch"
Write-Host '=============================================================='

New-Item -ItemType Directory -Path $scratch -Force | Out-Null

# ---------------------------------------------------------------- Environment Doctor
Start-Suite 'Environment Doctor'

Test-Case 'valid project reports no errors' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'valid-project') -Format Json -PassThru
    Assert-Equal 0 $r.Summary.Errors "Errors: $(@($r.Findings | Where-Object Status -eq 'ERROR' | ForEach-Object Message) -join '; ')"
    Assert-HasFinding $r 'uproject.present' 'OK'
    Assert-HasFinding $r 'uproject.valid' 'OK'
    Assert-HasFinding $r 'agent.config' 'OK'
    Assert-Equal '5.7' $r.Metadata.EngineAssociation
}

Test-Case 'missing .uproject is an ERROR' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'no-uproject') -Format Json -PassThru
    Assert-HasFinding $r 'uproject.present' 'ERROR'
    Assert-True ($r.Summary.Errors -gt 0) 'Expected at least one error.'
}

Test-Case 'malformed .uproject is an ERROR' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'broken-json-project') -Format Json -PassThru
    Assert-HasFinding $r 'uproject.valid' 'ERROR'
}

Test-Case 'non-existent path is an ERROR and stops early' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $scratch 'nope') -Format Json -PassThru
    Assert-HasFinding $r 'target.exists' 'ERROR'
}

Test-Case 'invalid agent config is an ERROR' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'bad-config-project') `
        -AgentConfigPath (Join-Path $fixtures 'invalid-config.json') -Format Json -PassThru
    Assert-HasFinding $r 'agent.config' 'ERROR'
}

Test-Case 'missing agent config path is an ERROR' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'valid-project') `
        -AgentConfigPath (Join-Path $scratch 'absent.json') -Format Json -PassThru
    Assert-HasFinding $r 'agent.config' 'ERROR'
}

Test-Case 'toolchain does not write into the inspected project' {
    $proj = Join-Path $fixtures 'valid-project'
    $before = @(Get-ChildItem -LiteralPath $proj -Recurse -File | Measure-Object).Count
    $null = Invoke-EnvironmentDoctor -ProjectPath $proj -Format Json -PassThru
    $after = @(Get-ChildItem -LiteralPath $proj -Recurse -File | Measure-Object).Count
    Assert-Equal $before $after 'The doctor must be read-only.'
}

# ---------------------------------------------------------------- Toolchain Integrity
Start-Suite 'Toolchain Integrity'

Test-Case 'matching checksum passes' {
    $r = Test-ToolchainIntegrity -ManifestPath (Join-Path $fixtures 'toolchain\toolchain-valid.json') -Format Json -PassThru
    Assert-Equal 0 $r.Summary.Errors 'Valid pin should produce no error.'
    Assert-HasFinding $r 'digest.match' 'OK'
    Assert-HasFinding $r 'license.declared' 'OK'
}

Test-Case 'wrong checksum raises unexpected modification' {
    $r = Test-ToolchainIntegrity -ManifestPath (Join-Path $fixtures 'toolchain\toolchain-badchecksum.json') -Format Json -PassThru
    Assert-HasFinding $r 'digest.match' 'ERROR'
    $hit = @($r.Findings | Where-Object { $_.Check -eq 'digest.match' -and $_.Status -eq 'ERROR' })[0]
    Assert-True ($hit.Message -like '*Unexpected modification detected*') "Unexpected message: $($hit.Message)"
}

Test-Case 'tampered artifact is detected at runtime' {
    # Copy the fixture, pin it, then modify the bytes behind the toolkit's back.
    $dir = Join-Path $scratch 'tamper'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $target = Join-Path $dir 'tool.bin'
    [System.IO.File]::WriteAllBytes($target, [byte[]](1, 2, 3, 4, 5))
    $manifest = New-ToolchainManifest -Name 'tamper' -OutputPath (Join-Path $dir 'm.json') `
        -Component @(@{ Id = 'tool'; Path = $target; License = 'Apache-2.0'; Version = '1.0.0' })

    $clean = Test-ToolchainIntegrity -ManifestPath $manifest -Format Json -PassThru
    Assert-Equal 0 $clean.Summary.Errors 'Freshly pinned artifact should verify.'

    Add-Content -LiteralPath $target -Value 'tampered' -Encoding UTF8
    $dirty = Test-ToolchainIntegrity -ManifestPath $manifest -Format Json -PassThru
    Assert-HasFinding $dirty 'digest.match' 'ERROR'
}

Test-Case 'missing artifact is an ERROR when required' {
    $r = Test-ToolchainIntegrity -ManifestPath (Join-Path $fixtures 'toolchain\toolchain-missing.json') -Format Json -PassThru
    Assert-HasFinding $r 'artifact.present' 'ERROR'
}

Test-Case 'absent license is a WARNING, not an error' {
    $r = Test-ToolchainIntegrity -ManifestPath (Join-Path $fixtures 'toolchain\toolchain-nolicense.json') -Format Json -PassThru
    Assert-HasFinding $r 'license.declared' 'WARNING'
    Assert-Equal 0 $r.Summary.Errors 'Missing license must not fail the run.'
}

Test-Case 'malformed manifest JSON is an ERROR' {
    $r = Test-ToolchainIntegrity -ManifestPath (Join-Path $fixtures 'toolchain\toolchain-malformed.json') -Format Json -PassThru
    Assert-HasFinding $r 'manifest.parse' 'ERROR'
}

Test-Case 'New-ToolchainManifest refuses a missing file' {
    $threw = $false
    try {
        New-ToolchainManifest -Name 'x' -OutputPath (Join-Path $scratch 'never.json') `
            -Component @(@{ Id = 'ghost'; Path = (Join-Path $scratch 'ghost.bin') }) | Out-Null
    }
    catch { $threw = $true }
    Assert-True $threw 'Expected New-ToolchainManifest to throw for a missing file.'
}

# ---------------------------------------------------------------- Governance Gate
Start-Suite 'Agent Governance Gate'

Test-Case 'APPROVED document is accepted as authoritative' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-valid.json') `
        -Topic 'input-mapping' -Format Json -PassThru
    Assert-Equal 'AUTHORITATIVE' $r.Metadata.Decision
    Assert-True $r.Metadata.Authoritative 'Authoritative flag should be true.'
    Assert-Equal 0 $r.Summary.Errors
}

Test-Case 'INCOMING document is refused as authority' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-valid.json') `
        -Topic 'camera-tuning' -Format Json -PassThru
    Assert-Equal 'REFUSED_INCOMING' $r.Metadata.Decision
    Assert-False $r.Metadata.Authoritative 'INCOMING must never be authoritative.'
    Assert-HasFinding $r 'authority.resolve' 'ERROR'
}

Test-Case 'SUPERSEDED document is refused' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-valid.json') `
        -Topic 'legacy-input' -Format Json -PassThru
    Assert-Equal 'REFUSED_NOT_ACTIVE' $r.Metadata.Decision
    Assert-False $r.Metadata.Authoritative
}

Test-Case 'ARCHIVED document is refused' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-valid.json') `
        -Topic 'old-notes' -Format Json -PassThru
    Assert-Equal 'REFUSED_NOT_ACTIVE' $r.Metadata.Decision
    Assert-False $r.Metadata.Authoritative
}

Test-Case 'two APPROVED documents produce AUTHORITY_CONFLICT' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-conflict.json') `
        -Topic 'shared-topic' -Format Json -PassThru
    Assert-Equal 'AUTHORITY_CONFLICT' $r.Metadata.Decision
    Assert-False $r.Metadata.Authoritative 'The gate must not pick a winner.'
    Assert-Equal 2 @($r.Metadata.Conflicts).Count
}

Test-Case 'APPROVED wins over INCOMING on the same topic' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-mixed.json') `
        -Topic 'mixed-topic' -Format Json -PassThru
    Assert-Equal 'AUTHORITATIVE' $r.Metadata.Decision
}

Test-Case 'undeclared topic is not invented into authority' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-valid.json') `
        -Topic 'does-not-exist' -Format Json -PassThru
    Assert-Equal 'NOT_DECLARED' $r.Metadata.Decision
    Assert-False $r.Metadata.Authoritative
}

Test-Case 'status outside the model is an ERROR' {
    $r = Get-AuthorityStatus -IndexPath (Join-Path $fixtures 'governance\governance-badstatus.json') `
        -Topic 'weird' -Format Json -PassThru
    Assert-Equal 'INVALID_STATUS' $r.Metadata.Decision
    Assert-HasFinding $r 'status.model' 'ERROR'
}

# ---------------------------------------------------------------- Report contract
Start-Suite 'Report contract'

Test-Case 'JSON output round-trips' {
    $r = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'valid-project') -Format Json -PassThru
    $json = $r | ConvertTo-Json -Depth 8
    $back = $json | ConvertFrom-Json
    Assert-Equal $r.Summary.Errors $back.Summary.Errors
    Assert-Equal 'environment-doctor' $back.Capability
}

Test-Case 'Markdown output is produced' {
    $out = Join-Path $scratch 'report.md'
    $null = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'valid-project') -Format Markdown -OutputPath $out -PassThru
    Assert-True (Test-Path -LiteralPath $out) 'Markdown report should exist.'
    $text = Get-Content -LiteralPath $out -Raw
    Assert-True ($text -like '*| Status | Check | Message |*') 'Markdown table header missing.'
}

Test-Case 'exit code reflects errors' {
    $ok = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'valid-project') -Format Json -PassThru
    $ko = Invoke-EnvironmentDoctor -ProjectPath (Join-Path $fixtures 'no-uproject') -Format Json -PassThru
    Assert-Equal 0 (Get-UatExitCode -Report $ok)
    Assert-Equal 1 (Get-UatExitCode -Report $ko)
}

# ---------------------------------------------------------------- Cleanup
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

$summary = Get-TestSummary
Write-Host ''
Write-Host '=============================================================='
Write-Host " TOTAL: $($summary.Total) | PASSED: $($summary.Passed) | FAILED: $($summary.Failed)"
Write-Host '=============================================================='

if ($summary.Failed -gt 0) {
    Write-Host ''
    Write-Host 'Failed tests:'
    $script:TestResults | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host " - [$($_.Suite)] $($_.Test): $($_.Message)"
    }
    exit 1
}
exit 0
