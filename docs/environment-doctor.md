# Environment Doctor

`Invoke-EnvironmentDoctor` answers one question: **is this Unreal project
directory in a state where an agent can safely be pointed at it?**

It is deliberately conservative. It reports what it can verify on disk and
refuses to guess about anything else.

## Usage

```powershell
Invoke-EnvironmentDoctor -ProjectPath C:\work\MyGame

# Machine-readable, written to a file
Invoke-EnvironmentDoctor -ProjectPath C:\work\MyGame -Format Json -OutputPath .\doctor.json

# As a script
powershell -ExecutionPolicy Bypass -File .\uat.ps1 doctor -ProjectPath C:\work\MyGame
```

## Parameters

| Parameter | Default | Purpose |
|---|---|---|
| `-ProjectPath` | *required* | Directory containing the `.uproject`. |
| `-AgentConfigPath` | *(none)* | Validate this agent/MCP config explicitly. |
| `-LargeFileThresholdMb` | `50` | Report files above this size. |
| `-Format` | `Text` | `Text`, `Json` or `Markdown`. |
| `-OutputPath` | *(none)* | Write the rendered report to a file. |
| `-PassThru` | off | Return the report object to the pipeline. |

## Checks

| Check | Severity when failing | Meaning |
|---|---|---|
| `target.exists` | ERROR | The path exists and is a readable directory. |
| `uproject.present` | ERROR | Exactly one `.uproject` exists. Multiple is a WARNING. |
| `uproject.valid` | ERROR / WARNING | The file parses as JSON. A missing `EngineAssociation` is a WARNING. |
| `folder.Source` | INFO | Conventional folder present. |
| `folder.Config` | INFO | Conventional folder present. |
| `folder.Plugins` | INFO | Conventional folder present. |
| `folder.Content` | INFO | Conventional folder present. |
| `config.defaultengine` | WARNING | `Config/DefaultEngine.ini` exists. |
| `agent.config` | ERROR / OK / INFO | An agent configuration was found and is usable. |
| `repo.largefiles` | WARNING | Oversized files outside ignored folders. |

### Severity rationale

- **`.uproject` problems are ERRORs.** Without a valid descriptor there is no
  project to work on, so continuing would be misleading.
- **Missing optional folders are INFO, not WARNING.** A content-only project
  legitimately has no `Source` folder. Treating that as a problem would train
  users to ignore the output.
- **A missing `DefaultEngine.ini` is a WARNING**, not an error, because the
  project is still workable, but agents lose visibility into engine settings.
- **A missing agent config is INFO.** Not every project uses an agent, so this
  must not read as a defect.

## What it never does

- It never requires or inspects proprietary assets, and never opens any engine asset file.
- It never writes to the inspected project. A test asserts this.
- It never launches Unreal Engine.
- It never executes anything found in the target project.

## Agent configuration detection

When `-AgentConfigPath` is not supplied, these locations are probed:

`.codex/config.toml`, `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`,
`AGENTS.md`, `CLAUDE.md`.

When `-AgentConfigPath` is supplied, that file is validated and a problem is an
ERROR.

### A note on TOML

`.json` agent configurations are parsed properly. `.toml` configurations
receive a **structural check only**: the file must be non-empty, and its
`[section]` headers and `mcp_servers` entries are counted. Shipping a full TOML
parser would add a dependency to a project whose value proposition is having
none, and a section/key count is enough to catch the common failure of a
truncated or mis-saved file.

This limitation is stated in the report's own `Detail` field, so it cannot be
mistaken for full validation.
