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

`.agents/config.yaml` — project-level settings:
- `project.source_dir` — where the dev agent writes code (default: `src/`)
- `orchestrator.max_cycles` — max dev→pm→dev cycles (default: 3)
- `orchestrator.base_branch` — base branch for spec branches / PR target (default: `main`)
- `orchestrator.review_mode` — PR review workflow: `agent`, `human`, or `hybrid` (default: `agent`)
- `agents.pm_model` — model for PM Agent (default: `opus`)
- `agents.dev_model` — model for Dev Agent (default: `opus`)
- `agents.arch_model` — model for Architect Agent (default: `opus`)
- `agents.reviewer_model` — model for Reviewer Agent (default: `opus`)

## Using Mermaid Diagrams

Agents may use Mermaid diagrams when documenting specifications and architecture. Research (FlowBench, EMNLP 2024) shows that LLM agents follow structured diagram syntax more reliably than prose when given the same information in multiple formats.

**When to use:**

- **PM Agent** — Consider adding Mermaid flowcharts to user flow specs or complex answer documentation
- **Architect Agent** — Consider using Mermaid to visualize system architecture (components, services, boundaries)

**Guidelines:**

- Diagrams are optional, not required — use them when they clarify complex concepts
- Keep diagrams simple and focused — one concept per diagram
- Use consistent naming between prose and diagrams
- Update diagrams when specifications or architecture change

## Conventions

- Agent identity files use YAML frontmatter + markdown body (same pattern as specs)
- Skills are Claude Code slash commands in `.claude/commands/`
- The orchestrator invokes agents via `claude -p` with scoped `--allowedTools`
- Both agents have web access (WebSearch, WebFetch) for research
- Architect Agent has no Bash access (read/write only, same as PM)
- PM Agent has no Bash access (read/write only); Dev and Reviewer Agents have Bash for tests/builds/gh CLI