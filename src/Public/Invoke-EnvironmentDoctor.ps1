# unreal-agent-guardrails - Invoke-EnvironmentDoctor
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

function Invoke-EnvironmentDoctor {
    <#
    .SYNOPSIS
        Verifies that an Unreal Engine project directory is ready for agent-assisted work.

    .DESCRIPTION
        Performs generic, project-agnostic checks and never requires proprietary
        assets. It reports findings at four severities (OK, INFO, WARNING, ERROR)
        and produces a machine-readable report suitable for CI gating.

        Checks performed:
          1.  The target path exists and is readable.
          2.  A .uproject file is discoverable (ERROR when absent).
          3.  The .uproject parses as JSON and exposes EngineAssociation.
          4.  Conventional project folders (Source, Config, Plugins, Content) exist.
          5.  Config/DefaultEngine.ini is present.
          6.  An agent/MCP configuration is detected, or the supplied one is valid.
          7.  No oversized tracked file is present (Git hygiene).

        The tool never writes to the inspected project.

    .PARAMETER ProjectPath
        Path to the Unreal project directory (the one containing the .uproject).

    .PARAMETER AgentConfigPath
        Optional path to an agent/MCP configuration file to validate explicitly.
        When omitted, common configuration locations are probed.

    .PARAMETER LargeFileThresholdMb
        Files larger than this are reported as a warning. Default 50.

    .PARAMETER Format
        Output format. Text (default), Json, or Markdown.

    .PARAMETER OutputPath
        Optional file to write the rendered report to, instead of the host.

    .PARAMETER PassThru
        Return the report object to the pipeline.

    .EXAMPLE
        Invoke-EnvironmentDoctor -ProjectPath 'C:\work\MyGame'

    .EXAMPLE
        Invoke-EnvironmentDoctor -ProjectPath 'C:\work\MyGame' -Format Json -OutputPath '.\doctor.json'

    .OUTPUTS
        PSCustomObject when -PassThru is used.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ProjectPath,

        [string]$AgentConfigPath,

        [ValidateRange(1, 100000)]
        [int]$LargeFileThresholdMb = 50,

        [ValidateSet('Text', 'Json', 'Markdown')]
        [string]$Format = 'Text',

        [string]$OutputPath,

        [switch]$PassThru
    )

    $report = New-UatReport -Capability 'environment-doctor' -Target $ProjectPath

    # 1. Target path
    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'target.exists' -Status 'ERROR' `
                -Message 'Project path does not exist.' `
                -Detail "Path: $ProjectPath" `
                -Remediation 'Create or restore the project directory, then re-run.')
    }
    elseif (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'target.exists' -Status 'ERROR' `
                -Message 'Project path is not a directory.' -Detail "Path: $ProjectPath")
    }
    else {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'target.exists' -Status 'OK' `
                -Message 'Project directory exists and is readable.' -Detail "Path: $ProjectPath")
    }

    if ($report.Summary.Errors -gt 0) {
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    # 2. .uproject discovery
    $uproject = @(Get-ChildItem -LiteralPath $ProjectPath -Filter '*.uproject' -File -ErrorAction SilentlyContinue)
    if ($uproject.Count -eq 0) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.present' -Status 'ERROR' `
                -Message 'No .uproject file found in the project root.' `
                -Remediation 'Confirm the path is the folder that contains the .uproject file.')
    }
    elseif ($uproject.Count -gt 1) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.present' -Status 'WARNING' `
                -Message "Multiple .uproject files found ($($uproject.Count)); continuing with the first." `
                -Detail ($uproject.Name -join ', ') `
                -Remediation 'Keep exactly one .uproject per project directory.')
        $uproject = @($uproject[0])
    }
    else {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.present' -Status 'OK' `
                -Message '.uproject file found.' -Detail $uproject[0].Name)
    }

    # 3. .uproject validity
    if ($uproject.Count -eq 1) {
        $parsed = Test-UatUprojectFile -Path $uproject[0].FullName
        if (-not $parsed.Valid) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.valid' -Status 'ERROR' `
                    -Message 'The .uproject file is not a valid JSON document.' `
                    -Detail $parsed.Error `
                    -Remediation 'Restore the .uproject from version control and re-run.')
        }
        elseif ($parsed.EngineAssociation) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.valid' -Status 'OK' `
                    -Message '.uproject parses as JSON.' -Detail "EngineAssociation: $($parsed.EngineAssociation)")
            $report.Metadata | Add-Member -NotePropertyName EngineAssociation -NotePropertyValue $parsed.EngineAssociation -Force
        }
        else {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'uproject.valid' -Status 'WARNING' `
                    -Message '.uproject parses as JSON but declares no EngineAssociation.' `
                    -Remediation 'Set EngineAssociation so agents can reason about the expected engine version.')
        }
    }

    # 4. Conventional folders
    foreach ($folder in @('Source', 'Config', 'Plugins', 'Content')) {
        $exists = Test-Path -LiteralPath (Join-Path $ProjectPath $folder) -PathType Container
        if ($exists) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check "folder.$folder" -Status 'OK' `
                    -Message "Folder '$folder' is present.")
        }
        else {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check "folder.$folder" -Status 'INFO' `
                    -Message "Folder '$folder' is absent (optional)." `
                    -Detail 'Absence is normal for a content-only or code-only project.')
        }
    }

    # 5. DefaultEngine.ini
    $defaultIni = Join-Path (Join-Path $ProjectPath 'Config') 'DefaultEngine.ini'
    if (Test-Path -LiteralPath $defaultIni -PathType Leaf) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'config.defaultengine' -Status 'OK' `
                -Message 'Config/DefaultEngine.ini is present.')
    }
    else {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'config.defaultengine' -Status 'WARNING' `
                -Message 'Config/DefaultEngine.ini is missing.' `
                -Remediation 'Without it, agents cannot see project-level engine settings.')
    }

    # 6. Agent / MCP configuration
    if ($AgentConfigPath) {
        $cfg = Get-UatAgentConfigInfo -Path $AgentConfigPath
        if (-not $cfg.Exists) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'agent.config' -Status 'ERROR' `
                    -Message 'The supplied agent configuration file does not exist.' -Detail "Path: $AgentConfigPath")
        }
        elseif ($cfg.Error) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'agent.config' -Status 'ERROR' `
                    -Message 'The supplied agent configuration file is not usable.' `
                    -Detail $cfg.Error `
                    -Remediation 'Fix or regenerate the configuration before letting an agent work on the project.')
        }
        else {
            $status = if ($cfg.Format -like 'unknown*') { 'INFO' } else { 'OK' }
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'agent.config' -Status $status `
                    -Message "Agent configuration is present and readable ($($cfg.Format))." `
                    -Detail $cfg.Detail)
        }
    }
    else {
        $candidates = @('.codex/config.toml', '.mcp.json', '.cursor/mcp.json', '.vscode/mcp.json', 'AGENTS.md', 'CLAUDE.md')
        $found = @()
        foreach ($rel in $candidates) {
            $candidatePath = Join-Path $ProjectPath ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { $found += $rel }
        }
        if ($found.Count -gt 0) {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'agent.config' -Status 'OK' `
                    -Message 'An agent configuration was detected.' -Detail ($found -join ', '))
        }
        else {
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'agent.config' -Status 'INFO' `
                    -Message 'No agent configuration detected in the project.' `
                    -Detail ('Checked: ' + ($candidates -join ', ')) `
                    -Remediation 'Optional. Add one if you want the project to declare its agent tooling explicitly.')
        }
    }

    # 7. Oversized files
    $large = @(Get-UatProjectLargeFiles -Root $ProjectPath -ThresholdMb $LargeFileThresholdMb)
    if ($large.Count -gt 0) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'repo.largefiles' -Status 'WARNING' `
                -Message "$($large.Count) file(s) exceed ${LargeFileThresholdMb} MB and are not in an ignored folder." `
                -Detail (($large | ForEach-Object { $_.Name }) -join ', ') `
                -Remediation 'Track binary assets with Git LFS or exclude them before sharing the repository.')
    }
    else {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'repo.largefiles' -Status 'OK' `
                -Message "No file exceeds ${LargeFileThresholdMb} MB outside ignored folders.")
    }

    Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
    if ($PassThru) { return $report }
}
