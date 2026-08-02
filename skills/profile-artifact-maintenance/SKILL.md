---
name: profile-artifact-maintenance
description: Maintain profile artifact metadata, indexes, and validation for profile-dieterbaier sources. Use when creating or editing profile pages, CV content, articles, shorts, project entries, profile sidecar metadata, profile generators, or profile metamodel rules.
---

# Profile Artifact Maintenance

## Workflow

1. Read `general-semantic-contracts.md`.
2. Read `ai-contracts/profile-artifact-metadata.md`.
3. Inspect the affected source under `src-content/profile`.
4. Preserve existing content and stable profile artifact IDs.
5. Add or update metadata:
   - YAML front matter for standalone pages when safe.
   - `*.profile.yaml` sidecars for include-heavy fragments.
6. Keep metadata aligned with `metamodel/profile-artifact.schema.yaml`.
7. Run `./gradlew validateProfileMetamodel`.
8. Run `./gradlew generateProfileArtifacts` when indexes or generated views need
   refreshing.

## Rules

- Treat profile content as product source, not generated output.
- Do not invent project facts, employment facts, dates, URLs, or publication
  channels.
- Keep generated files under `src-content/profile/generated/` reproducible.
- Generated output also lives outside `**/generated/`: the standalone article
  listing pages under `src-content/profile/site/**/articles/lists/` are written
  where they are published so the site build renders them as ordinary sources.
  They are Git-ignored and regenerated; do not edit them by hand.
- Prefer adding relations only when the target artifact ID is known.

## Outputs

For file changes, report:

- changed source artifact;
- changed metadata artifact;
- validation command and result;
- any unresolved assumptions.
