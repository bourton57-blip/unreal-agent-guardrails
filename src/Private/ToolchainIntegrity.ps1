# unreal-agent-guardrails - Toolchain integrity (internal implementation)
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

$script:UatSupportedManifestSchemaVersions = @(1)

function Get-UatManifestComponent {
    <#
    .SYNOPSIS
        Reads a property from a manifest component, tolerating its absence.
    #>
    param(
        [Parameter(Mandatory)][psobject]$Component,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Component.PSObject.Properties.Name -contains $Name) {
        return $Component.$Name
    }
    return $null
}

function Test-UatSha256Format {
    <#
    .SYNOPSIS
        Validates that a value is a 64-character hexadecimal SHA-256 digest.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '^[0-9a-fA-F]{64}$')
}
