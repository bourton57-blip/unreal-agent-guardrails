# unreal-agent-guardrails - minimal zero-dependency test harness
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.
#
# Why not Pester? Pester is not installed by default, and the version bundled
# with Windows (3.x) has a different syntax from current Pester. A 100-line
# harness keeps the test suite runnable on a clean machine with no prerequisites,
# which matters for a tool whose whole point is reproducibility.

$script:TestResults = New-Object System.Collections.ArrayList
$script:CurrentTest = $null

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    $script:CurrentTest = $Name
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $sw.Stop()
        [void]$script:TestResults.Add([pscustomobject]@{
                Suite = $script:CurrentSuite; Test = $Name; Status = 'PASS'; Message = ''; DurationMs = $sw.ElapsedMilliseconds
            })
        Write-Host "  [PASS] $Name"
    }
    catch {
        $sw.Stop()
        [void]$script:TestResults.Add([pscustomobject]@{
                Suite = $script:CurrentSuite; Test = $Name; Status = 'FAIL'; Message = $_.Exception.Message; DurationMs = $sw.ElapsedMilliseconds
            })
        Write-Host "  [FAIL] $Name"
        Write-Host "         $($_.Exception.Message)"
    }
    finally {
        $script:CurrentTest = $null
    }
}

function Start-Suite {
    param([Parameter(Mandatory)][string]$Name)
    $script:CurrentSuite = $Name
    Write-Host ''
    Write-Host "--- $Name ---"
}

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [string]$Message = 'Assertion failed.')
    if (-not $Condition) { throw $Message }
}

function Assert-False {
    param([Parameter(Mandatory)][bool]$Condition, [string]$Message = 'Assertion failed.')
    if ($Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = '')
    if ($Expected -ne $Actual) {
        throw "Expected '$Expected' but got '$Actual'. $Message"
    }
}

function Assert-NotNull {
    param($Value, [string]$Message = 'Expected a non-null value.')
    if ($null -eq $Value) { throw $Message }
}

function Assert-HasFinding {
    <#
    .SYNOPSIS
        Asserts that a report contains a finding for a check with a given status.
    #>
    param(
        [Parameter(Mandatory)]$Report,
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('OK', 'INFO', 'WARNING', 'ERROR')][string]$Status
    )
    $match = @($Report.Findings | Where-Object { $_.Check -eq $Check -and $_.Status -eq $Status })
    if ($match.Count -eq 0) {
        $actual = (@($Report.Findings | ForEach-Object { "$($_.Check)=$($_.Status)" })) -join ', '
        throw "Expected finding '$Check' with status '$Status'. Actual: $actual"
    }
}

function Get-TestSummary {
    [pscustomobject]@{
        Total  = $script:TestResults.Count
        Passed = @($script:TestResults | Where-Object { $_.Status -eq 'PASS' }).Count
        Failed = @($script:TestResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    }
}
