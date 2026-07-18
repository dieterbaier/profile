# AI Contract: Profile Artifact Metadata

## Purpose

Maintain personal profile content as validated Docs-as-Code source artifacts.
The contract applies to profile pages, CV sources, articles, short thoughts,
project entries, and reusable profile fragments under `src-content/profile`.

## Inputs

Required:

- A profile source file under `src-content/profile`.
- Existing sidecar metadata (`*.profile.yaml`) or YAML front matter when present.

Optional:

- Target publication channels.
- Audience constraints.
- Canonical publication URL.
- Relation targets to other profile artifacts.
- Article-series links via the optional `previous` and `next` fields (existing Article IDs).

## Output

When creating or materially changing a profile artifact, update or create
metadata that conforms to `metamodel/profile-artifact.schema.yaml`.

Use YAML front matter only for standalone source pages where it will not break
includes. Use `*.profile.yaml` sidecar metadata for include-heavy fragments such
as project entries.

## Invariants

- Source content remains authoritative.
- Metadata must not invent facts about the person, project, publication status,
  client, employer, or URL.
- Stable IDs are preserved after creation.
- Generated files under `**/generated/` are not edited manually, including the
  per-article navigation includes written to a `generated/` directory next to
  each article.
- Public-channel assumptions are explicit when they are not known.
- Prefer meaningful, discriminating tags. Ubiquitous tags (for example `profile`)
  carry no relatedness signal and trigger a validator warning.
- `previous`/`next` reference existing Articles and stay mutually consistent.

## Validation

Run:

```bash
./gradlew validateProfileMetamodel
```

When generated indexes are affected, run:

```bash
./gradlew generateProfileArtifacts
```

## Failure Behavior

If required facts are missing, leave a clear placeholder or ask for the missing
input. If metadata cannot be validated, stop before updating generated output.
