# Contributing to unreal-agent-guardrails

Thanks for considering a contribution. This project is young and its
maintenance burden should stay small, so the bar is mostly about **honesty and
reproducibility** rather than volume.

## Ground rules

1. **Tests are required.** Any new capability ships with tests in
   `tests/Invoke-Tests.ps1`. A capability without tests will not be merged.
2. **Fixtures must be synthetic.** Never add real game content, real project
   data, engine assets, marketplace assets, or anything derived from a private
   project. Fixtures must be generatable by a reader from the repository alone.
3. **Do not overstate.** If a feature is partial, say so in the README, and put
   it under `Roadmap` rather than in the feature list. This project's value
   depends on its claims being exactly true.
4. **No new dependencies without discussion.** The zero-dependency property is
   a feature. Propose it in an issue before adding it.
5. **Read-only by default.** Capabilities inspect. If a capability must write,
   it must be explicit, opt-in, and covered by a test proving the read-only
   path is unaffected.

## Development loop

```powershell
# Run the full suite (no Unreal Engine required)
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1

# Parse-check every script before pushing
Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
    $err = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
    if ($err) { Write-Host "SYNTAX ERROR: $($_.Name) line $($err[0].Extent.StartLineNumber)" }
}
```

## Style

- Target Windows PowerShell 5.1. Do not use PowerShell 7-only syntax.
- `Set-StrictMode -Version 3.0` and explicit error handling are expected.
- Public functions need comment-based help with a synopsis, a description, a
  real example, and outputs.
- Findings use stable `Check` identifiers. Renaming one is a breaking change
  for anyone asserting on it in CI.

## Reporting a security issue

Please follow [SECURITY.md](SECURITY.md) rather than opening a public issue.
