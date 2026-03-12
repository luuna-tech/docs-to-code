# Generate Question

Create a developer question file in `pm/questions/`.

## Input

$ARGUMENTS

## Output Format

Write the question to `pm/questions/SPEC-XXX-qN.md` where N is the next available question number for that spec. Use this exact format:

```markdown
---
spec: SPEC-XXX
agent_id: dev-XXX
status: pending
created: YYYY-MM-DD
---

## Context

<What are you working on and where did you get stuck? Include relevant file paths, function names, or architectural decisions you're facing.>

## Question

<The specific question. Should be focused and answerable with a clear decision.>

## Options Considered

<If you already have candidate approaches, list them with pros/cons. This helps the PM give a more targeted answer.>
```

## Rules

- The `spec` field MUST reference an existing spec in `pm/specs/`.
- Determine the next question number by listing existing `SPEC-XXX-q*.md` files in `pm/questions/`.
- Keep questions focused — one question per file. If you have multiple questions, create multiple files.
- Include enough context that the PM can answer without reading your code.
