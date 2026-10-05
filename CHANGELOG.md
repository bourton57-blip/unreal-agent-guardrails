# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

Initial MVP release candidate. Not yet published to any package registry or
public repository.

### Added

- **Environment Doctor** (`Invoke-EnvironmentDoctor`): verifies an Unreal
  project directory is ready for agent-assisted work. Detects and validates the
  `.uproject` (JSON validity and `EngineAssociation`), verifies conventional
  folders, checks `Config/DefaultEngine.ini`, detects and optionally validates
  an agent/MCP configuration, and flags oversized files.
- **Toolchain Integrity** (`Test-ToolchainIntegrity`): verifies pinned
  artifacts against a manifest using SHA-256, reporting a mismatch as
  `Unexpected modification detected`.
- **Toolchain manifest generation** (`New-ToolchainManifest`): pins artifacts by
  hashing files that exist on disk, and refuses to pin a missing file.
- **Agent Governance Gate** (`Get-AuthorityStatus`): resolves whether a
  document may be treated as authoritative, using the `INCOMING` / `APPROVED` /
  `SUPERSEDED` / `ARCHIVED` model, and returns `AUTHORITY_CONFLICT` when two
  approved documents claim the same topic.
- **Normalized report model** with `OK` / `INFO` / `WARNING` / `ERROR`
  severities, an overall status, per-severity counts, and stable finding
  identifiers.
- **Text, JSON and Markdown output**, plus optional file output and a documented
  exit-code contract for CI use.
- **CLI** (`uat.ps1`) with `doctor`, `integrity`, `authority`, `manifest` and
  `version` commands.
- **Zero-dependency test suite**: 25 tests against synthetic fixtures, requiring
  no Unreal Engine installation.
- Documentation for each capability, JSON Schemas for the manifest and governance
  index formats, and a publication audit.

### Fixed before release candidate 2

- The shipped leak scan no longer embeds any project-specific identifier. It is
  a generic hygiene check that applies to any repository. Project-specific
  confinement checking is performed separately and is not committed.
- The leak scan no longer walks the local `.git` directory, which contains
  remote URLs and is never published.
- The `.gitattributes` rule keeps binary fixtures byte-identical, so an
  end-of-line conversion can no longer invalidate a pinned checksum.
- `PUBLICATION_AUDIT.md` no longer records a commit SHA of the commit that
  contains it, and reports the file count verified from the Git tree.

### Known limitations

Documented in the README. In summary: no Unreal build automation, no automated
implementation-versus-specification comparison, no bundled MCP server or plugin,
Windows-only testing, and structural-only checking of TOML configurations.
