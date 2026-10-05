# Report model

Every capability emits the same normalized report structure, so a consumer can
assert on findings without special-casing the capability that produced them.

## Structure

```json
{
  "SchemaVersion": 1,
  "Tool": "unreal-agent-guardrails",
  "Capability": "environment-doctor",
  "GeneratedAtUtc": "2026-10-05T13:49:41.4159127Z",
  "Target": "C:\\work\\MyGame",
  "Status": "WARNING",
  "Summary": { "Total": 10, "Passed": 8, "Info": 1, "Warnings": 1, "Errors": 0 },
  "Findings": [
    {
      "Check": "config.defaultengine",
      "Status": "WARNING",
      "Message": "Config/DefaultEngine.ini is missing.",
      "Detail": "",
      "Remediation": "Without it, agents cannot see project-level engine settings."
    }
  ],
  "Metadata": { "EngineAssociation": "5.7" }
}
```

## Severity model

Severities are ordered `OK` < `INFO` < `WARNING` < `ERROR`. A report's `Status`
is the **maximum** severity among its findings, so a report is never more
optimistic than its worst finding.

| Severity | Meaning |
|---|---|
| `OK` | The check passed. |
| `INFO` | Neutral observation. Not a defect. |
| `WARNING` | A real concern that does not block work. |
| `ERROR` | The check failed. Work should not proceed. |

## Finding identifiers

Every finding carries a stable `Check` identifier, for example
`uproject.valid` or `digest.match`. These are part of the tool's contract: they
are what a CI assertion should match against. Renaming one is a breaking change.

## Metadata per capability

| Capability | Metadata keys |
|---|---|
| `environment-doctor` | `EngineAssociation` |
| `toolchain-integrity` | *(none)* |
| `governance-gate` | `Topic`, `Decision`, `Authoritative`, `Conflicts` |

## Formats and exit codes

`-Format Text | Json | Markdown` and `-OutputPath` are available on every
capability. `Get-UatExitCode` maps a report to a process exit code:

| Report | Exit code |
|---|---|
| No errors | `0` |
| At least one error | `1` |

Warnings deliberately do not fail a run, so the tool can be introduced into a
pipeline as a non-blocking signal. A strict mode is listed in the roadmap rather
than assumed.
