# unreal-agent-guardrails - Common helpers
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.
#
# Severity model: OK < INFO < WARNING < ERROR. A report's overall status is the
# maximum severity of its findings. This ordering is the single source of truth
# for both the report object and the rendered text/json/markdown output.

$script:UatSeverityRank = @{
    'OK'      = 0
    'INFO'    = 1
    'WARNING' = 2
    'ERROR'   = 3
}

function Get-UatSeverityName {
    <#
    .SYNOPSIS
        Maps a numeric severity rank back to its status name.
    .NOTES
        Hashtable enumeration order is not guaranteed, so the reverse mapping is
        resolved explicitly instead of relying on Keys ordering.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][int]$Rank)

    switch ($Rank) {
        3 { return 'ERROR' }
        2 { return 'WARNING' }
        1 { return 'INFO' }
        default { return 'OK' }
    }
}

function New-UatFinding {
    <#
    .SYNOPSIS
        Creates a single normalized finding.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][ValidateSet('OK', 'INFO', 'WARNING', 'ERROR')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [AllowNull()][AllowEmptyString()][string]$Detail,
        [AllowNull()][AllowEmptyString()][string]$Remediation
    )

    [pscustomobject]@{
        Check       = $Check
        Status      = $Status
        Message     = $Message
        Detail      = $Detail
        Remediation = $Remediation
    }
}

function New-UatReport {
    <#
    .SYNOPSIS
        Creates an empty report envelope shared by every capability.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Capability,
        [AllowNull()][AllowEmptyString()][string]$Target
    )

    [pscustomobject]@{
        SchemaVersion  = 1
        Tool           = 'unreal-agent-guardrails'
        Capability     = $Capability
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Target         = $Target
        Status         = 'OK'
        Summary        = [pscustomobject]@{
            Total    = 0
            Passed   = 0
            Info     = 0
            Warnings = 0
            Errors   = 0
        }
        Findings       = @()
        Metadata       = [pscustomobject]@{}
    }
}

function Add-UatFinding {
    <#
    .SYNOPSIS
        Appends a finding to a report and recomputes the aggregate status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Report,
        [Parameter(Mandatory)][psobject]$Finding
    )

    $existing = @()
    if ($null -ne $Report.Findings) { $existing = @($Report.Findings) }
    $Report.Findings = @($existing) + @($Finding)

    $rank = 0
    foreach ($f in $Report.Findings) {
        $r = $script:UatSeverityRank[[string]$f.Status]
        if ($r -gt $rank) { $rank = $r }
    }
    $Report.Status = Get-UatSeverityName -Rank $rank

    $Report.Summary.Total    = @($Report.Findings).Count
    $Report.Summary.Passed   = @($Report.Findings | Where-Object { $_.Status -eq 'OK' }).Count
    $Report.Summary.Info     = @($Report.Findings | Where-Object { $_.Status -eq 'INFO' }).Count
    $Report.Summary.Warnings = @($Report.Findings | Where-Object { $_.Status -eq 'WARNING' }).Count
    $Report.Summary.Errors   = @($Report.Findings | Where-Object { $_.Status -eq 'ERROR' }).Count
}

function Get-UatExitCode {
    <#
    .SYNOPSIS
        Maps a report to a process exit code: 0 = clean, 1 = errors present.
    .NOTES
        Warnings deliberately do not fail the run so this can be used in CI as a
        non-blocking signal until a project opts into strict mode.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][psobject]$Report)

    if ($Report.Summary.Errors -gt 0) { return 1 }
    return 0
}

function Get-UatFileSha256 {
    <#
    .SYNOPSIS
        Computes the SHA-256 of a file as an uppercase hex string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
