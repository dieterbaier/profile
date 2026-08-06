---
name: language-profile
description: Choose the register a document is written in before writing it. Use when writing or revising an ADR, architecture constraint, quality scenario, risk, glossary entry, arc42 chapter, README, AGENTS.md, a local skill, the questions-and-answers document, a progress file, a diary recap, a GitHub issue, a pull request body, a commit message, a code comment, or a Gherkin specification.
---

# Language Profile Skill

## Purpose

Project-specific addition covering one thing: the *register* each artifact here is
written in.

The toolkit's skills decide what an artifact must **contain** and what may happen
to it. This skill decides how it **reads**. The two never overlap: if a rule is
about structure, required sections, metadata, relations, status or lifecycle, it
belongs to the toolkit and not here.

It exists because the differences are load-bearing rather than stylistic. An ADR
that hedges has decided nothing. A diary entry that mocks a past belief destroys
the record of why the belief was plausible, which is the stated reason the diary
exists.

## Read first

This skill adds voice rules to existing workflows. Read the baseline before
applying it, and do not re-derive from here what those sources already say —
resolve the toolkit skills through the lookup order in `AGENTS.md`:

- the toolkit's `skills/adr`, `skills/risk`, `skills/quality-scenario`
- the toolkit's `skills/commit-message` — **owns the commit format entirely.**
  This skill adds nothing to it.
- the toolkit's `skills/pr-review` and `skills/bdd-specification`
- `general-semantic-contracts.md`

## Picking a profile

Not by formal against informal. That is a social axis and it predicts none of the
rules below. Pick by **what the lifecycle does with the text once it turns out to
be wrong**:

