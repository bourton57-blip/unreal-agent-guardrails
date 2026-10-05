# unreal-agent-guardrails - Get-AuthorityStatus (Agent Governance Gate)
# Licensed under the Apache License, Version 2.0. See LICENSE at the repository root.

$script:UatGovernanceStatuses = @('INCOMING', 'APPROVED', 'SUPERSEDED', 'ARCHIVED')

function Get-UatGovernanceDocument {
    <#
    .SYNOPSIS
        Reads a property from a governance document, tolerating its absence.
    #>
    param(
        [Parameter(Mandatory)][psobject]$Document,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Document.PSObject.Properties.Name -contains $Name) { return $Document.$Name }
    return $null
}

function Get-AuthorityStatus {
    <#
    .SYNOPSIS
        Decides whether a governance document may be used as authoritative input.

    .DESCRIPTION
        This is the Agent Governance Gate. It answers one question: may an agent
        treat this document as the authoritative specification?

        Document statuses:
          INCOMING   - Raw, unvalidated material. NEVER authoritative.
          APPROVED   - Reviewed by a human. Authoritative.
          SUPERSEDED - Replaced by a newer APPROVED document. Not authoritative.
          ARCHIVED   - Withdrawn from the active flow. Not authoritative.

        When two or more APPROVED documents claim authority over the same topic,
        the gate returns AUTHORITY_CONFLICT and refuses to choose. The conflict is
        escalated to a human; this function never resolves it.

        The gate is deliberately generic: it contains no domain knowledge, no
        project data and no decision logic beyond the status model above.

    .PARAMETER IndexPath
        Path to a governance index JSON document. See schemas/governance-index.schema.json.

    .PARAMETER Topic
        The topic whose authority should be resolved.

    .PARAMETER Format
        Output format. Text (default), Json, or Markdown.

    .PARAMETER OutputPath
        Optional file to write the rendered report to.

    .PARAMETER PassThru
        Return the report object to the pipeline.

    .EXAMPLE
        Get-AuthorityStatus -IndexPath '.\governance.json' -Topic 'input-mapping'

    .OUTPUTS
        PSCustomObject when -PassThru is used. The report Metadata carries
        Authoritative (bool), Decision (string) and Conflicts (array).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$IndexPath,

        [Parameter(Mandatory, Position = 1)]
        [string]$Topic,

        [ValidateSet('Text', 'Json', 'Markdown')]
        [string]$Format = 'Text',

        [string]$OutputPath,

        [switch]$PassThru
    )

    $report = New-UatReport -Capability 'governance-gate' -Target "$IndexPath#$Topic"

    $decision = 'UNKNOWN'
    $authoritative = $false
    $conflicts = @()

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'index.present' -Status 'ERROR' `
                -Message 'Governance index does not exist.' -Detail "Path: $IndexPath" `
                -Remediation 'Provide a governance index describing document statuses.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'index.present' -Status 'OK' `
            -Message 'Governance index found.' -Detail "Path: $IndexPath")

    $raw = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8
    $index = $null
    try {
        $index = $raw | ConvertFrom-Json
    }
    catch {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'index.parse' -Status 'ERROR' `
                -Message 'Governance index is not valid JSON.' -Detail $_.Exception.Message `
                -Remediation 'Regenerate the index; a malformed index cannot grant authority.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    $documents = Get-UatGovernanceDocument -Document $index -Name 'documents'
    if ($null -eq $documents) {
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'index.documents' -Status 'ERROR' `
                -Message 'Governance index declares no documents array.' `
                -Remediation 'Declare a "documents" array with topic, status and path entries.')
        Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
        if ($PassThru) { return $report }
        return
    }

    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'index.documents' -Status 'OK' `
            -Message "Governance index declares $(@($documents).Count) document(s).")

    $candidates = @($documents | Where-Object { [string](Get-UatGovernanceDocument -Document $_ -Name 'topic') -eq $Topic })

    if ($candidates.Count -eq 0) {
        $decision = 'NOT_DECLARED'
        Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'authority.resolve' -Status 'WARNING' `
                -Message "No document is declared for topic '$Topic'." `
                -Remediation 'Declare the topic, or treat it as out of scope. Do not invent an authority.')
    }
    else {
        # Validate declared statuses are part of the model
        $invalid = @()
        foreach ($d in $candidates) {
            $st = [string](Get-UatGovernanceDocument -Document $d -Name 'status')
            if ($script:UatGovernanceStatuses -notcontains $st) { $invalid += "$Topic => '$st'" }
        }
        if ($invalid.Count -gt 0) {
            $decision = 'INVALID_STATUS'
            Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'status.model' -Status 'ERROR' `
                    -Message 'One or more documents declare a status outside the allowed model.' `
                    -Detail (($invalid -join '; ') + " | allowed: $($script:UatGovernanceStatuses -join ', ')") `
                    -Remediation 'Use only INCOMING, APPROVED, SUPERSEDED or ARCHIVED.')
        }
        else {
            $approved = @($candidates | Where-Object { [string](Get-UatGovernanceDocument -Document $_ -Name 'status') -eq 'APPROVED' })

            if ($approved.Count -gt 1) {
                $decision = 'AUTHORITY_CONFLICT'
                $authoritative = $false
                $conflicts = @($approved | ForEach-Object {
                        [pscustomobject]@{
                            topic    = $Topic
                            path     = [string](Get-UatGovernanceDocument -Document $_ -Name 'path')
                            version  = [string](Get-UatGovernanceDocument -Document $_ -Name 'version')
                            approvedOn = [string](Get-UatGovernanceDocument -Document $_ -Name 'approvedOn')
                        }
                    })
                Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'authority.resolve' -Status 'ERROR' `
                        -Message "AUTHORITY_CONFLICT: $($approved.Count) APPROVED documents claim authority over topic '$Topic'." `
                        -Detail (($conflicts | ForEach-Object { "$($_.path) (v$($_.version), $($_.approvedOn))" }) -join '; ') `
                        -Remediation 'A human must decide which document is authoritative. Do not merge or compromise them.')
            }
            elseif ($approved.Count -eq 1) {
                $doc = $approved[0]
                $decision = 'AUTHORITATIVE'
                $authoritative = $true
                $docPath = [string](Get-UatGovernanceDocument -Document $doc -Name 'path')
                $version = [string](Get-UatGovernanceDocument -Document $doc -Name 'version')
                $approvedOn = [string](Get-UatGovernanceDocument -Document $doc -Name 'approvedOn')
                Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'authority.resolve' -Status 'OK' `
                        -Message "Topic '$Topic' resolves to an APPROVED document." `
                        -Detail "path=$docPath version=$version approvedOn=$approvedOn" `
                        -Remediation 'Use only this document as the specification for this topic.')
            }
            else {
                # No APPROVED document: fall back to the strongest declared status
                $statuses = @($candidates | ForEach-Object { [string](Get-UatGovernanceDocument -Document $_ -Name 'status') })
                $statuses = @($statuses | Select-Object -Unique)

                if ($statuses -contains 'INCOMING' -and $statuses.Count -eq 1) {
                    $decision = 'REFUSED_INCOMING'
                    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'authority.resolve' -Status 'ERROR' `
                            -Message "Topic '$Topic' is INCOMING and is therefore NOT authoritative." `
                            -Detail 'Raw research is never a specification. It carries no implementation authority.' `
                            -Remediation 'A human reviewer must validate and promote it to APPROVED before it can be used.')
                }
                else {
                    $decision = 'REFUSED_NOT_ACTIVE'
                    Add-UatFinding -Report $report -Finding (New-UatFinding -Check 'authority.resolve' -Status 'ERROR' `
                            -Message "Topic '$Topic' has no active APPROVED document." `
                            -Detail ("Declared statuses: " + ($statuses -join ', ')) `
                            -Remediation 'SUPERSEDED and ARCHIVED documents are not authoritative. Escalate to a human.')
                }
            }
        }
    }

    $report.Metadata | Add-Member -NotePropertyName Topic -NotePropertyValue $Topic -Force
    $report.Metadata | Add-Member -NotePropertyName Decision -NotePropertyValue $decision -Force
    $report.Metadata | Add-Member -NotePropertyName Authoritative -NotePropertyValue $authoritative -Force
    $report.Metadata | Add-Member -NotePropertyName Conflicts -NotePropertyValue $conflicts -Force

    Write-UatReport -Report $report -Format $Format -OutputPath $OutputPath
    if ($PassThru) { return $report }
}
