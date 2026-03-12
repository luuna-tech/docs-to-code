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
- After creating specs, ALWAYS update `pm/specs/BACKLOG.md`. Add a row for each new spec to the summary table. If the file doesn't exist, create it. The table format is:

```markdown
# Backlog

| ID | Title | Priority | Dependencies | Status | Summary |
|----|-------|----------|--------------|--------|---------|
| SPEC-001 | ... | critical | — | backlog | One-line description of what this spec covers and its scope |
```

- The `Summary` column is critical — it must be a concise but complete description of what the spec covers, specific enough to determine overlap with other specs without reading the full file.
