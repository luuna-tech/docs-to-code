# Project Name

<!-- Replace with your project description -->

## Getting started

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- `jq` (for verbose streaming output)
- `gh` (GitHub CLI, for PR-based review workflow)
- `bash` 4+

### 1. Write your domain docs

Create documentation files in `docs/` and update `docs/AGENT_INDEX.md` with the index:

```
docs/
  AGENT_INDEX.md    # maps topics to doc files so agents can find context
  vision.md         # project vision, scope, stack
  domain.md         # data models, business rules
  flows.md          # user flows
```

### 2. Configure

Edit `.agents/config.yaml`:

```yaml
project:
  source_dir: src/          # where code goes

orchestrator:
  max_cycles: 3             # dev-pm-dev cycles before requiring human intervention
  base_branch: main         # base branch for spec branches (PR target)
  review_mode: agent        # agent | human | hybrid

agents:
  pm_model: opus            # model for each agent (sonnet, opus, haiku)
  dev_model: opus
  arch_model: opus
  reviewer_model: opus
```

Review modes:

| Mode | Behavior |
|------|----------|
| `agent` | Reviewer Agent reviews the PR and merges automatically if approved |
| `human` | Dev creates PR, orchestrator prints URL. Human reviews on GitHub |
| `hybrid` | Reviewer Agent reviews, human merges. Best of both worlds |

Edit `CLAUDE.md` to add your branching rules and project conventions — agents read it on every invocation.

### 3. Generate the backlog

```bash
.agents/orchestrator.sh pm-seed docs/vision.md
```

### 4. Define architecture

```bash
.agents/orchestrator.sh arch-init "React 18 + TypeScript, Express, PostgreSQL"
```

### 5. Implement

```bash
# Single spec
.agents/orchestrator.sh dev-implement SPEC-001

# Or let it run unattended
.agents/orchestrator.sh dev-auto
```

### 6. Check progress

```bash
.agents/orchestrator.sh status          # compact summary
.agents/orchestrator.sh -v status       # list each spec with state
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
dev-implement <SPEC-ID>     # Implement a specific spec (with PR review)
dev-implement-next          # Auto-pick and implement the next eligible spec
dev-address <SPEC-ID>       # Address review comments on a spec's PR
dev-auto                    # Unattended: implement all eligible specs continuously

# Review commands
review-pending              # Review all specs in 'in_review' status

# Status
status                      # Show backlog summary
```

**Flags:**
- `-v, --verbose` — stream agent tool calls and output in real time
- `--max-cycles N` — max dev-pm-dev cycles per spec (default: 3)

## How it works

```
orchestrator              dev agent              pm agent           reviewer agent
     |                        |                      |                    |
     |--- invoke dev -------->|                      |                    |
     |                        |-- read spec          |                    |
     |                        |-- check deps         |                    |
     |                        |-- create branch      |                    |
     |                        |-- explore codebase   |                    |
     |                        |-- write task plan    |                    |
     |                        |-- /gen-question ----->| (question file)   |
     |                        |-- stop               |                    |
     |<-----------------------|                      |                    |
     |                                               |                    |
     |-- pending questions found                     |                    |
     |--- invoke pm -------------------------------->|                    |
     |                                               |-- research docs    |
     |                                               |-- /gen-answer      |
     |<----------------------------------------------|                    |
     |                                                                    |
     |--- invoke dev -------->|                                           |
     |                        |-- implement code                          |
     |                        |-- run tests                               |
     |                        |-- git push + PR                           |
     |                        |-- /update-status in_review                |
     |<-----------------------|                                           |
     |                                                                    |
     |--- invoke reviewer ------------------------------------------->|
     |                                                                |
     |                                          review PR diff -------|
     |                                          check ACs ------------|
     |                                          inline comments ------|
     |                                          approve/request ------|
     |<---------------------------------------------------------------|
     |                                                                    |
     | done! (or dev addresses changes and reviewer re-reviews)           |
```

## Project structure

```
.agents/                    # orchestration framework (do not modify unless developing the framework)
  orchestrator.sh           # main entry point
  config.yaml               # project configuration
  pm.md, dev.md, ...        # agent identities
  FRAMEWORK.md              # framework internals documentation

docs/                       # domain documentation (input for agents)
pm/
  architecture.md           # architecture guidelines (generated by Architect)
  specs/                    # product specs + BACKLOG.md
  questions/                # dev questions + PM answers
  tasks/                    # implementation plans
src/                        # source code
```

## Debugging

Each agent invocation is logged to `.agents/logs/` with timestamped filenames:

```
.agents/logs/2026-03-16_19-52-50_dev_SPEC-010_cycle1.log
.agents/logs/2026-03-16_19-53-01_pm_answer_SPEC-010-q1.log
```

In verbose mode (`-v`), logs contain the raw stream-json output with full tool calls, inputs, and outputs.

---

*Powered by [Agent Orchestration Framework](/.agents/FRAMEWORK.md) — see `.agents/FRAMEWORK.md` for framework internals.*
