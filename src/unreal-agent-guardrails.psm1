# unreal-agent-guardrails - module entry point
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.
#
# Design notes:
#  - Targets Windows PowerShell 5.1, which is what Unreal Engine developers on
#    Windows have by default. No dependency on PowerShell 7 is required.
#  - There are no external module dependencies. Everything is built on the .NET
#    base class library so the toolkit stays installable without a package manager.
#  - Dot-sourcing is used instead of a nested module layout to keep the source
#    readable for contributors who are new to PowerShell.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$srcRoot = $PSScriptRoot

# Order matters: helpers first, then private implementations, then public API.
. (Join-Path $srcRoot 'Private\Common.ps1')
. (Join-Path $srcRoot 'Private\Report.ps1')
. (Join-Path $srcRoot 'Private\EnvironmentDoctor.ps1')
. (Join-Path $srcRoot 'Private\ToolchainIntegrity.ps1')

. (Join-Path $srcRoot 'Public\Invoke-EnvironmentDoctor.ps1')
. (Join-Path $srcRoot 'Public\Test-ToolchainIntegrity.ps1')
. (Join-Path $srcRoot 'Public\New-ToolchainManifest.ps1')
. (Join-Path $srcRoot 'Public\Get-AuthorityStatus.ps1')

Export-ModuleMember -Function @(
    'Invoke-EnvironmentDoctor',
    'Test-ToolchainIntegrity',
    'New-ToolchainManifest',
    'Get-AuthorityStatus',
    'Get-UatExitCode'
)
