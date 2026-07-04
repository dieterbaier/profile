# General Semantic Contracts

This file is the AI-agnostic project contract for `profile-dieterbaier`.
Agent adapters and task skills build on it instead of duplicating the same
rules in tool-specific folders.

## Contract Order

Apply instructions in this order:

1. User instruction.
2. Relevant generic skill in `skills/**/SKILL.md`.
3. Relevant task contract in `ai-contracts/`.
4. Adapter-specific guidance under `adapters/<agent>/`.
5. `AGENTS.md`.
6. This file.

More specific instructions may narrow or override more general instructions.
They should not silently contradict them; call out unclear conflicts before
changing architecture, profile content, build behavior, or AI assets.

## Source Of Truth

Repository source files are authoritative. Conversational context, inferred
relations, generated prose, and AI output are advisory until reviewed and
committed.

Generated files under `**/generated/` are reproducible output and are not
primary editing surfaces.

## Architecture Knowledge

Architecture documentation follows the `architecture-knowledge-toolkit`
conventions under `src-content/docs`:

- arc42 chapter documents use stable metadata and IDs.
- ADRs, quality scenarios, risks, canvases, Q&A, traceability metadata,
  validators, and generated fragments follow the toolkit structure.
- Architecture validators and generators are exposed through Gradle.

Use:

```bash
./gradlew validateArchitectureMetamodel
./gradlew generateArchitectureArtifacts
```

## Profile Knowledge

Profile content under `src-content/profile` is treated as product source.
It has its own metamodel, validators, generators, and generated indexes.

Profile metadata follows `metamodel/profile-artifact.schema.yaml`.
Use YAML front matter only where it is safe for standalone documents. Use
`*.profile.yaml` sidecar metadata for include-heavy fragments.

Use:

```bash
./gradlew validateProfileMetamodel
./gradlew generateProfileArtifacts
```

## AI-Agnostic Skills

Generic repeatable workflows live in `skills/`. They must not contain
Codex-specific, OpenAI-specific, GitHub Copilot-specific, or other runtime
adapter assumptions.

Reusable templates and prompt/output templates live in `templates/`.

## Task Contracts

Task-specific AI contracts live in `ai-contracts/`.

A task contract defines:

- purpose and task boundary;
- accepted inputs;
- required outputs;
- invariants;
- validation checks;
- failure behavior.

Use task contracts for repeatable, checkable work such as article summaries and
profile artifact metadata. Keep them engine-agnostic.

## Adapter-Specific Guidance

Adapter-specific files live under `adapters/<agent>/`.

For Codex, read `adapters/codex/README.md` after this file when Codex-specific
skill discovery, UI metadata, or execution conventions matter.

## Contract Strategy

There is no single settled industry standard for repository-local AI task
contracts. Current practice is converging around:

- repository-level agent guidance such as `AGENTS.md`;
- reusable skill bundles with `SKILL.md`;
- explicit task contracts for boundaries, outputs, validation, and failure
  behavior;
- adapter-specific metadata outside generic instructions;
- MCP for tool and context integration rather than repository content rules.

This repository therefore uses a hybrid:

- `general-semantic-contracts.md` for project-wide semantics;
- `ai-contracts/` for modular task contracts;
- `skills/` for AI-agnostic workflows;
- `adapters/` for runtime-specific integration.
