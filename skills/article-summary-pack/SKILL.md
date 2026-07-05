---
name: article-summary-pack
description: Create paste-ready summaries, teasers, excerpts, and short publication drafts from project articles for LinkedIn and Substack. Use when an agent is asked to summarize an article, prepare social posts, generate cross-posting copy, apply article-summary templates, or work with the AI contract for article summaries in this repository.
---

# Article Summary Pack

## Workflow

1. Read `general-semantic-contracts.md`.
2. Read the project contract at `ai-contracts/article-summary-pack.md`.
3. Read `ai-contracts/profile-artifact-metadata.md` when article metadata or publication channels are relevant.
4. Read the source article. Prefer AsciiDoc sources from `src-content/profile/site/articles/**/*.adoc`.
5. Resolve enough includes and attributes to understand the article thesis, audience, and conclusion. Ignore site navigation and styling includes.
6. Read the article's `*.profile.yaml` sidecar if present.
7. Select requested platform templates from `templates/article-summary-pack/`; if no platform is specified, use LinkedIn and Substack.
8. Produce paste-ready HTML sections following the contract.
9. Always write generated summaries to `build/summaries/` when summaries are requested.
10. Use `./gradlew generateArticleSummaries` when deterministic build-generated summaries are requested.

## Source Handling

- Treat article content as authoritative.
- Preserve the source language unless the user asks for another language.
- Use German by default for German articles.
- Keep the author's reflective, architecture-aware tone: clear, practical, opinionated without hype.
- Do not invent URLs. Use `[Artikel-Link einsetzen]` when no canonical URL is supplied.
- Do not copy long source passages. Paraphrase and compress.

## Templates

- LinkedIn: read `templates/article-summary-pack/linkedin.html`.
- Substack: read `templates/article-summary-pack/substack.html`.

Use templates as output contracts, not as literal boilerplate. Replace placeholders with article-specific copy and remove unused optional lines.

## Output Shape

For chat responses, group outputs in this order:

1. `LinkedIn`
2. `Substack`

For summary requests, create one HTML file per platform:

```text
build/summaries/<article-slug>_summary_linkedin.html
build/summaries/<article-slug>_summary_substack.html
```

Each output must be directly pasteable. Put assumptions and missing values in a short `notes` block after the platform copy.

Summary files are generated writing aids. They must not be linked from article content, navigation, generated site pages, or generated article exports.

## Build Task

`./gradlew generateArticleSummaries` creates reproducible LinkedIn and Substack
HTML summaries for all article metadata entries under
`src-content/profile/site/articles`. The task writes to `build/summaries/`.
