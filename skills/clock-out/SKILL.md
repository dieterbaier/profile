---
name: clock-out
description: End a working session by refreshing the progress files for the topics touched and writing the diary entry for the day. Use when the owner calls it a day, before a long break, or when a topic is being put on ice.
---

# Clock Out Skill

## Purpose

Leave the repository in a state that a session tomorrow can resume from without
asking anyone.

Two artifacts, and the split between them is the whole point:

- `progress/<topic>.adoc` — **where we are.** Present tense, rewritten wholesale,
  no history.
- `diary/YYYY-MM-DD-<slug>.adoc` — **what we learned.** Past tense, never
  revised once the day is closed.

A sentence that fits both is a duplicate. It goes in the diary, because that is
the one that may not be rewritten later.

The counterpart is `skills/clock-in/SKILL.md`.

## Steps

**1. Close the loop on the work itself.** Nothing uncommitted without a reason
stated, every open pull request named with its check status, every red check
named. Take these from the tools, not from what happened in the session:

```sh
git status --short
gh pr list --state open
gh pr checks <number>
```

A session does not end tidily just because it stopped.

**2. Refresh the progress file for every topic touched.**

- Overwrite it. It describes now; there is nothing in it worth preserving as
  history.
- Move the plan's steps to their real state, and correct the plan itself if the
  day showed the order was wrong. The plan is the thing worth having — a
  checklist that no longer reflects the intended order is worse than none.
- **Do not mark a step done that no check confirmed.** "Done" in a file that
  outlives the session is a claim, and it will be believed.
- If the topic is going on ice, say so in the status line together with **why**
  and what would bring it back. "Paused" without a resumption condition is a file
  nobody will ever reopen.
- If the topic ended, delete the file. What it was for is in the diary by then.

**3. Write the diary entry.** Follow `skills/diary/SKILL.md` — it owns what the
entry contains, where it goes, and which of the cross-cutting documents must grow
today. `skills/language-profile/SKILL.md` profile 5 owns how it reads.

Write it from the commit history, the issues and the pull requests. At clock-out
the day is fresh, which is exactly when memory feels reliable enough to skip the
check.

**4. Close the day, or do not.** A day file is open until the day is closed and
append-only afterwards. Say plainly which of the two just happened, so that a
later session knows whether it may still edit the file.

**5. Say what is open — in the files, not only in the conversation.** The chat
is gone tomorrow. A thread that outlives its topic goes to
`diary/open-threads.adoc`; one that dies with the topic stays in the progress
file.

## What this skill does not do

- It does not decide whether work is finished. Checks and reviews do that.
- It does not merge, push to `main`, or close issues to make a day look complete.
- It does not restate the commit format or the pull-request workflow. Those are
  the toolkit's.

## When this skill should be deleted

The ritual is general; the two artifacts and their paths are this project's. If
the toolkit ships a session-handoff skill, this file keeps only the
project-specific parts and defers the rest.

## Supporting files

- `../clock-in/templates/progress.adoc` — the shape of a progress file. One copy,
  deliberately, so the two skills cannot drift apart.
