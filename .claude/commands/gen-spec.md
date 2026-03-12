# Generate Spec

Create a product spec file in `pm/specs/`.

## Input

$ARGUMENTS

## Output Format

Write one file per spec to `pm/specs/SPEC-XXX.md` using this exact format:

```markdown
---
id: SPEC-XXX
title: "<short descriptive title>"
status: backlog
priority: critical | high | medium | low
created: YYYY-MM-DD
dependencies: [] # list of SPEC-IDs this depends on
---

## User Story

As a [actor], I want [action] so that [benefit].

## Context

<Why does this feature/fix exist? Link to domain concepts from docs.>

## Acceptance Criteria

- [ ] AC1: <specific, testable criterion>
- [ ] AC2: ...

## Technical Notes

<Optional. Only include if there are non-obvious technical constraints, API contracts, data models, or integration points that the developer needs to know.>

## Out of Scope

<Optional. Explicitly call out what this spec does NOT cover, to prevent scope creep.>
```

## Rules

- Determine the next available SPEC ID by listing files in `pm/specs/`.
- Each acceptance criterion must be specific and testable — no vague language like "should work well".
- Prioritize using: `critical > high > medium > low`.
- If writing multiple specs, also create/update `pm/specs/BACKLOG.md` with a summary table:

```markdown
# Backlog

| ID | Title | Priority | Dependencies | Status |
|----|-------|----------|--------------|--------|
| SPEC-001 | ... | critical | — | backlog |
```
