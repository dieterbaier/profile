# Repository Instructions For GitHub Copilot

This file is a GitHub Copilot entry point only. Keep GitHub Copilot-specific
integration guidance under `adapters/github-copilot/` and keep reusable project
semantics in `general-semantic-contracts.md`, `skills/**/`, and `ai-contracts/`.

Follow repository-root `adapters/github-copilot/copilot-instructions.md`, then
the contract hierarchy in repository-root `AGENTS.md`.

Do not duplicate architecture, profile-metadata, article, or task-contract rules
here. Add durable rules to the canonical skill, task contract, or adapter source
instead.
