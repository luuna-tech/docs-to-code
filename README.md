# Agent Orchestration Framework

A multi-agent orchestration framework built on [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that coordinates PM and Dev agents for automated software development. Give it a project description and domain docs, and it will generate a backlog, plan implementations, ask clarifying questions, and write code — all without human intervention.

## How it works

```
                          orchestrator.sh
                               |
              +----------------+----------------+
              |                |                |
         PM Agent      Architect Agent     Dev Agent
    (product manager)   (architect)       (developer)
              |                |                |
    - reads docs/       - reads docs/     - reads specs
    - generates specs   - defines stack   - reads architecture
    - answers questions - sets conventions - plans implementation
    - detects gaps      - reviews code    - asks PM when blocked
                        - corrective specs - writes code
```

The orchestrator coordinates three specialized agents:

1. **PM Agent** reads your domain documentation (`docs/`), decomposes the project into specs, and answers implementation questions grounded in the docs.
2. **Architect Agent** establishes technical direction in `pm/architecture.md` — stack, structure, conventions, patterns. Reviews code for compliance and generates corrective specs when the codebase deviates.
3. **Dev Agent** picks specs from the backlog, reads the architecture guidelines, plans the implementation, asks the PM when something is ambiguous, and writes the code.

Communication between agents happens through files — specs, questions, answers, and task plans — all in markdown with YAML frontmatter. The orchestrator manages the loop: invoke dev, check if there are questions, invoke PM to answer, re-invoke dev to continue.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- `jq` (for verbose streaming output)
- `bash` 4+

## Quick start

### 1. Set up your project

Create a `docs/` directory with your domain documentation and an index file:

```
docs/
  AGENT_INDEX.md    # maps topics to doc files so agents can find context
  vision.md         # project vision, scope, stack
  domain.md         # data models, business rules
  flows.md          # user flows
```

`AGENT_INDEX.md` example:

```markdown
# Documentation Index

| File | Topic | Summary |
|------|-------|---------|
| `vision.md` | Project Vision | MVP scope, tech stack, target user |
| `domain.md` | Domain Model | Entities, fields, validation rules, business logic |
| `flows.md` | User Flows | Step-by-step user interactions |
```

### 2. Generate the backlog

```bash
.agents/orchestrator.sh pm-seed "Recipe management app with CRUD, search, and portion scaling"
```

Or point to a file:

```bash
.agents/orchestrator.sh pm-seed docs/vision.md
```

The PM Agent reads your docs and generates individual specs in `pm/specs/`, each with acceptance criteria, dependencies, and priority. It also creates `pm/specs/BACKLOG.md` with a summary table.

### 3. Implement a single spec

```bash
.agents/orchestrator.sh dev-implement SPEC-001
```

The Dev Agent will:
1. Read the spec and verify dependencies are done
2. Explore the codebase, plan the implementation
3. Write a task file in `pm/tasks/SPEC-001.md`
4. If blocked by ambiguity, file questions in `pm/questions/`
5. The orchestrator invokes PM to answer, then re-invokes dev
6. Dev implements the code and marks the spec as done

### 4. Set up architecture guidelines

```bash
# Define the tech stack, conventions, and constraints
.agents/orchestrator.sh arch-init "React 18 + TypeScript frontend, Express backend, PostgreSQL. Use functional components, REST API, repository pattern."

# Update architecture later with new guidelines
.agents/orchestrator.sh arch-add "Add Redis caching layer for API responses"

# Discuss trade-offs interactively
.agents/orchestrator.sh arch-add-interactive

# Review code compliance (generates corrective specs for deviations)
.agents/orchestrator.sh arch-review
```

The Architect Agent creates `pm/architecture.md` with stack, directory structure, patterns, and key decisions. The Dev Agent reads this doc before implementing any spec.

### 5. Add new requirements later

Once the initial backlog is built, add new requirements incrementally:

```bash
# Non-interactive: describe the requirement, PM generates spec(s)
.agents/orchestrator.sh pm-add "Add a navigation bar with links to home and create recipe"

# Interactive: have a conversation with the PM to refine the requirement
.agents/orchestrator.sh pm-add-interactive
```

In interactive mode, the PM asks clarifying questions about scope, edge cases, and constraints. Once the requirement is clear, it generates the specs.

### 6. Let it run unattended

```bash
.agents/orchestrator.sh dev-auto
```

This continuously resolves the next eligible spec (highest priority with all dependencies met) and implements it. Stop anytime with `Ctrl+C` or `touch .agents/.stop` from another terminal.

### 7. Check progress

```bash
.agents/orchestrator.sh status          # compact summary
.agents/orchestrator.sh -v status       # list each spec with state
```

```
[status] Specs:     11 total | 10 done | 1 in progress | 0 backlog
  [x ] SPEC-001 — Project Scaffolding & Dev Environment (done)
  [x ] SPEC-002 — Database Schema & Migrations (done)
  [x ] SPEC-003 — Recipe CRUD API (done)
  ...
  [> ] SPEC-011 — Search & Tag Filtering (F6) (in_progress)
[status] Questions: 1 total | 1 answered | 0 pending
[status] Tasks:     10 total | 9 done | 0 implementing | 1 planning | 0 blocked
[status] Progress:  [##################--] 90%
```

## All commands

```bash
orchestrator.sh [-v] [--max-cycles N] <command> [options]

# PM commands
pm-seed <prompt|file>       # Generate initial backlog from project description
pm-add <prompt|file>        # Add new spec(s) for a requirement to existing backlog
pm-add-interactive          # Refine a requirement interactively, then generate specs
pm-answer <question-file>   # Answer a specific developer question
pm-answer-pending           # Answer all unanswered questions

# Architect commands
arch-init <prompt|file>     # Generate initial architecture doc (pm/architecture.md)
arch-add <prompt|file>      # Update architecture with new guidelines
arch-add-interactive        # Discuss and update architecture interactively
arch-review                 # Review code compliance, generate corrective specs

# Dev commands
dev-implement <SPEC-ID>     # Implement a specific spec
dev-implement-next          # Auto-pick and implement the next eligible spec
dev-auto                    # Unattended: implement all eligible specs continuously

# Status
status                      # Show backlog summary
```

**Flags:**
- `-v, --verbose` — stream agent tool calls and output in real time
- `--max-cycles N` — max dev-pm-dev cycles per spec (default: 3)

## Configuration

`.agents/config.yaml`:

```yaml
project:
  source_dir: src/          # where dev agent writes code

orchestrator:
  max_cycles: 3             # dev-pm-dev cycles before requiring human intervention

agents:
  pm_model: opus            # model for PM Agent (sonnet, opus, haiku)
  dev_model: opus           # model for Dev Agent (sonnet, opus, haiku)
  arch_model: opus          # model for Architect Agent (sonnet, opus, haiku)
```

## Project structure

```
.agents/
  orchestrator.sh           # main entry point
  config.yaml               # project configuration
  pm.md                     # PM Agent identity
  architect.md              # Architect Agent identity
  dev.md                    # Dev Agent identity
  logs/                     # agent invocation logs (auto-generated)

.claude/commands/
  gen-spec.md               # skill: generate a spec
  gen-arch.md               # skill: create/update architecture doc
  gen-answer.md             # skill: answer a dev question
  gen-question.md           # skill: file a question to PM
  update-status.md          # skill: transition spec status

# Generated at runtime (not part of the framework):
docs/                       # your domain documentation (input)
pm/architecture.md          # architecture doc (generated by Architect)
pm/specs/                   # generated specs + BACKLOG.md
pm/questions/               # dev questions + PM answers
pm/tasks/                   # implementation plans
src/                        # generated source code
```

## Example: full unattended run

```bash
# 1. Write your domain docs in docs/

# 2. Generate the backlog
.agents/orchestrator.sh -v pm-seed "Recipe management app: CRUD, search, portion scaling"

# 3. Set architecture guidelines
.agents/orchestrator.sh -v arch-init "React 18 + TypeScript, Express, PostgreSQL"

# 4. Check what was generated
.agents/orchestrator.sh -v status

# 5. Let it build everything
.agents/orchestrator.sh -v dev-auto

# 5. Watch the progress — agents plan, ask questions, answer, implement
#    Stop anytime with Ctrl+C or: touch .agents/.stop
```

## How the dev-pm loop works

```
orchestrator                  dev agent                 pm agent
     |                            |                         |
     |--- invoke dev (SPEC-002) ->|                         |
     |                            |-- read spec             |
     |                            |-- check deps (done?)    |
     |                            |-- explore codebase      |
     |                            |-- write task plan       |
     |                            |-- ambiguity found!      |
     |                            |-- /gen-question ------->| (writes question file)
     |                            |-- stop                  |
     |<---------------------------|                         |
     |                                                      |
     |-- pending questions found                            |
     |--- invoke pm ---------------------------------------->|
     |                                                      |-- read question
     |                                                      |-- research docs
     |                                                      |-- /gen-answer (writes answer file)
     |<-----------------------------------------------------|
     |                                                      |
     |--- invoke dev (SPEC-002) ->|                         |
     |                            |-- read task plan        |
     |                            |-- read answer           |
     |                            |-- implement code        |
     |                            |-- run tests             |
     |                            |-- /update-status done   |
     |<---------------------------|                         |
     |                                                      |
     | done!                                                |
```

## Debugging

Each agent invocation is logged to `.agents/logs/` with timestamped filenames:

```
.agents/logs/2026-03-16_19-52-50_dev_SPEC-010_cycle1.log
.agents/logs/2026-03-16_19-53-01_pm_answer_SPEC-010-q1.log
```

In verbose mode (`-v`), logs contain the raw stream-json output with full tool calls, inputs, and outputs. Use these to diagnose agent failures.
