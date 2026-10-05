# unreal-agent-guardrails - Test-ToolchainIntegrity
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

function Test-ToolchainIntegrity {
    <#
    .SYNOPSIS
        Verifies pinned toolchain artifacts against a declarative manifest.

    .DESCRIPTION
        The manifest is a JSON document that pins every external artifact an agent
        workflow depends on: id, kind, version, revision, license and SHA-256.

        For each component the function verifies:
          1.  Required fields are present and well-formed.
          2.  The pinned digest is a valid 64-character SHA-256.
          3.  The artifact exists at the expected path (relative to -BasePath).
          4.  The artifact's computed SHA-256 matches the pinned digest.
          5.  A license is declared for every component.

        A digest mismatch is reported as an ERROR and described as an unexpected
        modification. This function only reads; it never installs or repairs.

        The integrity principle is generic and was re-implemented for this project.
        No third-party code is copied, vendored or re-licensed.

    .PARAMETER ManifestPath
        Path to the manifest JSON file.

    .PARAMETER BasePath
        Directory that relative component paths are resolved against.
        Defaults to the manifest's own directory.

    .PARAMETER Format
        Output format. Text (default), Json, or Markdown.

    .PARAMETER OutputPath
        Optional file to write the rendered report to.

    .PARAMETER PassThru
        Return the report object to the pipeline.

    .EXAMPLE
        Test-ToolchainIntegrity -ManifestPath '.\toolchain.json' -PassThru

    .OUTPUTS
        PSCustomObject when -PassThru is used.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ManifestPath,

        [string]$BasePath,

        [ValidateSet('Text', 'Json', 'Markdown')]
        [string]$Format = 'Text',

        [string]$OutputPath,

        [switch]$PassThru
    )

    $report = New-UatReport -Capability 'toolchain-integrity' -Target $ManifestPath

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.present' -Status 'ERROR' `
                -Message 'Manifest file does not exist.' -Detail "Path: $ManifestPath")
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.present' -Status 'OK' `
            -Message 'Manifest file found.' -Detail "Path: $ManifestPath")

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        $BasePath = Split-Path -Parent (Resolve-Path -LiteralPath $ManifestPath).Path
        if (-not $BasePath) { $BasePath = '.' }
    }

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $manifest = $null
    try {
        $manifest = $raw | ConvertFrom-Json
    }
    catch {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.parse' -Status 'ERROR' `
                -Message 'Manifest is not valid JSON.' -Detail $_.Exception.Message `
                -Remediation 'Regenerate the manifest with New-ToolchainManifest.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    if ($null -eq $manifest) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.parse' -Status 'ERROR' `
                -Message 'Manifest deserialized to null.' -Remediation 'Regenerate the manifest.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.parse' -Status 'OK' `
            -Message 'Manifest is valid JSON.')

    # Schema version
    $schemaVersion = Get-UatManifestComponent -Component $manifest -Name 'schemaVersion'
    if ($null -eq $schemaVersion) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.schemaVersion' -Status 'ERROR' `
                -Message 'Manifest does not declare schemaVersion.' `
                -Remediation 'Add "schemaVersion": 1 at the root of the manifest.')
    }
    elseif ($script:UatSupportedManifestSchemaVersions -notcontains [int]$schemaVersion) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.schemaVersion' -Status 'ERROR' `
                -Message "Unsupported manifest schemaVersion '$schemaVersion'." `
                -Detail "Supported: $($script:UatSupportedManifestSchemaVersions -join ', ')")
    }
    else {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.schemaVersion' -Status 'OK' `
                -Message "Manifest schemaVersion $schemaVersion is supported.")
    }

    # Components
    $components = Get-UatManifestComponent -Component $manifest -Name 'components'
    if ($null -eq $components -or @($components).Count -eq 0) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.components' -Status 'ERROR' `
                -Message 'Manifest declares no components.' `
                -Remediation 'Add at least one component with a pinned SHA-256.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'manifest.components' -Status 'OK' `
            -Message "Manifest declares $(@($components).Count) component(s).")

    $index = 0
    foreach ($component in $components) {
        $index++
        $id = [string](Get-UatManifestComponent -Component $component -Name 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { $id = "component#$index" }
        $label = "component[$index] '$id'"

        $sha256 = [string](Get-UatManifestComponent -Component $component -Name 'sha256')
        $relPath = [string](Get-UatManifestComponent -Component $component -Name 'path')
        $license = [string](Get-UatManifestComponent -Component $component -Name 'license')
        $version = [string](Get-UatManifestComponent -Component $component -Name 'version')
        $revision = [string](Get-UatManifestComponent -Component $component -Name 'revision')

        # Digest well-formed
        if (-not (Test-UatSha256Format -Value $sha256)) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'digest.format' -Status 'ERROR' `
                    -Message "$label does not declare a valid SHA-256 digest." `
                    -Detail "Value: '$sha256'" `
                    -Remediation 'Regenerate the digest with New-ToolchainManifest.')
            continue
        }

        # Path declared
        if ([string]::IsNullOrWhiteSpace($relPath)) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'artifact.path' -Status 'ERROR' `
                    -Message "$label declares no path." `
                    -Remediation 'Declare the artifact path relative to the manifest directory.')
            continue
        }

        $absolute = if ([System.IO.Path]::IsPathRooted($relPath)) { $relPath } else { Join-Path $BasePath $relPath }

        # Existence
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            $isRequired = Get-UatManifestComponent -Component $component -Name 'required'
            $status = if ($isRequired -eq $false) { 'WARNING' } else { 'ERROR' }
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'artifact.present' -Status $status `
                    -Message "$label is missing at '$relPath'." `
                    -Detail "Resolved: $absolute" `
                    -Remediation 'Fetch the pinned artifact, then re-run the integrity check.')
            continue
        }

        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'artifact.present' -Status 'OK' `
                -Message "$label is present." -Detail "Path: $relPath")

        # Digest match
        $actual = Get-UatFileSha256 -Path $absolute
        $expected = $sha256.ToUpperInvariant()
        if ($actual -eq $expected) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'digest.match' -Status 'OK' `
                    -Message "$label matches its pinned SHA-256." -Detail "sha256: $actual")
        }
        else {
            $versionDetail = if ($version) { "version=$version" } else { 'version=<unpinned>' }
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'digest.match' -Status 'ERROR' `
                    -Message "Unexpected modification detected: $label does not match its pinned SHA-256." `
                    -Detail "expected=$expected actual=$actual ($versionDetail)" `
                    -Remediation 'Do not trust this artifact. Restore the pinned version or re-pin deliberately.')
        }

    }

        # License
        if ([string]::IsNullOrWhiteSpace($license) -or $license -match '(?i)^(unknown|todo|n/?a)$') {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'license.declared' -Status 'WARNING' `
                    -Message "$label does not declare a license." `
                    -Remediation 'Record the upstream license so downstream users can comply.')
        }
        else {
            $revisionDetail = if ($revision) { "revision=$revision" } else { 'revision=<unpinned>' }
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'license.declared' -Status 'OK' `
                    -Message "$label declares license '$license'." -Detail $revisionDetail)
        }

    Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
    if ($PassThru) { return $report }
}
