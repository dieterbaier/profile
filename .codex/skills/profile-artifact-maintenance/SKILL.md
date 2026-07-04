---
name: profile-artifact-maintenance
description: Maintain profile artifact metadata, indexes, and validation for profile-dieterbaier sources. Use when creating or editing profile pages, CV content, articles, shorts, project entries, profile sidecar metadata, profile generators, or profile metamodel rules.
---

# Profile Artifact Maintenance

## Workflow

1. Read `.agents/ai-contracts/profile-artifact-metadata.md`.
2. Inspect the affected source under `src-content/profile`.
3. Preserve existing content and stable profile artifact IDs.
4. Add or update metadata:
   - YAML front matter for standalone pages when safe.
   - `*.profile.yaml` sidecars for include-heavy fragments.
5. Keep metadata aligned with `metamodel/profile-artifact.schema.yaml`.
6. Run `./gradlew validateProfileMetamodel`.
7. Run `./gradlew generateProfileArtifacts` when indexes or generated views need
   refreshing.

## Rules

- Treat profile content as product source, not generated output.
- Do not invent project facts, employment facts, dates, URLs, or publication
  channels.
- Keep generated files under `src-content/profile/generated/` reproducible.
- Prefer adding relations only when the target artifact ID is known.

## Outputs

For file changes, report:

- changed source artifact;
- changed metadata artifact;
- validation command and result;
- any unresolved assumptions.
