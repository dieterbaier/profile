# AI Contract: Article Summary Pack

## Purpose

Create paste-ready summaries and publication drafts from a source article for:

- LinkedIn
- Substack
- listed.io

The output is a writing aid for cross-posting, not a replacement for the source article.

## Inputs

Required:

- One source article, preferably an AsciiDoc file from `src-content/profile/site/articles/**/*.adoc`.

Optional:

- Canonical article URL
- Target language
- Desired tone adjustment
- Publication date or context
- Platforms to generate; default is all three

## Output

Produce one clearly separated section per target platform.

Each platform section must include:

- `title`: platform-suitable headline or opening line
- `summary`: paste-ready body text
- `cta`: call to action or closing sentence
- `tags`: platform-appropriate tags or hashtags, if useful
- `notes`: assumptions, placeholders, or omitted items

When writing to files, use this layout:

```text
build/article-summaries/<article-slug>/
  linkedin.md
  substack.md
  listed-io.md
```

## Invariants

- Preserve the article's actual claims, nuance, and stance.
- Do not add facts, metrics, case studies, quotes, or links that are not present in the article or supplied by the user.
- Keep the author's first-person perspective when the source article uses it.
- Keep the source article as the authority. Summaries may simplify but must not contradict it.
- Use plain pasteable Markdown. Avoid platform-specific embedded HTML.
- Do not include internal build paths in the public copy.
- Use placeholders such as `[Artikel-Link einsetzen]` when a required publication URL is missing.

## Platform Rules

LinkedIn:

- Write as a concise professional post.
- Prefer a strong hook, 2-5 short paragraphs, and an optional compact bullet list.
- Include 3-5 relevant hashtags.

Substack:

- Write as a newsletter teaser or short intro post.
- Include a title, subtitle, preview paragraph, and a short CTA.
- Keep enough substance to stand alone, but point to the full article.

listed.io:

- Write as a quiet, reflective note.
- Prefer simple Markdown, minimal formatting, and no hashtags unless requested.
- Keep the voice close to the source article.

## Quality Checks

Before finalizing:

- Verify the source title and main thesis are represented.
- Verify each platform output is paste-ready without extra explanation.
- Verify missing URLs or assumptions are explicit in `notes`.
- Verify the LinkedIn copy does not exceed roughly 1,300 characters unless the user asks for a long version.
- Verify listed.io output reads naturally as a standalone note.

## Failure Behavior

- If the article cannot be read, report the missing path and stop.
- If the source is ambiguous, ask for the article path.
- If the article has unresolved AsciiDoc conditionals or includes that materially change meaning, mention the uncertainty in `notes`.
