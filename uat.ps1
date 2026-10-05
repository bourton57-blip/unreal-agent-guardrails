<#
.SYNOPSIS
    unreal-agent-guardrails command line entry point.

.DESCRIPTION
    A single dispatcher so users do not have to import the module first.

.PARAMETER Command
    doctor       Verify an Unreal project environment.
    integrity    Verify pinned toolchain artifacts.
    authority    Resolve whether a governance document is authoritative.
    manifest     Create a toolchain manifest from files on disk.
    version      Print the toolkit version.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uat.ps1 doctor -ProjectPath C:\work\MyGame

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uat.ps1 authority -IndexPath .\governance.json -Topic input-mapping
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('doctor', 'integrity', 'authority', 'manifest', 'version')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$ProjectPath,

    [string]$ManifestPath,
    [string]$IndexPath,
    [string]$Topic,
    [string]$OutputPath,
    [string]$AgentConfigPath,
    [ValidateSet('Text', 'Json', 'Markdown')][string]$Format = 'Text',
    [string]$ToolchainName
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'src\unreal-agent-guardrails.psd1') -Force

switch ($Command) {
    'doctor' {
        if (-not $ProjectPath) { throw 'doctor requires -ProjectPath.' }
        $r = Invoke-EnvironmentDoctor -ProjectPath $ProjectPath -AgentConfigPath $AgentConfigPath -Format $Format -OutputPath $OutputPath -PassThru
        exit (Get-UatExitCode -Report $r)
    }
    'integrity' {
        if (-not $ManifestPath) { throw 'integrity requires -ManifestPath.' }
        $r = Test-ToolchainIntegrity -ManifestPath $ManifestPath -Format $Format -OutputPath $OutputPath -PassThru
        exit (Get-UatExitCode -Report $r)
    }
    'authority' {
        if (-not $IndexPath -or -not $Topic) { throw 'authority requires -IndexPath and -Topic.' }
        $r = Get-AuthorityStatus -IndexPath $IndexPath -Topic $Topic -Format $Format -OutputPath $OutputPath -PassThru
        if ($r.Metadata.Decision -eq 'AUTHORITATIVE') { exit 0 }
        exit 1
    }
    'manifest' {
        if (-not $ToolchainName) { throw 'manifest requires -ToolchainName.' }
        $null = New-ToolchainManifest -Name $ToolchainName -OutputPath $(if ($OutputPath) { $OutputPath } else { '.\toolchain.json' })
        exit 0
    }
    'version' {
        Write-Host 'unreal-agent-guardrails 0.1.0'
        exit 0
    }
}
