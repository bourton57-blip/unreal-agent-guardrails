# Toolchain integrity

`Test-ToolchainIntegrity` verifies that the external artifacts an agent workflow
depends on are exactly the ones that were pinned. It detects **unexpected
modification**, which is a different problem from "the file is missing" and
deserves a different message.

## Usage

```powershell
Test-ToolchainIntegrity -ManifestPath .\toolchain.json

# From a script
powershell -ExecutionPolicy Bypass -File .\uat.ps1 integrity -ManifestPath .\toolchain.json
```

## The manifest

```json
{
  "schemaVersion": 1,
  "name": "my-toolchain",
  "components": [
    {
      "id": "helper-tool",
      "kind": "file",
      "version": "1.0.0",
      "revision": "abc1234",
      "license": "Apache-2.0",
      "licenseUrl": "https://www.apache.org/licenses/LICENSE-2.0",
      "source": "https://example.org/helper-tool",
      "path": "vendor/helper-tool.exe",
      "sha256": "8BF790DEC3144B553C6B4F9EF3B0B46F2558F812A2012898058DBAC0D101D414",
      "required": true
    }
  ]
}
```

Relative `path` values are resolved against the manifest's directory, or against
`-BasePath` when supplied.

| Field | Required | Purpose |
|---|---|---|
| `id` | yes | Stable identifier used in report messages. |
| `path` | yes | Location of the artifact. |
| `sha256` | yes | 64-character hex digest. |
| `kind` | no | Artifact type, for readability. Default `file`. |
| `version` / `revision` | no | Human-readable pin context. |
| `license` | no | Upstream license. Absent is a WARNING. |
| `required` | no | `false` downgrades a missing artifact to WARNING. Default `true`. |

See [`schemas/toolchain-manifest.schema.json`](../schemas/toolchain-manifest.schema.json).

## Checks

| Check | Severity | Meaning |
|---|---|---|
| `manifest.present` | ERROR | The manifest file exists. |
| `manifest.parse` | ERROR | The manifest is valid JSON. |
| `manifest.schemaVersion` | ERROR | Declared and supported (currently `1`). |
| `manifest.components` | ERROR | At least one component is declared. |
| `digest.format` | ERROR | The pin is a well-formed SHA-256. |
| `artifact.path` | ERROR | A path is declared. |
| `artifact.present` | ERROR / WARNING | The artifact exists. WARNING only when `required: false`. |
| `digest.match` | OK / ERROR | Computed digest equals the pin. |
| `license.declared` | OK / WARNING | A license is declared for the component. |

## The distinction that matters

A missing artifact and a modified artifact are different failures with different
responses:

- **Missing** → fetch the pinned artifact, then re-verify.
- **Modified** → do not trust it. Restore the pinned version, or re-pin
  deliberately and record why.

The mismatch message is explicit about this:

```
[FAIL] digest.match: Unexpected modification detected: component[1] 'helper-tool' does not match its pinned SHA-256.
          expected=8BF790... expected actual=1A2B3C... (version=1.0.0)
          fix: Do not trust this artifact. Restore the pinned version or re-pin deliberately.
```

## Creating a manifest

`New-ToolchainManifest` computes digests from files that exist on disk:

```powershell
New-ToolchainManifest -Name 'my-toolchain' -OutputPath .\toolchain.json -Component @(
    @{ Id = 'helper-tool'; Path = '.\vendor\helper.exe'; License = 'Apache-2.0'; Version = '1.0.0' }
)
```

It refuses to pin a path that does not exist. This is deliberate: a manifest
should only ever describe artifacts you actually hold, otherwise pinning becomes
a way to record an intention rather than a fact.

## Licensing note

The integrity *principle* is generic and was re-implemented for this project.
**No third-party code is copied or vendored**, and nothing here is relicensed.
Third-party artifacts you choose to pin remain under their own licenses, which
is why an absent license is surfaced as a warning.
