---
name: diary
description: Write or extend a development diary entry. Use when recapping a working day, when a mistake is worth recording, when a working agreement emerges from something going wrong, when a thread is left deliberately unfinished, or when the toolkit's guidance is confirmed or contradicted by using it.
---

# Diary Skill

## Purpose

The diary records **why a wrong belief was plausible**. That is its whole reason
to exist, and every rule below follows from it.

It is not architecture documentation. Decisions live in
`src-content/docs/arc42/09-architecture-decisions/`, constraints in
`src-content/docs/arc42/doc-02000-architecture-constraints.adoc`, and those are the authority. The diary
is the reasoning that did not fit in an ADR and the mistakes an ADR has no place
to record.

This skill owns **what an entry contains and where it goes**. How it *reads* is
`skills/language-profile/SKILL.md`, profile 5 — read it before writing.

## What belongs here, and what does not

| It goes in | When it is |
|---|---|
| The diary | Something we believed, and what corrected it |
| An ADR | A decision that binds future work |
| `src-content/docs/doc-005-questions-and-answers.adoc` | A question the owner answered |
| A GitHub issue | Work not yet done |
| `progress/<topic>.adoc` | Where a topic stands right now |

The last row is the one that slips. The diary is what we **learned**; a progress
file is where we **are**. A sentence that fits both is a duplicate, and the diary
keeps it, because it is the one that may not be rewritten later.

## The day file

One file per working day: `diary/YYYY-MM-DD-<slug>.adoc`, where the slug names
what the day turned on rather than what was worked on — `domain-model`,
`green-lights`, `features-and-identity`.

- Heading: `== Day <n> — <D Month YYYY>: <what the day turned on>`.
- Include it in `diary/diary.adoc` in date order. The cross-cutting documents
  bracket the chronological ones: the through-line first, the toolkit validation
  last.
- Sections are `===` headings that state a finding, not a topic. "The figure that
  was answering a different question", not "Calculator work".

## Lifecycle

**A day file is open until the day it covers is closed. After that, append
only.**

- While the day is open, edit freely. It is a draft.
- Once closed, what we believed and when it is fixed. How it reads may still
  change — voice, typography, a cross-reference, a corrected commit id.
- Changing a past claim, softening a past error, or deleting an entry is
  forbidden. That becomes a new entry, which may say the earlier one was wrong.

The register consequences of this rule are in `language-profile` profile 5. This
section is the rule itself; do not restate it there.

## The four cross-cutting documents

Each grows for exactly one reason. Adding to the wrong one is how they stop being
readable.

`diary/through-line.adoc`:: A new instance of the single lesson these days keep
teaching, or a new category of it. An instance carries the artifact, what it
claimed, and what would have caught it. Do not add an instance that only
resembles one already there — resemblance is the point of the document, and it
dilutes with volume.

`diary/working-agreements.adoc`:: A rule that emerged because something went
wrong. Never a rule someone proposed. Each entry is one line plus the cost that
produced it.

`diary/open-threads.adoc`:: A thread left deliberately unfinished, with the
reasoning attached so the next decision does not start from scratch. A thread
belongs here when it **outlives the topic that produced it**; if it dies with the
topic, it belongs in that topic's progress file.

`diary/toolkit-validation.adoc`:: The toolkit's guidance confirmed or
contradicted by using it. This is the return on the project's second goal, so a
finding here is worth an upstream issue as well.

## Sourcing

Written from the commit history, the issues and the pull requests — **never from
memory**. Every date, number, issue id, commit id and quoted output is
reproducible by a reader with the repository.

Before writing, look at what actually happened:

```sh
git log --oneline --since=<date>
gh pr list --state merged --limit 10
gh issue list --state all --limit 20
```

A number that no command produced does not go in. This project has one recorded
case of a constant that was invented by being reported as discovered; the rule
comes from there.

## When this skill should be deleted

The diary practice is general and would suit any project that keeps one; the four
cross-cutting documents and their split are this project's. If the toolkit ever
ships a diary skill, this file keeps only the document list and defers the rest.
