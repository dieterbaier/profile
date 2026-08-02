<!-- GENERATED FILE: edit skills/**/SKILL.md or scripts/build-agent-adapters.js, then regenerate. -->
# GitHub Copilot Adapter

This is a thin GitHub Copilot-specific wrapper for the profile-dieterbaier
repository. Keep project semantics in repository-root
`general-semantic-contracts.md`, task contracts in `ai-contracts/`, and
canonical `skills/**/SKILL.md` files.

When GitHub Copilot performs AI-assisted work in this repository:

1. Read repository-root `AGENTS.md`.
2. Read repository-root `general-semantic-contracts.md`.
3. Select and read the relevant canonical skill from the list below.
4. Read the task contract referenced by that skill under `ai-contracts/`.
5. Treat this adapter as routing guidance only.

## Canonical Skills

Paths are relative to the profile-dieterbaier repository root.

- `article-summary-pack`: `skills/article-summary-pack/SKILL.md`
- `clock-in`: `skills/clock-in/SKILL.md`
- `clock-out`: `skills/clock-out/SKILL.md`
- `diary`: `skills/diary/SKILL.md`
- `profile-artifact-maintenance`: `skills/profile-artifact-maintenance/SKILL.md`
- `write-article`: `skills/write-article/SKILL.md`

Architecture and software-development-lifecycle work not covered by a local
skill is delegated to the architecture-knowledge-toolkit. Use the toolkit lookup
order in repository-root `AGENTS.md`.

## Adapter Boundary

Do not duplicate architecture, profile-metadata, article, or task-contract rules
here. Agent-specific files may only wrap, point to, or invoke the canonical
sources in `skills/`, `ai-contracts/`, and `general-semantic-contracts.md`.
