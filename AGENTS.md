# Agent Instructions

## Repository Workflow

- Inspect the repository before changing code, build logic, documentation, or AI assets.
- Read and apply `general-semantic-contracts.md` before changing architecture content, profile metadata, task contracts, skills, adapters, validators, or generators.
- Preserve user changes. Do not revert unrelated work.
- Prefer existing project patterns in Gradle, AsciiDoc, architecture documentation, generic skill layout, and adapter layout.
- When changing build behavior, run the narrowest relevant Gradle task and report any warnings that remain.

## Contract And Adapter Discovery

- Generic AI instructions live in `general-semantic-contracts.md`, `skills/`, `ai-contracts/`, and `templates/`.
- Agent-specific integration lives under `adapters/<agent>/`.
- Codex-specific instructions and skill metadata live under `adapters/codex/`.
- Do not put generic task workflows under `.codex/`; use `skills/` and keep Codex-only metadata in `adapters/codex/`.

## Architecture Documentation

- This repository belongs to the docs-as-code-toolkit context.
- If architecture documentation, ADRs, quality scenarios, risks, traceability, metadata, templates, validators, or generators are requested, use the architecture-knowledge-toolkit where applicable.
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
- Use `skills/article-summary-pack/SKILL.md` and the templates in `templates/article-summary-pack/` for LinkedIn, Substack, and listed.io outputs.
- Default language is German unless the source article or user explicitly asks otherwise.
