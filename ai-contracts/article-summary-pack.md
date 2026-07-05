# AI Contract: Article Summary Pack

## Purpose

Create paste-ready summaries and publication drafts from a source article for:

- LinkedIn
- Substack

The output is a writing aid for cross-posting, not a replacement for the source article.

## Inputs

Required:

- One source article, preferably an AsciiDoc file from `src-content/profile/site/articles/**/*.adoc`.

Optional:

- Canonical article URL
- Target language
- Desired tone adjustment
- Publication date or context
- Platforms to generate; default is LinkedIn and Substack

## Output

Produce one generated HTML file per target platform under `build/summaries/`.

Each platform section must include:

- `title`: platform-suitable headline or opening line
- `summary`: paste-ready body text
- `cta`: call to action or closing sentence
- `tags`: platform-appropriate tags or hashtags, if useful
- `notes`: assumptions, placeholders, or omitted items

Whenever summaries are requested, write files to `build/summaries/` and name each
file after the article filename with `_summary_<target>` before the `.html`
extension:

```text
build/summaries/<article-slug>_summary_linkedin.html
build/summaries/<article-slug>_summary_substack.html
```

The Gradle task `generateArticleSummaries` creates these files for all article
metadata entries under `src-content/profile/site/articles`.

## Invariants

- Preserve the article's actual claims, nuance, and stance.
- Do not add facts, metrics, case studies, quotes, or links that are not present in the article or supplied by the user.
- Keep the author's first-person perspective when the source article uses it.
- Keep the source article as the authority. Summaries may simplify but must not contradict it.
- Treat file-based summaries as generated writing aids under `build/summaries/`.
- Do not include summary files in generated site or article export targets.
- Do not add links, xrefs, navigation entries, or generated public content that points to `_summary_<target>` files.
- Use paste-ready HTML based on the platform template.
- Do not include internal build paths in the public copy.
- Use placeholders such as `[Artikel-Link einsetzen]` when a required publication URL is missing.

## Platform Rules

LinkedIn:

- Write as a concise professional post.
- Prefer a strong hook, 2-5 short paragraphs, and an optional compact bullet list.
- Include 3-5 relevant hashtags.
- Do not exceed 2,000 characters for the complete LinkedIn copy, excluding `notes`.

Substack:

- Write as a newsletter teaser or short intro post.
- Include a title, subtitle, preview paragraph, and a short CTA.
- Keep enough substance to stand alone, but point to the full article.

## Quality Checks

Before finalizing:

- Verify the source title and main thesis are represented.
- Verify each platform output is paste-ready without extra explanation.
- Verify missing URLs or assumptions are explicit in `notes`.
- Verify the LinkedIn copy does not exceed 2,000 characters, excluding `notes`.
- Verify generated summaries were written to `build/summaries/`.
- Run `./gradlew generateArticleSummaries` when checking deterministic summary generation.

## Failure Behavior

- If the article cannot be read, report the missing path and stop.
- If the source is ambiguous, ask for the article path.
- If the article has unresolved AsciiDoc conditionals or includes that materially change meaning, mention the uncertainty in `notes`.
