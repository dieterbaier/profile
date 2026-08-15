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
- Put what an article alone owns — its images, its diagram sources — in a
  directory named after its artifact ID next to the article, and address it
  relatively: `:assetsdir: <ARTIFACT-ID>` with `:imagesdir: {assetsdir}` after
  the docheader include, `image::<file>[alt, role="…"]` for an image, and
  `plantuml::{docfile}/../{assetsdir}/<file>.puml[…]` for a diagram source.
  Never `{includesdir}` for those: it points at the public checkout, so the
  reference breaks when the article is promoted from the private repository.
- Use `{includesdir}` only for what more than one article shares — site chrome
  under `includes/images/`, diagram sources under `includes/diagrams/`.
- Do not place an article image in an `++++` passthrough block as a raw `<img>`
  tag. It is copied into the page verbatim, so nothing resolves its `src` and
  the editor preview shows a broken image even where the rendered site works.
  Pass CSS classes through `role="…"` on the `image::` macro instead.
- Do not name a directory after an artifact ID that no article declares; the
  validator rejects it, because no target would publish it.

## Outputs

For file changes, report:

- changed source artifact;
- changed metadata artifact;
- validation command and result;
- any unresolved assumptions.
