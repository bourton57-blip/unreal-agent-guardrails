# unreal-agent-guardrails - New-ToolchainManifest
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

function New-ToolchainManifest {
    <#
    .SYNOPSIS
        Creates a toolchain manifest by pinning the SHA-256 of files already on disk.

    .DESCRIPTION
        Pinning must be a deliberate act. This function computes digests from real
        bytes so the manifest always describes artifacts that actually exist, and
        it refuses to invent a version, revision or license.

        Supply at least one component. Every component requires -Path and -Id.
        License is strongly recommended: components without a declared license are
        reported as a WARNING by Test-ToolchainIntegrity.

    .PARAMETER OutputPath
        Where the manifest JSON is written. Defaults to .\toolchain.json.

    .PARAMETER Name
        Logical name of the toolchain.

    .PARAMETER Component
        One or more component hashtables. Recognized keys:
          Id (required), Path (required), Kind, Version, Revision, License, LicenseUrl, Source, Required.

    .PARAMETER Force
        Overwrite an existing manifest.

    .EXAMPLE
        New-ToolchainManifest -Name 'my-mcp' -Component @(
            @{ Id = 'mcp-server'; Path = '.\vendor\server.exe'; License = 'Apache-2.0'; Version = '1.0.0' }
        )

    .OUTPUTS
        The manifest path.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [string]$OutputPath = '.\toolchain.json',
        [Parameter(Mandatory)][string]$Name,

        [Parameter(Mandatory)]
        [object[]]$Component,

        [switch]$Force
    )

    $resolvedOut = [System.IO.Path]::GetFullPath($OutputPath)
    if ((Test-Path -LiteralPath $resolvedOut) -and -not $Force) {
        throw "Manifest already exists: $resolvedOut. Use -Force to overwrite."
    }

    $baseDir = Split-Path -Parent $resolvedOut
    if (-not $baseDir) { $baseDir = '.' }

    $entries = @()
    foreach ($c in $Component) {
        $id = [string]$c['Id']
        $path = [string]$c['Path']

        if ([string]::IsNullOrWhiteSpace($id)) { throw 'Every component requires a non-empty Id.' }
        if ([string]::IsNullOrWhiteSpace($path)) { throw "Component '$id' requires a non-empty Path." }

        $absolute = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path (Get-Location).Path $path }
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            throw "Component '$id' points at a file that does not exist: $absolute"
        }

        $relative = $path
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            $full = [System.IO.Path]::GetFullPath($path)
            try { $relative = [System.IO.Path]::GetRelativePath($baseDir, $full) } catch { $relative = $path }
        }

        $entry = [ordered]@{
            id         = $id
            kind       = if ($c.ContainsKey('Kind')) { [string]$c['Kind'] } else { 'file' }
            version    = if ($c.ContainsKey('Version')) { [string]$c['Version'] } else { $null }
            revision   = if ($c.ContainsKey('Revision')) { [string]$c['Revision'] } else { $null }
            license    = if ($c.ContainsKey('License')) { [string]$c['License'] } else { $null }
            licenseUrl = if ($c.ContainsKey('LicenseUrl')) { [string]$c['LicenseUrl'] } else { $null }
            source     = if ($c.ContainsKey('Source')) { [string]$c['Source'] } else { $null }
            path       = $relative
            sha256     = Get-UatFileSha256 -Path $absolute
            required   = if ($c.ContainsKey('Required')) { [bool]$c['Required'] } else { $true }
        }
        $entries += $entry
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        name          = $Name
        generatedBy   = 'unreal-agent-guardrails'
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        components    = $entries
    }

    if ($PSCmdlet.ShouldProcess($resolvedOut, 'Write toolchain manifest')) {
        $dir = Split-Path -Parent $resolvedOut
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $json = $manifest | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $resolvedOut -Value $json -Encoding UTF8
        Write-Host "Manifest written to $resolvedOut ($($entries.Count) component(s) pinned)."
    }

    return $resolvedOut
}
