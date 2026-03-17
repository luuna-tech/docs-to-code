# Generate Architecture

Create or update the project architecture document at `pm/architecture.md`.

## Input

$ARGUMENTS

## Output Format

Write to `pm/architecture.md` using this exact format:

```markdown
---
title: "Project Architecture"
updated: YYYY-MM-DD
---

## System Overview

<High-level description of the system and its components>

## Components

### <Component Name> (e.g., Frontend, Backend, API)

#### Stack

<Languages, frameworks, libraries>

#### Directory Structure

<Expected directory layout>

#### Patterns & Conventions

<Naming conventions, architectural patterns, coding standards>

#### Key Decisions

<Decisions with rationale in this format:>
- **Decision**: <what was decided>
  - **Rationale**: <why this was chosen>
  - **Alternatives rejected**: <what else was considered>

## Integration Points

<How components communicate with each other>

## Cross-Cutting Concerns

<Logging, error handling, testing strategy, security, etc.>
```

## Rules

- If `pm/architecture.md` already exists, **read it first** and MERGE the new content with existing content. Do NOT overwrite sections that are not being changed.
- Preserve existing Key Decisions unless the update explicitly replaces them.
- Guidelines must be concrete and actionable. Avoid vague statements like "write clean code" or "follow best practices".
- Every guideline should be specific enough that a developer can unambiguously determine whether their code complies.
- Use the domain documentation from `docs/` to ground architectural decisions in project context.
- Update the `updated` field in frontmatter to today's date.
