# unreal-agent-guardrails - Environment Doctor (internal implementation)
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

function Test-UatUprojectFile {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    $result = [pscustomobject]@{
        Valid            = $false
        EngineAssociation = $null
        Error            = $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    catch {
        $result.Error = "Unreadable: $($_.Exception.Message)"
        return $result
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        $result.Error = 'File is empty. A .uproject must be a JSON document.'
        return $result
    }

    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        $result.Error = "Invalid JSON: $($_.Exception.Message)"
        return $result
    }

    if ($null -eq $json) {
        $result.Error = 'Invalid JSON: document deserialized to null.'
        return $result
    }

    $result.Valid = $true
    if ($json.PSObject.Properties.Name -contains 'EngineAssociation') {
        $result.EngineAssociation = [string]$json.EngineAssociation
    }
    return $result
}

function Get-UatAgentConfigInfo {
    <#
    .SYNOPSIS
        Detects an agent/MCP configuration and performs a lightweight structural check.
    .DESCRIPTION
        JSON configs are parsed properly. TOML configs receive a structural
        section/key check only, because shipping a full TOML parser would add a
        dependency for a check that does not need one. The check is documented
        as such so nobody mistakes it for a validation guarantee.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param([Parameter(Mandatory)][string]$Path)

    $info = [pscustomobject]@{
        Exists   = $false
        Format   = 'unknown'
        Detail   = $null
        ServerCount = 0
        Error    = $null
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $info }
    $info.Exists = $true

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $info.Error = 'Configuration file is empty.'
        return $info
    }

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.json' {
            $info.Format = 'json'
            try {
                $json = $raw | ConvertFrom-Json
            }
            catch {
                $info.Error = "Invalid JSON: $($_.Exception.Message)"
                return $info
            }
            if ($null -eq $json) {
                $info.Error = 'Invalid JSON: document deserialized to null.'
                return $info
            }
            $props = @($json.PSObject.Properties.Name)
            $serverKeys = @($props | Where-Object { $_ -eq 'mcpServers' -or $_ -eq 'servers' -or $_ -eq 'mcp_servers' })
            if ($serverKeys.Count -gt 0) {
                $info.ServerCount = @($json.($serverKeys[0]).PSObject.Properties).Count
            }
            $info.Detail = "JSON parsed. Top-level keys: $($props -join ', ')."
        }
        '.toml' {
            $info.Format = 'toml (structural check only)'
            $sections = [regex]::Matches($raw, '(?m)^\s*\[([^\]]+)\]\s*$') | ForEach-Object { $_.Groups[1].Value }
            $info.ServerCount = @($sections | Where-Object { $_ -match '(?i)server' }).Count
            $info.Detail = "Sections: $($sections -join ', '). No full TOML validation is performed."
        }
        default {
            $info.Format = 'unknown'
            $info.Detail = 'Unrecognised extension; presence reported without parsing.'
        }
    }
    return $info
}

function Get-UatProjectLargeFiles {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$ThresholdMb = 50
    )

    $excluded = '\\(Binaries|DerivedDataCache|Intermediate|Saved|\.git)(\\|$)'
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $excluded } |
        Where-Object { $_.Length -gt ($ThresholdMb * 1MB) } |
        Select-Object -First 20
}
