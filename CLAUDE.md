# Project

<!-- Replace this section with your project description. This is what Claude Code
     sees on every invocation, so keep it concise and relevant. -->

This project uses an automated agent orchestration framework (`.agents/`) to manage specs, implementation, and code review.

## Workflow

Development is driven by specs in `pm/specs/`. The orchestrator (`.agents/orchestrator.sh`) coordinates four agents:

- **PM Agent** — generates specs from `docs/`, answers dev questions
- **Architect Agent** — defines architecture in `pm/architecture.md`, reviews compliance
- **Dev Agent** — implements specs on isolated branches, creates PRs
- **Reviewer Agent** — reviews PRs against ACs, architecture, security

Each spec goes through: `backlog → in_progress → in_review → done`

### Quick reference

```bash
.agents/orchestrator.sh pm-seed <prompt>        # Generate backlog from docs
.agents/orchestrator.sh arch-init <prompt>       # Define architecture
.agents/orchestrator.sh dev-implement SPEC-XXX   # Implement a spec
.agents/orchestrator.sh dev-auto                 # Implement all eligible specs
.agents/orchestrator.sh status                   # Show progress
```

For the full command list and framework internals, see `.agents/FRAMEWORK.md`.

## Branching

<!-- Customize this section with your branching model. The Dev Agent reads CLAUDE.md
     on every invocation and will follow these rules. Examples:

     - "Feature branches use prefix spec/ and target main"
     - "Always rebase before creating a PR"
     - "Use squash merge only"
     - "Never push directly to main or develop"
-->

- Spec branches: `spec/SPEC-XXX` (created automatically by the Dev Agent)
- PR target: configured via `base_branch` in `.agents/config.yaml`

## Project conventions

<!-- Add project-specific conventions here. These will be followed by all agents.
     Examples:

     - "Use TypeScript strict mode"
     - "All API endpoints must have OpenAPI annotations"
     - "Tests are required for all business logic"
-->

## Configuration

See `.agents/config.yaml` for orchestrator settings (review mode, models, base branch, etc.).
