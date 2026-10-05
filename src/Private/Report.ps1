# unreal-agent-guardrails - Report rendering
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

function ConvertTo-UatText {
    <#
    .SYNOPSIS
        Renders a report as human-readable terminal text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Report)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=' * 78)
    [void]$sb.AppendLine(" unreal-agent-guardrails | $($Report.Capability)")
    [void]$sb.AppendLine('=' * 78)
    if ($Report.Target) { [void]$sb.AppendLine(" Target    : $($Report.Target)") }
    [void]$sb.AppendLine(" Generated : $($Report.GeneratedAtUtc)")
    [void]$sb.AppendLine(" Status    : $($Report.Status)")
    [void]$sb.AppendLine('')

    $icon = @{ 'OK' = '[ OK ]'; 'INFO' = '[INFO]'; 'WARNING' = '[WARN]'; 'ERROR' = '[FAIL]' }
    foreach ($f in $Report.Findings) {
        [void]$sb.AppendLine(" $($icon[[string]$f.Status]) $($f.Check): $($f.Message)")
        if ($f.Detail) { [void]$sb.AppendLine("          -> $($f.Detail)") }
        if ($f.Remediation) { [void]$sb.AppendLine("          fix: $($f.Remediation)") }
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(" Summary: $($Report.Summary.Total) check(s) | $($Report.Summary.Passed) passed | $($Report.Summary.Info) info | $($Report.Summary.Warnings) warning(s) | $($Report.Summary.Errors) error(s)")
    [void]$sb.AppendLine('=' * 78)
    $sb.ToString()
}

function ConvertTo-UatMarkdown {
    <#
    .SYNOPSIS
        Renders a report as Markdown, suitable for a PR comment or an audit trail.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Report)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# unreal-agent-guardrails report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **Capability**: $($Report.Capability)")
    if ($Report.Target) { [void]$sb.AppendLine("- **Target**: ``$($Report.Target)``") }
    [void]$sb.AppendLine("- **Generated (UTC)**: $($Report.GeneratedAtUtc)")
    [void]$sb.AppendLine("- **Status**: **$($Report.Status)**")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Status | Check | Message |')
    [void]$sb.AppendLine('|---|---|---|')
    foreach ($f in $Report.Findings) {
        $msg = ([string]$f.Message) -replace '\|', '\|'
        [void]$sb.AppendLine("| $($f.Status) | $($f.Check) | $msg |")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Summary:** $($Report.Summary.Total) check(s), $($Report.Summary.Errors) error(s), $($Report.Summary.Warnings) warning(s).")
    $sb.ToString()
}

function Write-UatReport {
    <#
    .SYNOPSIS
        Renders a report in the requested format, to the host and/or a file.
    .DESCRIPTION
        This is the single sink used by every public capability so that terminal,
        JSON and Markdown output can never drift apart.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Report,
        [ValidateSet('Text', 'Json', 'Markdown')][string]$Format = 'Text',
        [string]$OutputPath
    )

    switch ($Format) {
        'Json'     { $text = ($Report | ConvertTo-Json -Depth 8) }
        'Markdown' { $text = ConvertTo-UatMarkdown -Report $Report }
        default    { $text = ConvertTo-UatText -Report $Report }
    }

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $OutputPath -Value $text -Encoding UTF8
        Write-Host "Report written to $OutputPath"
    }
    else {
        Write-Host $text
    }
}
