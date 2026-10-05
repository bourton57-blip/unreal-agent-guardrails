# unreal-agent-guardrails

**Safety guardrails for AI coding agents on Unreal Engine projects.**

`unreal-agent-guardrails` helps you prepare, verify and audit an Unreal Engine +
AI-agent environment *before* you let an agent modify your project. It is a
small, dependency-free PowerShell toolkit built around one idea:

> An agent must never be allowed to turn unvalidated material, or its own
> guesswork, into an authoritative decision.

The toolkit does not generate code and does not replace your editor. It answers
three narrow, checkable questions, and it answers them with evidence rather
than opinion.

---

## The problem

Most agentic coding guidance assumes the agent's output can be reviewed after
the fact. That assumption breaks down on Unreal projects:

- **Unreal state is a large binary graph.** Blueprints, maps and assets cannot
  be reviewed in a diff. A plausible-looking change can silently invalidate
  weeks of work.
- **A missing precondition is discovered too late.** A misconfigured MCP server
  or a drifted toolchain binary is usually noticed mid-task, not before it.
- **Success is easy to claim and hard to prove.** "The file changed", "the
  plugin loaded", "the MCP connection worked" and "the tool is usable" are four
  different claims. Conflating them is how unverified work gets reported as done.
- **Authority is implicit.** Without an explicit rule, an agent can treat raw
  research notes as if they were a specification.

These are process problems, not model problems. They are addressable with
mechanisms, and mechanisms are what this repository provides.

---

## What the MVP actually does today

Three capabilities, all executable and all covered by tests.

### 1. Environment Doctor

Verifies that a project directory is ready for agent-assisted work. Checks the
target path, discovers and validates the `.uproject` (including JSON
validity and `EngineAssociation`), verifies conventional folders, checks
`Config/DefaultEngine.ini`, detects and optionally validates an agent/MCP
configuration, and flags oversized files that would break a shared repository.

It never requires proprietary assets and never writes to the inspected project.

### 2. Toolchain Integrity

Verifies pinned external artifacts against a declarative manifest. Each
component pins an id, kind, version, revision, license and SHA-256 digest.
The checker confirms the artifact exists and that its computed digest still
matches the pin, and it reports a mismatch as an explicit
`Unexpected modification detected` error.

`New-ToolchainManifest` builds a manifest by hashing files that actually exist
on disk, so a manifest can never describe an artifact you do not have.

### 3. Agent Governance Gate

Decides whether a document may be treated as an authoritative specification,
using a four-state model:

| Status | Authoritative? | Meaning |
|---|---|---|
| `INCOMING` | **No** | Raw, unvalidated material. Never a specification. |
| `APPROVED` | **Yes** | Reviewed by a human. |
| `SUPERSEDED` | **No** | Replaced by a newer approved document. |
| `ARCHIVED` | **No** | Withdrawn from the active flow. |

If two `APPROVED` documents claim authority over the same topic, the gate
returns `AUTHORITY_CONFLICT`, refuses to pick a winner, and escalates to a
human. **The toolkit never resolves the conflict itself.** This is a
deliberate design choice, not a missing feature.

---

## Requirements

- Windows PowerShell **5.1** (bundled with Windows) or PowerShell 7+
- No other dependencies. No module downloads, no package manager, no NuGet.

Because Windows PowerShell blocks unsigned scripts by default in some
environments, scripts are invoked with an explicit bypass flag in the
examples below. On a managed workstation, follow your organisation's policy
rather than disabling protection globally.

---

## Installation

```powershell
git clone https://github.com/bourton57-blip/unreal-agent-guardrails.git
cd unreal-agent-guardrails
```

That is the whole installation. There is nothing to build.

### Use as a module

```powershell
Import-Module .\src\unreal-agent-guardrails.psd1
```

### Use as a command line tool

```powershell
powershell -ExecutionPolicy Bypass -File .\uat.ps1 <command> [options]
```

---

## Usage

### Check an Unreal project before handing it to an agent

```powershell
powershell -ExecutionPolicy Bypass -File .\uat.ps1 doctor -ProjectPath C:\work\MyGame
```

```
==============================================================================
 unreal-agent-guardrails | environment-doctor
==============================================================================
 Status    : INFO

 [ OK ] uproject.present: .uproject file found.
 [ OK ] uproject.valid: .uproject parses as JSON.
          -> EngineAssociation: 5.7
 [WARN] config.defaultengine: Config/DefaultEngine.ini is missing.
 [INFO] folder.Plugins: Folder 'Plugins' is absent (optional).
 [ OK ] repo.largefiles: No file exceeds 50 MB outside ignored folders.

 Summary: 10 check(s) | 7 passed | 3 info | 0 warning(s) | 0 error(s)
==============================================================================
```

### Validate an agent/MCP configuration explicitly

```powershell
powershell -ExecutionPolicy Bypass -File .\uat.ps1 doctor -ProjectPath C:\work\MyGame -AgentConfigPath C:\work\MyGame\.mcp.json
```

### Verify pinned toolchain artifacts

```powershell
powershell -ExecutionPolicy Bypass -File .\uat.ps1 integrity -ManifestPath .\toolchain.json
```

### Ask whether a document is authoritative

```powershell
powershell -ExecutionPolicy Bypass -File .\uat.ps1 authority -IndexPath .\governance.json -Topic input-mapping
```

