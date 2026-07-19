---
name: write-article
description: Draft or revise long-form profile articles for profile-dieterbaier. Use when an agent is asked to write a new article, turn notes into an article, propose an article outline, create article AsciiDoc and profile metadata, or apply the repository article template under `templates/write-article/`.
---

# Write Article

## Workflow

1. Read `general-semantic-contracts.md`.
2. Read `ai-contracts/profile-artifact-metadata.md` before creating or changing article metadata.
3. Inspect existing articles under `src-content/profile/site/articles/**/*.adoc` and their `*.profile.yaml` sidecars.
4. Use `templates/write-article/article.adoc` as the preferred starting point for new long-form articles.
5. Create the article under a topical subdirectory of `src-content/profile/site/articles/`.
6. Create or update the sidecar metadata next to the article, using `templates/write-article/article.profile.yaml` as the metadata scaffold.
7. Preserve article facts supplied by the user. Ask for missing high-impact inputs instead of inventing them.
8. Run `./gradlew validateProfileMetamodel` after metadata changes.
9. Run `./gradlew generateProfileArtifacts` when generated profile indexes need refreshing.

## Article Template Fit

The current repository articles share a stable AsciiDoc header, author metadata, article navigation state, and profile sidecar metadata. Their bodies do not share a single rigid structure:

- `architecture/smarte-cicd-pipeline.adoc` is a compact architecture/process article with numbered solution sections and trade-offs.
- `architecture/sustainability.adoc` is a reflective architecture article with a highlight intro and cross-links.
- `documentation/doc-as-code.adoc` is a longer explanatory article with myths, diagrams, examples, and key takeaways.

Use the template for new articles as a flexible scaffold. Do not rewrite existing articles only to make them fit the template.

## Writing Rules

- Preserve the author's practical, reflective, architecture-aware tone.
- Default to German unless the requested article, source notes, or target audience imply another language.
- Prefer concrete experience, trade-offs, and consequences over generic advice.
- Keep `include::{includesdir}/docheader.adoc[]`, article attributes, and `toc::[]` aligned with existing articles.
- Use `[.highlight.info]` for a short thesis or framing block when it helps the article start clearly.
- Use AsciiDoc xrefs for internal links and do not invent publication URLs.
- Keep source articles authoritative. Summaries and publication drafts are handled by `$article-summary-pack`.

## Metadata Rules

- Use a `*.profile.yaml` sidecar next to the article.
- Follow `metamodel/profile-artifact.schema.yaml` and `ai-contracts/profile-artifact-metadata.md`.
- Use `type: Article`, `generated: false`, and channels such as `website` and `markdown-export` when applicable.
- Assign a stable article ID only after checking existing `ART-*` IDs.
- Mark `reviewed: false` for AI-created or AI-modified articles until human review is recorded.
- Use meaningful, discriminating topical tags. Avoid ubiquitous tags such as `profile`; they add no relatedness signal and the validator warns when an article relies on them.
- To place an article in a series, set the optional `previous` and/or `next` fields to existing Article IDs. Keep them consistent (`A.next = B` should pair with `B.previous = A`); the validator warns on mismatches and errors on unknown or non-Article targets.

## Article Navigation

- Each article ends with a generated navigation include (previous/next series links and a "Könnte Sie auch interessieren" list). `templates/write-article/article.adoc` already carries the guarded include line; keep it and do not author the navigation block by hand.
- `generateProfileArtifacts` writes one `<slug>-navigation.adoc` per article into a `generated/` directory next to the article (for example `.../architecture/generated/`), empty when nothing applies. Placing it beside the article keeps the filename unique per directory, so articles that share a basename in different directories never collide. Related articles are derived from shared meaningful tags (ubiquitous tags excluded) and from `relations`, limited to the five newest.
- The navigation renders on the website only, not in the Markdown/README export.

## Article Tags

- Each article starts with the guarded generated `{docname}-tags.adoc` include from `templates/write-article/article.adoc`; do not author the tag list by hand.
- `generateProfileArtifacts` writes the article's metadata tags as the same linked, horizontal `article-card-tags` markup used by article listings.
- The tag list renders on the website only, not in the Markdown/README export.

## Output Expectations

When writing files, produce:

```text
src-content/profile/site/articles/<topic>/<article-slug>.adoc
src-content/profile/site/articles/<topic>/<article-slug>.profile.yaml
```

If the user only asks for a proposal, provide the proposed outline and note whether it follows `templates/write-article/article.adoc`.
