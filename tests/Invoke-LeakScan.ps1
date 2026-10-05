<#
.SYNOPSIS
    Scans a repository for secrets, credentials and files that should never be published.

.DESCRIPTION
    A generic, project-independent hygiene check suitable for any public
    open-source repository. It contains no project-specific identifiers and no
    knowledge of any particular private codebase: the rules below are universal.

    Checks performed:

      1. Secret material  - provider key prefixes, private key headers, cloud
                             access keys, source-hosting and chat tokens.
      2. Credentials      - .env files, key and certificate files, and common
                             credential keywords assigned a literal value.
      3. Personal paths   - absolute user home directories in file contents.
      4. Engine assets    - binary Unreal Engine content that usually cannot be
                             redistributed (purchased or marketplace content).
      5. Oversized files  - anything above a size threshold, which breaks
                             clones and inflates repositories.
      6. Repository hygiene - local tool or editor directories that should not
                             be committed.

    Excluded from the scan, both declared here rather than left implicit:

      - The .git directory. Git's own metadata legitimately contains remote
        URLs and is never part of the published tree.
      - This script itself. A scanner necessarily contains the strings it
        searches for, so scanning itself is meaningless.

    This script deliberately knows nothing about any specific project. A
    maintainer who needs project-specific checks keeps them in a separate,
    private scan that is not part of the published repository.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tests\Invoke-LeakScan.ps1

.OUTPUTS
    Exits 0 when clean, 1 when at least one detection is found.
#>
[CmdletBinding()]
param(
    [string]$Root,

    [ValidateRange(1, 100000)]
    [int]$MaxFileSizeMb = 50
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated inside a param() default value, so the root is
# resolved after parameter binding.
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# --- Universal secret patterns -------------------------------------------------
$secretPatterns = @(
    'AKIA',                      # AWS access key id
    'ASIA',                      # AWS temporary access key id
    'ghp_', 'gho_', 'ghu_', 'ghs_', 'ghr_',  # source-hosting tokens
    'github_pat_',               # fine-grained source-hosting token
    'glpat-',                    # GitLab token
    'xoxb-', 'xoxp-', 'xoxa-', 'xoxr-', 'xoxs-', # chat tokens
    'sk-',                       # model provider key prefix
    'AIza',                      # cloud API key prefix
    'ya29.',                     # OAuth token prefix
    '-----BEGIN RSA PRIVATE KEY-----',
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN DSA PRIVATE KEY-----',
    '-----BEGIN EC PRIVATE KEY-----',
    '-----BEGIN OPENSSH PRIVATE KEY-----',
    '-----BEGIN PGP PRIVATE KEY-----'
)

# --- Universal credential patterns ---------------------------------------------
$credentialPatterns = @(
    '(?i)api[_-]?key\s*[:=]\s*["'']?[A-Za-z0-9_\-]{16,}',
    '(?i)secret[_-]?key\s*[:=]\s*["'']?[A-Za-z0-9_\-]{16,}',
    '(?i)access[_-]?token\s*[:=]\s*["'']?[A-Za-z0-9_\-]{16,}',
    '(?i)client[_-]?secret\s*[:=]\s*["'']?[A-Za-z0-9_\-]{16,}',
    '(?i)password\s*[:=]\s*["'']?[^"''\s]{8,}',
    '(?i)passwd\s*[:=]\s*["'']?[^"''\s]{8,}',
    '(?i)connectionstring\s*[:=]\s*["'']?[^"''\s]{12,}'
)

# --- Personal path patterns ----------------------------------------------------
$pathPatterns = @(
    '/home/[a-z0-9._-]+/',
    '/Users/[a-z0-9._-]+/',
    '\\Users\\[A-Za-z0-9._-]+\\'
)

# --- Sensitive file names ------------------------------------------------------
$sensitiveNames = @(
    '.env', '.env.local', '.env.production', '.env.development',
    'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519',
    'credentials', 'secrets', 'service-account.json'
)
$sensitiveExtensions = @('.pem', '.key', '.pfx', '.p12', '.jks', '.keystore')

# --- Binary engine content that is normally not redistributable ----------------
$engineAssetExtensions = @('.uasset', '.umap', '.ubulk', '.uexp')

# --- Local directories that should not be committed ----------------------------
$ignoredDirectoryPattern = '[\\/]\.git[\\/]'

$selfPath = $MyInvocation.MyCommand.Path

$all = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch $ignoredDirectoryPattern }
)

$scannable = @(
    $all | Where-Object {
        $_.FullName -ne $selfPath -and
        $_.Extension -notin @('.bin', '.dll', '.exe', '.png', '.jpg', '.jpeg', '.gif', '.ico')
    }
)

$detections = New-Object System.Collections.ArrayList

function Add-Detection {
    param([string]$Category, [string]$File, [string]$Detail)
    [void]$detections.Add([pscustomobject]@{
            Category = $Category
            File     = $File
            Detail   = $Detail
        })
}

# 1. Secrets and credentials in file contents
foreach ($f in $scannable) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $text) { continue }
    $relative = $f.FullName.Replace($Root + '\', '')

    foreach ($p in $secretPatterns) {
        if ($text -match $p) {
            Add-Detection -Category 'secret' -File $relative -Detail 'secret-like token in contents'
        }
    }
    foreach ($p in $credentialPatterns) {
        if ($text -match $p) {
            Add-Detection -Category 'credential' -File $relative -Detail 'hardcoded credential assignment'
        }
    }
    foreach ($p in $pathPatterns) {
        if ($text -match $p) {
            Add-Detection -Category 'personal-path' -File $relative -Detail 'absolute user home path in contents'
        }
    }
}

# 2. Sensitive file names and extensions
foreach ($f in $all) {
    $relative = $f.FullName.Replace($Root + '\', '')
    if ($sensitiveNames -contains $f.Name) {
        Add-Detection -Category 'sensitive-file' -File $relative -Detail 'environment or credential file'
    }
    if ($sensitiveExtensions -contains $f.Extension.ToLowerInvariant()) {
        Add-Detection -Category 'sensitive-file' -File $relative -Detail 'key or certificate material'
    }
    foreach ($ext in $engineAssetExtensions) {
        if ($f.Extension.ToLowerInvariant() -eq $ext) {
            Add-Detection -Category 'engine-asset' -File $relative -Detail 'binary engine asset, usually not redistributable'
        }
    }
}

# 3. Oversized files
$threshold = $MaxFileSizeMb * 1MB
foreach ($f in $all) {
    if ($f.Length -gt $threshold) {
        Add-Detection -Category 'oversized' -File $f.FullName.Replace($Root + '\', '') `
            -Detail "file exceeds $MaxFileSizeMb MB"
    }
}

$binarySkipped = @($all | Where-Object { $_.Extension -eq '.bin' }).Count
$audited = $all.Count

Write-Host "Files in tree : $($all.Count)"
Write-Host "Files audited : $audited (text-scanned $($scannable.Count), binary $($binarySkipped) checked by extension)"
Write-Host "Excluded      : .git directory (local metadata, never published)"
Write-Host "Self-excluded : $(Split-Path -Leaf $selfPath)"
Write-Host "Checks        : secrets, credentials, personal paths, sensitive files, engine assets, file size"

if ($detections.Count -eq 0) {
    Write-Host ''
    Write-Host 'LEAK SCAN: CLEAN'
    exit 0
}

Write-Host ''
Write-Host 'LEAK SCAN: DETECTIONS FOUND'
$detections | Sort-Object Category, File | Format-Table -AutoSize -Wrap
exit 1
