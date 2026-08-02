---
name: clock-in
description: Start a working session by establishing the real state of the repository and picking up a topic from progress/. Use at the beginning of a day, when resuming after an interruption, or when starting a new topic that will span more than one session.
---

# Clock In Skill

## Purpose

Resume a topic without depending on what anyone remembers.

A session that starts by asking "where were we?" gets an answer built from
memory, and memory is where this project's recorded mistakes come from. This
skill starts from the repository instead, and only then asks the one question the
repository cannot answer: which topic to work on.

The counterpart is `skills/clock-out/SKILL.md`.

## Steps

**1. Establish the state before asking anything.**

```sh
git status --short && git branch --show-current
git log --oneline -5
gh pr list --state open
gh issue list --state open --limit 20
```

Note anything that contradicts what the progress files will claim. Uncommitted
work, a branch that is not `main`, an open pull request — these are facts about
where the last session stopped, and they outrank any file.

**2. List the topics from the directory, not from an index.**

Every file in `progress/` is a topic. There is no index to go stale. For each
one, take when it was last touched from git rather than from the file:

```sh
git log -1 --format='%ad %s' --date=short -- progress/<file>
```

**3. Ask, once, which topic to continue.** Offer each existing topic, plus
starting a new one, plus working without a topic — a one-off fix does not need a
progress file, and creating one for it is ceremony.

Ask this as a single question. Do not pair it with a second one; the answers
collide.

**4. Read what the chosen topic depends on.**

- `progress/<topic>.adoc` — the plan and where it stands.
- The newest file in `diary/` — what the last session learned, which is often
  why the plan says what it says.
- The issues the plan references, if the plan's next step names any.

**5. Report the delta, then start.** Three things, briefly: where the topic
stands, what the plan's next step is, and what has changed on `main` since the
file was last touched. If the two disagree, say so and fix the file — it
describes now, so a stale statement in it is corrected on sight, not preserved.

**6. For a new topic**, create `progress/<slug>.adoc` from
`templates/progress.adoc` and fill the plan **with** the owner, not for them. A
plan invented on their behalf is a guess wearing a checklist.

## What a progress file is for

It is the plan and the current status of one topic, sitting next to the code and
present the moment the repository is checked out. That is what it adds over the
issue board: an order of work, and the reason for that order, which a board
cannot show.

It refers to issues by number and never restates them. The issue owns the
acceptance criteria; the file owns the sequence.

It carries no history. It describes now, is rewritten as often as needed, and is
deleted when its topic ends — what was learned along the way is in the diary by
then.

**No number in it that a command can produce.** Not test counts, not coverage,
not bundle sizes. Write the command instead. A number copied into a file nobody
re-runs is a claim that goes stale silently, and this repository has a
through-line documenting where that leads.

## When this skill should be deleted

The ritual is general; `progress/`, AsciiDoc, and the diary wiring are this
project's. If the toolkit ships a session-handoff skill, this file keeps only the
project-specific paths and defers the rest.

## Supporting files

- `templates/progress.adoc` — the shape of a progress file. The only copy;
  `clock-out` references this one.
