# Codex Adapter

Codex-specific integration lives here. Generic skills and contracts stay in
`skills/` and `ai-contracts/`.

## Discovery

When working in this repository, Codex should read files in this order:

1. `AGENTS.md`
2. `general-semantic-contracts.md`
3. Relevant `skills/**/SKILL.md`
4. Relevant `ai-contracts/*.md`
5. This adapter directory for Codex-specific metadata

## Skill Metadata

Codex UI metadata for generic skills is stored under:

```text
adapters/codex/skills/<skill-name>/agents/openai.yaml
```

The executable workflow remains the generic skill at:

```text
skills/<skill-name>/SKILL.md
```

## Current Skills

- `skills/article-summary-pack/SKILL.md`
- `skills/write-article/SKILL.md`
- `skills/profile-artifact-maintenance/SKILL.md`