| Fate under the lifecycle | Artifacts | Profile |
|---|---|---|
| Decision core fixed once accepted; a changed decision becomes a new record | ADR, architecture constraint | [1](#1-decided-once) |
| Reassessed in place as evidence arrives | Risk, quality scenario | [2](#2-reassessed-in-place) |
| Corrected in place, silently | Glossary, arc42 chapters, component descriptions, README, `AGENTS.md`, `general-semantic-contracts.md`, `ai-contracts/**`, `skills/**`, `progress/**` | [3](#3-corrected-silently) |
| Corrected in place, visibly | `src-content/docs/doc-005-questions-and-answers.adoc` | [4](#4-corrected-visibly) |
| Never revised | `diary/**` | [5](#5-never-revised) |
| Corrected when a claim fails | Issue, pull request body, commit message | [6](#6-working-traffic) |
| Changes with the code | Code comment, Gherkin feature | [7](#7-code-and-specifications) |

An author who knows the core of a text is fixed writes differently from one who
knows it will be re-judged next month. That difference is what the profiles
encode.

Fate picks the register. It does not pick the sentences: two artifacts can share
a fate and still have different fields to fill, which is why a profile may carry
sub-rules per artifact type. Where it does, the shared part is the register and
the sub-rules are the vocabulary.

**The first column is a reading of the toolkit's lifecycle, not a rule issued
here.** It is the diagnostic used to pick a register, nothing more. This skill
never says whether an artifact may be edited, superseded, re-graded or retired —
the toolkit's `adr`, `risk` and `quality-scenario` skills say that, and if the
column ever contradicts them, they are right and the column is stale.

Published profile content — articles, shorts, the CV, the site chrome — is **not**
in this table. Its voice is the author's and is product work, not a register this
skill assigns.

## Across every profile: naming a registered identifier

One rule holds in all seven, because it is about how a sentence reads rather than
what happens to it later.

**When prose names something the build can resolve, write the identifier in
backticks.** `translation_of`, not "the translation field". `ART-003-doc-as-code`,
not "the Docs-as-Code article". `{url_cv_marker}`, `buildSite`,
`generateProfileArtifacts`, `.article-list-languages`.

The marking is what makes these sentences readable. This repository mixes English
prose with German content and with identifiers that are neither, so a bare
`ui_nav_home` in a sentence reads as though the author slipped. Marked, it reads
as a name — and a reader who does not recognise it knows exactly what to grep for.

Two things are not this:

- **Quoting a rendering in order to reject it.** "'1 weiterer Artikel' is wrong as
  soon as the other language has fewer" is prose about a wording, not a use of an
  identifier. Quotation marks, not backticks.
- **Example data.** `docs-as-code` as a tag value in a sentence about tagging is a
  value, not a concept in the register.

## 1. Decided once

ADR, architecture constraint.

Read by someone deciding years later whether this still applies, who was not
present when it was decided.

- **Name the deciding role and the date.** The role, not the person: owner,
  architect. A decision whose author is unrecoverable cannot be re-judged.
- **Active voice.** "It was decided", "es wurde entschieden" and their relatives
  are forbidden. They are the construction that makes a decision unattributable.
- **No hedging.** The Decision section says what holds, not what might be worth
  considering. "We could perhaps" is not a decision.
- **No blame.** Attribute the decision, never the error.
- **Self-contained.** Reference sibling artifacts by ID; do not restate them. A
  reader must not need the conversation that produced it.
- **Record the rejected alternative and why**, or it gets proposed again with its
  refutation invisible. ADR-010's Pugh matrix is the shape: four options, scored,
  with a paragraph saying why the runners-up lost.
- Present tense for the rule, past tense for the history.

Metadata and traceability upkeep on an accepted record — a relation added, an
evidence path corrected, a status moved — is the toolkit's business and is not a
rewrite of the decision. The rules above govern the decision's *prose*.

## 2. Reassessed in place

Risk, quality scenario.

Read by someone asking whether the claim still holds — usually the person who
then has to re-judge it.

Both artifacts share a fate and therefore a register. They do not share a
vocabulary: a risk is graded, a scenario is specified, and the sub-rules below
differ accordingly.

**Shared:**

- **Present tense, stating the claim that holds now.** Not the history of claims.
- **Keep the claim and the evidence for it in separate sentences.** A number that
  is simultaneously the requirement and the last measurement cannot be checked
  against itself.
- **When the claim moves, the prose under it moves with it.** A likelihood raised
  while the paragraph justifying the old one stays put leaves two answers in one
  artifact, and the reader cannot tell which is stale.
- **Say what would move it**, so that someone other than the author can re-judge
  it.

**A risk** — `Likelihood`, `Impact`, `Priority`, `Timeframe`, `Confidence`:

- **Attribute the evidence, not a decider.** Nobody decides a risk. A risk names
  what the grade rests on.
- **Assessment cells are terse; the reasoning goes below the table.** The
  generated register inlines those cells into a narrow column, so a sentence there
  is unreadable where it is actually consulted.

**A quality scenario** — `Source`, `Stimulus`, `Artifact`, `Environment`,
`Response`, `Response Measure`:

- **The scenario as a whole describes one concrete, stageable occasion.** That is
  the test the elements serve, and it is a property of the six read together.
- **Each element writes what its own job needs.** `Source` names the actor.
  `Stimulus` states what happens. `Artifact` names what is affected. `Environment`
  states the operating condition that matters. `Response` says actively what the
  system does.
- **Three of the six are nominal and stay that way.** `Artifact`, `Environment`
  and `Response Measure` name things and conditions. Demanding a verb there buys
  nothing.
- **The Response Measure is checkable without asking the author.** QS-004's is the
  shape: "No backend call is required for core content display." "Fast enough" is
  not a measure.
- **A scenario carries no grade.** No likelihood, no priority, no confidence. The
  metamodel has no place to put them, so an invented grade lands in prose and
  reads as fact.

Whether a threshold or a grade may move at all is not this skill's call.

## 3. Corrected silently

Glossary, arc42 chapter documents, component descriptions, README,
`general-semantic-contracts.md`, `AGENTS.md`, `ai-contracts/**`, local skills
under `skills/`, progress files under `progress/`.

Read by someone who needs to act now.

- **Present tense, describing what is.** No "we then decided to" — that is what an
  ADR is for, and duplicating it means two artifacts own one truth.
- **No dates in the body.** They go stale invisibly. The date belongs in the
  frontmatter, or in a pin that names what it pins.
- **Define once.** A term is defined in the glossary and linked from everywhere
  else. Rationale lives in the ADR.
- **State the exception where the rule is stated.** A convention documented in one
  place and contradicted in another is how the `**/generated/` convention stopped being true
  without anyone noticing.
- README may carry voice; the glossary may not. That is a difference in density,
  not in register.
- **A progress file carries no number a command can produce.** Write the command
  instead. This is `skills/clock-in/SKILL.md`'s rule; it appears here because it
  is also what keeps the file readable.

## 4. Corrected visibly

`src-content/docs/doc-005-questions-and-answers.adoc`.

Read by someone tracing why a decision reads the way it does.

- **An answer that turns out wrong is not overwritten.** A dated correction is
  added beneath it and the original stays legible.
- Identifiers are permanent. A question keeps its id forever.
- Say what the earlier answer claimed, not only what is now true. The point of
  this document is the delta.

## 5. Never revised

`diary/**`.

Read by us, later, looking for why a mistake was plausible.

- **First person singular, and it is always the owner's.** The diary is one
  person's record of what they observed during a day, written in the voice they
  would use with no assistant present. "Ich" is the owner, everywhere, without
  exception.
- **Never "der Owner".** A reader who meets both an "ich" and an "Owner" in the
  same entry counts two people and cannot tell which one is the author. This is
  the rule the earlier entries broke, and they were rewritten for it.
- **Name the assistant in the third person where the distinction carries the
  lesson** — where it proposed something the owner caught, or missed a check the
  owner ran. "Der Assistent" is the term; it names the role and survives a change
  of model.
- **No "wir".** Where it does not matter who acted, state the fact without an
  actor. A plural that stands in for one person and a tool records neither.
- Past tense.
- **Unsparing about the error, generous about its plausibility.** Both halves are
  required. Naming the mistake without explaining why it convinced anyone leaves a
  record nobody can learn from.
- **No cynicism.** Mocking a past belief deletes exactly what the entry is for.
- Every claim checkable: dates, issue numbers, commit ids, quoted output.
- **What we believed and when it is never revised; how it reads may be** — voice,
  typography, a cross-reference. That is the register consequence of the diary's
  lifecycle rule, which is `skills/diary/SKILL.md`'s and is not restated here.

German is this project's working language with the owner, and the diary is
written in it. The rules above are about register, not about which language the
register is realised in.

## 6. Working traffic

Issue, pull request body, commit message.

Read by a reviewer now, and by a stranger doing archaeology later.

- Commit format is the toolkit's `commit-message` skill. Not restated here.
- Say **why the change was worth making**, not what the diff already shows.
- Acceptance criteria are checkable by someone who did not write them.
- **Correct the claim, not only the code.** When a justification in an issue turns
  out to be wrong, correct it there too — the issue text is what a later reader
  finds first. Issue #56's acceptance criterion outlived the ADR review that
  invalidated it, and the pull request had to say so.
- **Report what was not reproduced.** A pull request that says a fix works is
  weaker than one that says which four attempts to reproduce the fault failed.
- Do not sell. A body that overstates what a change achieves is a claim nobody
  will ever re-run.

## 7. Code and specifications

Code comments, Gherkin features.

Read by whoever changes this next.

- **Explain the non-obvious reason, never the what.** The comment above the
  interface-term cascade explains why a file-existence check is impossible in
  AsciiDoc; no reader could derive that from the include.
- Match the density and idiom of the surrounding code.
- **A scenario states behaviour, not mechanism.** Gherkin uses the reader's
  vocabulary: "a link that falls back names the language it leads to", not "the
  registry emits a marker attribute".
- **A claim in a comment is a check nobody can run.** It gets the same scrutiny as
  an assertion, or it does not get written.

## Not covered here

- **Published content.** Articles, shorts, the CV and the site chrome are the
  author's voice and product work.
- **Which language a page is written in.** That is ADR-010 and the profile
  metadata, not a register.
- **Commit message format.** The toolkit owns it.
- **Lifecycle and ownership.** When an artifact may be edited, superseded or
  re-graded belongs to whoever owns the artifact — the toolkit for everything it
  defines, `skills/diary/SKILL.md` for the diary. Never this skill.
- **What an entry contains and where it goes.** For the diary and the progress
  files that is `skills/diary/SKILL.md`, `skills/clock-in/SKILL.md` and
  `skills/clock-out/SKILL.md`.

## When this skill should be deleted

The *mechanism* — registers chosen by what the lifecycle does to a text — is
general and belongs upstream if a second project confirms it. The *profiles* are
this project's and do not.

This is the second project to carry it, which is the first evidence that the
mechanism travels. It is not yet evidence that the profiles do: the two projects
adapted the table rather than sharing it. The upstream shape is therefore the
mechanism plus a requirement that each project declare its own profiles.

## Baseline

Taken from the budget project's skill and adapted here. Written against toolkit
`de7c2ad`. If the toolkit skills listed under [Read first](#read-first) have moved
since, check that the delta above still only adds and never contradicts — in
particular that the first column of the profile table still describes what those
skills actually do.
