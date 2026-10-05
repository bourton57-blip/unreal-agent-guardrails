# Security policy

## Reporting a vulnerability

**Use GitHub Private Vulnerability Reporting. Do not open a public issue.**

Once this repository is public, the maintainer will enable
**GitHub Private Vulnerability Reporting** (Settings -> Code security ->
Enable private vulnerability reporting). That gives you a private, authenticated
channel to submit a report directly to the maintainer, with no e-mail address
exposed anywhere in this repository.

To file a report:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the issue and submit.

You will receive an acknowledgement, and the report stays private between you
and the maintainer until a fix is published.

If private reporting is not yet enabled when you arrive, open a regular issue
that says only: *"Security report available on request — please open a private
channel."* Do not include technical details in a public issue.

## What to include

- the capability and exact command used;
- the toolkit version or commit;
- reproduction steps;
- the impact you believe it has;
- whether the issue affects the inspected project, the user's own files, or both.

## Scope

`unreal-agent-guardrails` is a local, read-mostly developer tool. It inspects
project directories, verifies file digests, and reads governance indexes.

## Security properties this project maintains

- **Read-only by default.** `Invoke-EnvironmentDoctor` and
  `Test-ToolchainIntegrity` never modify the paths they inspect. A test asserts
  this. Only `New-ToolchainManifest` and explicit `-OutputPath` writes create
  files, and they only write where the user pointed them.
- **No network access.** The toolkit performs no HTTP requests, downloads
  nothing, and phones home for nothing. Network access is entirely the user's,
  via their own artifact acquisition.
- **No credential handling.** The toolkit never reads, stores, requests or
  transmits secrets. Configuration files are parsed structurally, and secret
  values are neither required nor emitted.
- **No execution of inspected content.** The toolkit does not launch Unreal
  Engine, does not run scripts found in a target project, and does not evaluate
  the content it reads.
- **Manifest writes are guarded.** `New-ToolchainManifest` refuses to pin a file
  that does not exist, so a manifest always describes real artifacts.
- **No bundled third-party code.** There is no vendored source to audit, and no
  runtime module dependency. See `THIRD-PARTY-NOTICES.md`.

## An honest limit

Digest verification is **advisory, not a security boundary**. SHA-256 pinning
detects *unexpected modification* of a local artifact against a pin you
control. It does not defend against an attacker who can rewrite both the
artifact and the manifest.

## Out of scope

- Vulnerabilities in Unreal Engine itself.
- Vulnerabilities in third-party MCP servers or Unreal plugins. The toolkit
  bundles none of them; report those to their own maintainers.
- Reports that rely on a user deliberately pointing the toolkit at a path they
  do not own or have permission to read.
- Social engineering or phishing, which this local tool has no exposure to.
