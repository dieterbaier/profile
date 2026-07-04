---
name: article-summary-pack
description: Create paste-ready summaries, teasers, excerpts, and short publication drafts from project articles for LinkedIn, Substack, and listed.io. Use when Codex is asked to summarize an article, prepare social posts, generate cross-posting copy, apply article-summary templates, or work with the AI contract for article summaries in this repository.
---

# Article Summary Pack

## Workflow

1. Read the project contract at `../../../.agents/ai-contracts/article-summary-pack.md`.
2. Read `../../../.agents/ai-contracts/profile-artifact-metadata.md` when article metadata or publication channels are relevant.
3. Read the source article. Prefer AsciiDoc sources from `src-content/profile/site/articles/**/*.adoc`.
4. Resolve enough includes and attributes to understand the article thesis, audience, and conclusion. Ignore site navigation and styling includes.
5. Read the article's `*.profile.yaml` sidecar if present.
6. Select requested platform templates from `assets/templates/`; if no platform is specified, use all three.
7. Produce paste-ready Markdown sections following the contract.
8. If asked to write files, write to `build/article-summaries/<article-slug>/`.

## Source Handling

- Treat article content as authoritative.
- Preserve the source language unless the user asks for another language.
- Use German by default for German articles.
- Keep the author's reflective, architecture-aware tone: clear, practical, opinionated without hype.
- Do not invent URLs. Use `[Artikel-Link einsetzen]` when no canonical URL is supplied.
- Do not copy long source passages. Paraphrase and compress.

## Templates

- LinkedIn: read `assets/templates/linkedin.md`.
- Substack: read `assets/templates/substack.md`.
- listed.io: read `assets/templates/listed-io.md`.

Use templates as output contracts, not as literal boilerplate. Replace placeholders with article-specific copy and remove unused optional lines.

## Output Shape

For chat responses, group outputs in this order:

1. `LinkedIn`
2. `Substack`
3. `listed.io`

For file output, create one file per platform:

```text
build/article-summaries/<article-slug>/linkedin.md
build/article-summaries/<article-slug>/substack.md
build/article-summaries/<article-slug>/listed-io.md
```

Each output must be directly pasteable. Put assumptions and missing values in a short `notes` block after the platform copy.