An `INCOMING` topic is refused:

```
 [FAIL] authority.resolve: Topic 'camera-tuning' is INCOMING and is therefore NOT authoritative.
          -> Raw research is never a specification. It carries no implementation authority.
          fix: A human reviewer must validate and promote it to APPROVED before it can be used.
```

### Create a toolchain manifest from files on disk

```powershell
New-ToolchainManifest -Name 'my-toolchain' -Component @(
    @{ Id = 'helper-tool'; Path = '.\vendor\helper.exe'; License = 'Apache-2.0'; Version = '1.0.0' }
)
```

---

## Output

Every capability emits a single normalized report with:

- a **status** (`OK`, `INFO`, `WARNING`, `ERROR`) and an overall status equal to
  the most severe finding;
- a **summary** with counts per severity;
- **findings**, each with a stable `Check` identifier, a message, an optional
  detail and an optional remediation;
- **capability-specific metadata** (for example `EngineAssociation`, or the
  governance `Decision` and `Authoritative` flags).

Three formats are available via `-Format Text | Json | Markdown`, and
`-OutputPath` writes the rendered report to a file. JSON output is stable and
suitable for CI assertions.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | No errors. Warnings may still be present. |
| `1` | At least one error. |

`uat.ps1 authority` exits `0` only when the resolved decision is
`AUTHORITATIVE`; every other outcome, including `AUTHORITY_CONFLICT`, exits `1`.

---

## Testing

The suite has **no external dependencies and requires no Unreal Engine
installation**. It runs against synthetic fixtures only.

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-Tests.ps1
```

Current status: **25 tests, 25 passing.**

The harness is intentionally hand-rolled (~100 lines) rather than Pester-based.
Pester is not installed by default, and the version bundled with Windows (3.x)
uses a different syntax from current Pester. A self-contained harness keeps the
suite runnable on a clean machine, which matters for a tool whose purpose is
reproducibility.

Covered scenarios include a valid project, a missing `.uproject`, malformed
`.uproject` JSON, an invalid agent configuration, a valid checksum, a wrong
checksum, an artifact tampered with at runtime, an `INCOMING` document refused
as authority, an `APPROVED` document accepted, and an authority conflict
detected.

---

## Project layout

```
unreal-agent-guardrails/
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ uat.ps1                     # CLI entry point
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ src/
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ unreal-agent-guardrails.psd1
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ unreal-agent-guardrails.psm1
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Private/                # internal helpers
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Public/                 # exported commands
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ tests/
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Invoke-Tests.ps1
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ TestHarness.ps1
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬Å¡   ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ fixtures/               # synthetic only
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ examples/                   # runnable samples
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ docs/
ÃƒÂ¢Ã¢â‚¬ÂÃ…â€œÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ schemas/
ÃƒÂ¢Ã¢â‚¬ÂÃ¢â‚¬ÂÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ PUBLICATION_AUDIT.md
```

---

## Limitations

Stated plainly, because a tool that oversells itself is worse than no tool.

**This MVP does not do any of the following, and does not claim to:**

- build Unreal projects automatically;
- compile or run Unreal Automation Tests;
- run a full Unreal Engine CI pipeline;
- perform automated gameplay testing;
- compare an implementation against a specification automatically;
- provide, bundle or vendor any MCP server or Unreal plugin;
- make design decisions, resolve authority conflicts, or approve documents.

Additional known limits:

- **Windows-focused.** Written for Windows PowerShell 5.1. The file-system and
  hashing calls should work on macOS and Linux, but neither platform is tested.
- **TOML configs are checked structurally, not parsed.** A full TOML parse
  would need a dependency, so `.toml` agent configs are checked for section and
  key structure only. This is documented in the report detail rather than
  presented as full validation.
- **The doctor does not launch Unreal Engine.** It inspects the project on disk.

---

## Roadmap

Planned, not implemented. Listed separately so nothing here can be mistaken for
a shipped feature.

- **Reverse verification:** check that a change actually satisfies the
  specification it claims to implement.
- **Structured report schema** with a published JSON Schema and stable
  finding identifiers.
- **Pester-compatible test suite** as an optional target, keeping the
  dependency-free harness as the default.
- **Cross-platform validation** for PowerShell 7 on macOS and Linux.
- **Optional strict mode** where warnings also fail a run.
- **Governance index generator** to scaffold and validate an index from a folder.
- **Unreal Automation Test integration** behind an explicit opt-in, for
  projects that already have a reproducible test harness.

---

## Repository hygiene scan

`tests/Invoke-LeakScan.ps1` is a generic hygiene check that any repository can
use. It looks for secret material, hardcoded credentials, personal paths,
sensitive files, non-redistributable engine asset extensions, and oversized
files.

It contains no project-specific identifier and no knowledge of any private
codebase. Checks tied to a particular project belong in a separate scan that is
not committed, which is how this toolkit is itself released.

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Invoke-LeakScan.ps1
```

Exits `0` when clean and `1` on any detection. See
[docs/leak-scan-control-set.md](docs/leak-scan-control-set.md) for what it
checks and which two exclusions it declares.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). New capabilities need tests, and tests
need fixtures that are synthetic and free of third-party or proprietary content.

## Security

See [SECURITY.md](SECURITY.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
