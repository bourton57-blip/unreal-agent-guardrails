@{
    RootModule        = 'unreal-agent-guardrails.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '5e9f260f-1606-4319-89fb-eb7c4bcdacdd'
    Author            = 'bourton57-blip'
    CompanyName       = 'bourton57-blip'
    Copyright         = 'Licensed under the Apache License, Version 2.0.'
    Description       = 'Safety guardrails for AI coding agents on Unreal Engine projects: environment preflight, toolchain integrity verification, and an authority gate for unvalidated research.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Invoke-EnvironmentDoctor',
        'Test-ToolchainIntegrity',
        'New-ToolchainManifest',
        'Get-AuthorityStatus',
        'Get-UatExitCode'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('UnrealEngine', 'Unreal', 'Codex', 'MCP', 'Governance', 'Guardrails', 'AgentSafety', 'Tooling')
            LicenseUri = 'https://www.apache.org/licenses/LICENSE-2.0'
        }
    }
}
