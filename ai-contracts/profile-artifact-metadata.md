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
- A `published` date (article listings display and sort by it; when absent they
  fall back to `created`).
- Language-specific summaries `summary_de` and `summary_en` (article listings
  prefer the language variant and fall back to the neutral `summary`).
- Translation provenance via `translation_of` (ID of the artifact this one was
  translated from), `translation_source_digest`, and `translation_divergence`.
  All three are only valid on a translation; `translation_of` must reference an
  original, not another translation.
- A `skills` array of skill slugs an article demonstrates, kept separate from
  `tags`. Each skill gets a generated overview page listing its articles.

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
  each article and the `recent.adoc` listing fragment under the articles
  `generated/lists` directory.
- The standalone article listing pages under the articles `lists/` directory are
  generated too, even though they sit outside `**/generated/`. They are written
  where they are published so the site build renders them as ordinary sources.
  They are Git-ignored and must not be edited by hand.
- Public-channel assumptions are explicit when they are not known.
- Prefer meaningful, discriminating tags. Ubiquitous tags (for example `profile`)
  carry no relatedness signal and trigger a validator warning.
- `previous`/`next` reference existing Articles and stay mutually consistent.
- `language` is a concrete language and matches the artifact's location: the
  default language `de` at the root of its tree, every other language below its
  own `<lang>/` subtree. There is no `mixed` value.
- The original of a translation may be in any language. The default language is
  the fallback target, not the assumed source language.
- Every artifact declares `metadata_version`, and it is one of the versions
  `metamodel/profile-artifact.schema.yaml` accepts. An absent version is an
  error, not the initial version: content that says nothing about its contract
  would pass against a checkout too old to understand it.

## Contract Version

`metadata_version` says which version of this contract an artifact was written
against. The accepted versions live in one place, the `metadata_version` enum in
`metamodel/profile-artifact.schema.yaml`. The validator reads them from that file
in its own checkout, so content validated through a checkout of this repository
is judged by that checkout's contract rather than by whatever metamodel sits
beside the content.

New artifacts declare the current version. Copy it from the enum or from
`templates/write-article/article.profile.yaml`; do not invent a value.

Raise the version when a change to this contract would make older metadata
wrong rather than merely incomplete — a field that changes meaning, a value that
stops being accepted, a rule that reinterprets what is already written. Adding
an optional field does not need a new version, because existing artifacts remain
true under it.

Raising it is a deliberate act with three parts, all in the same change: add the
new version to the schema enum, migrate the artifacts that are being moved to
it, and decide whether the previous version stays in the enum. Dropping a
version from the enum is what makes unmigrated content fail by name, so drop it
only when nothing that must still validate declares it.

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
