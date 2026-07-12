# Agent Instructions

## Repository Workflow

- Inspect the repository before changing code, build logic, documentation, or AI assets.
- Read and apply `general-semantic-contracts.md` before changing architecture content, profile metadata, task contracts, skills, adapters, validators, or generators.
- Preserve user changes. Do not revert unrelated work.
- Prefer existing project patterns in Gradle, AsciiDoc, architecture documentation, generic skill layout, and adapter layout.
- When changing build behavior, run the narrowest relevant Gradle task and report any warnings that remain.
- When working from a GitHub issue or pull request, use the `architecture-knowledge-toolkit` SDLC skills where applicable, including `skills/slice-issues/SKILL.md`, `skills/implement-issue-workflow/SKILL.md`, `skills/architecture-impact/SKILL.md`, `skills/commit-message/SKILL.md`, `skills/pr-review/SKILL.md`, and `skills/post-merge-sync/SKILL.md`. In particular, format issue commit messages according to `skills/commit-message/SKILL.md` from the toolkit, for example `issue_23: Split deploy workflow by target`.

## Contract And Adapter Discovery

- Generic AI instructions live in `general-semantic-contracts.md`, `skills/`, `ai-contracts/`, and `templates/`.
- Agent-specific integration lives under `adapters/<agent>/`.
- Codex-specific instructions live under `adapters/codex/`.
- Do not put generic task workflows under `.codex/`; use `skills/` and keep Codex-only routing in `adapters/codex/`.
- The thin routing wrappers `adapters/codex/AGENTS.md`, `adapters/vibe/AGENTS.md`, `adapters/github-copilot/copilot-instructions.md`, and `adapters/cursor/rules/profile-dieterbaier.mdc` are generated from `skills/**/SKILL.md` by `scripts/build-agent-adapters.js`. Do not edit them by hand; change the canonical skills or the generator, then run `node scripts/build-agent-adapters.js` (or `./gradlew buildAgentAdapters`). CI runs `node scripts/check-agent-adapters.js` (`./gradlew checkAgentAdapters`) to fail on stale adapters.
- Put OpenAI-specific skill UI metadata, such as `openai.yaml`, under `adapters/openai/<skill-name>/`; do not place it under `adapters/codex/skills/<skill-name>/agents/` or `skills/<skill-name>/agents/`.
- Keep GitHub Copilot repository instructions in `.github/copilot-instructions.md` as an entry point only that points back to `adapters/github-copilot/copilot-instructions.md`.

## Architecture Documentation

- This repository belongs to the docs-as-code-toolkit context.
- If architecture documentation, ADRs, quality scenarios, risks, traceability, metadata, templates, validators, or generators are requested, use the architecture-knowledge-toolkit where applicable.
- For toolkit-backed architecture work, use the matching toolkit skills where applicable, including `adr`, `quality-scenario`, `risk`, `traceability-review`, `architecture-impact`, and `domain-modeling`.
- Project-local instructions and contracts win over generic toolkit conventions.
- Architecture source follows the architecture-knowledge-toolkit structure under `src-content/docs`.
- Run `./gradlew validateArchitectureMetamodel` or `./gradlew generateArchitectureArtifacts` after changing architecture metadata or traceability.

## Profile Artifact Documentation

- Profile content under `src-content/profile` is treated like product source.
- Profile metadata follows `metamodel/profile-artifact.schema.yaml`.
- Use `ai-contracts/profile-artifact-metadata.md` for repeatable AI-assisted profile metadata work.
- Use `skills/profile-artifact-maintenance/SKILL.md` when changing profile pages, CV content, articles, shorts, project entries, or profile metadata.
- Run `./gradlew validateProfileMetamodel` or `./gradlew generateProfileArtifacts` after changing profile metadata.

## AI Contracts

- AI-assisted repeatable work must have an explicit contract under `ai-contracts/`.
- A contract defines the task boundary, accepted inputs, required outputs, invariants, validation checks, and failure behavior.
- Skills and automation that implement such work must reference the relevant contract.
- Do not silently invent missing publication URLs, audience constraints, or article facts. Ask for missing high-impact inputs or mark them as placeholders.

## Article Summaries

- Use the project-local `$article-summary-pack` skill for summaries, teasers, excerpts, or paste-ready publication drafts derived from articles in `src-content/profile/site/articles`.
- Follow `ai-contracts/article-summary-pack.md`.
- Also preserve article metadata governed by `ai-contracts/profile-artifact-metadata.md`.
- Use `skills/article-summary-pack/SKILL.md` and the HTML templates in `templates/article-summary-pack/` for LinkedIn and Substack outputs.
- When summaries are requested, always write the generated HTML files to `build/summaries/`.
- Do not link summary files from public content or include them in generated site/article targets.
- Default language is German unless the source article or user explicitly asks otherwise.
