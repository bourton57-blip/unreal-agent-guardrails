# Agent Governance Gate

`Get-AuthorityStatus` answers one question: **may an agent treat this document
as the authoritative specification for this topic?**

It is the smallest useful expression of a governance rule, and it is
intentionally incapable of making decisions on your behalf.

## Usage

```powershell
Get-AuthorityStatus -IndexPath .\governance.json -Topic input-mapping

# From a script
powershell -ExecutionPolicy Bypass -File .\uat.ps1 authority -IndexPath .\governance.json -Topic input-mapping
```

## The status model

| Status | Authoritative? | Meaning |
|---|---|---|
| `INCOMING` | **No** | Raw, unvalidated material. Never a specification. |
| `APPROVED` | **Yes** | Reviewed and accepted by a human. |
| `SUPERSEDED` | **No** | Replaced by a newer approved document. |
| `ARCHIVED` | **No** | Withdrawn from the active flow. |

A status outside this set is an ERROR. The gate refuses to interpret an
unrecognised status rather than guessing at its intent.

## The index

```json
{
  "schemaVersion": 1,
  "documents": [
    { "topic": "input-mapping", "status": "APPROVED",   "path": "specs/input-mapping.md", "version": "1.0.0", "approvedOn": "2026-01-10", "approvedBy": "human-reviewer" },
    { "topic": "camera-tuning", "status": "INCOMING",   "path": "incoming/camera.md",     "version": "0.1.0" },
    { "topic": "old-notes",      "status": "ARCHIVED",   "path": "archive/old-notes.md",   "version": "0.2.0" }
  ]
}
```

See [`schemas/governance-index.schema.json`](../schemas/governance-index.schema.json).

## Decisions

| Decision | Authoritative | When |
|---|---|---|
| `AUTHORITATIVE` | yes | Exactly one `APPROVED` document claims the topic. |
| `REFUSED_INCOMING` | no | The topic is only `INCOMING`. |
| `REFUSED_NOT_ACTIVE` | no | The topic is only `SUPERSEDED` and/or `ARCHIVED`. |
| `AUTHORITY_CONFLICT` | no | Two or more `APPROVED` documents claim the topic. |
| `NOT_DECLARED` | no | No document mentions the topic. |
| `INVALID_STATUS` | no | A document declares a status outside the model. |

## Why a conflict is never resolved here

When two approved documents claim the same topic, the gate returns
`AUTHORITY_CONFLICT`, lists both candidates, and stops.

This is a design decision rather than a missing feature. An automated tie-break
would be worse than no answer, because it would launder an unresolved human
disagreement into apparent certainty. Merging the two documents, or picking the
newer one, would silently fabricate an authority that no human ever granted.

The correct next step is always a human decision followed by an explicit index
update, so the resolution is itself recorded and reviewable.

```
[FAIL] authority.resolve: AUTHORITY_CONFLICT: 2 APPROVED documents claim authority over topic 'shared-topic'.
          -> specs/a.md (v1.0.0, 2026-01-10); specs/b.md (v1.1.0, 2026-02-02)
          fix: A human must decide which document is authoritative. Do not merge or compromise them.
```

## Undeclared topics

A topic that no document mentions returns `NOT_DECLARED` and a WARNING rather
than an ERROR: the topic may simply be out of scope. Either way, the gate never
invents an authority, because a plausible default is exactly the failure mode
this capability exists to prevent.

## Machine-readable metadata

With `-PassThru`, `Metadata` carries:

- `Topic`
- `Decision`
- `Authoritative` (boolean)
- `Conflicts` (array of the competing documents, empty unless a conflict exists)

The CLI exits `0` only for `AUTHORITATIVE`, so a conflict fails a CI step
automatically.

## Genericity

The gate contains no domain knowledge, no project data, and no content
decisions. It encodes only the four-state model and the refusal to arbitrate.
The same index works for input mapping, save systems, AI behaviour, or anything
else a project needs to govern.
