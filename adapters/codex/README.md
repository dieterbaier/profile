# Codex Adapter

Codex-specific integration lives here. Generic skills and contracts stay in
`skills/` and `ai-contracts/`.

## Discovery

When working in this repository, Codex should read files in this order:

1. `AGENTS.md`
2. `general-semantic-contracts.md`
3. Relevant `skills/**/SKILL.md`
4. Relevant `ai-contracts/*.md`
5. This adapter directory for Codex-specific routing

The routing wrapper `adapters/codex/AGENTS.md` is generated from
`skills/**/SKILL.md` by `scripts/build-agent-adapters.js`. Do not edit it by
hand; change the canonical skills or the generator and regenerate.

## Skill Metadata

OpenAI UI metadata for generic skills is stored under:

```text
adapters/openai/<skill-name>/openai.yaml
```

The executable workflow remains the generic skill at:

```text
skills/<skill-name>/SKILL.md
```

## Current Skills

Project-local skills:

- `skills/article-summary-pack/SKILL.md`
- `skills/write-article/SKILL.md`
- `skills/profile-artifact-maintenance/SKILL.md`

Toolkit-provided skills are not copied into this project. For architecture and
SDLC work covered by `architecture-knowledge-toolkit`, inspect the matching
toolkit `skills/**/SKILL.md`, including:

- `skills/slice-issues/SKILL.md` for issue slicing.
- `skills/implement-issue-workflow/SKILL.md` for issue implementation.
- `skills/architecture-impact/SKILL.md` for feature, refactoring, issue, PR,
  and architecture impact alignment.
- `skills/commit-message/SKILL.md` for commit messages.
- `skills/pr-review/SKILL.md` for pull request reviews.
- `skills/post-merge-sync/SKILL.md` for cleanup after merged pull requests.
- `skills/adr/SKILL.md`, `skills/quality-scenario/SKILL.md`,
  `skills/risk/SKILL.md`, `skills/traceability-review/SKILL.md`, and
  `skills/domain-modeling/SKILL.md` for architecture maintenance.
