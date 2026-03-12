# Generate Answer

Answer a developer question from `pm/questions/`.

## Input

$ARGUMENTS

## Process

1. Read the question file specified above.
2. Extract the `spec` field from its frontmatter and read the referenced spec from `pm/specs/`.
3. Research: read `docs/AGENT_INDEX.md` and any relevant documentation to inform your answer.
4. Write the answer file.
5. Evaluate if the question reveals a gap in the backlog (see Gap Detection below).

## Output Format

Write the answer to `pm/questions/SPEC-XXX-qN.answer.md` (same name as the question file, with `.answer.md` suffix). Use this exact format:

```markdown
---
spec: SPEC-XXX
question_file: SPEC-XXX-qN.md
answered: YYYY-MM-DD
new_specs_created: []
---

## Answer

<Direct, actionable answer. If multiple approaches are valid, recommend one and explain why.>

## New Specs Created

<If any, list each new spec ID with a one-line explanation of why it was needed. Omit this section if none were created.>
```

## Gap Detection

While answering, critically assess whether the question reveals missing specs:

- Does the question imply a prerequisite that no existing spec covers?
- Does the answer require functionality that isn't in any current spec?
- Has an edge case surfaced that deserves its own spec?

**Before creating any new spec**, validate it is not a duplicate:

1. Read `pm/specs/BACKLOG.md` and scan the `Summary` column to check if any existing spec already covers the same functionality — even partially.
2. Only if a summary looks potentially overlapping, open that specific spec file to confirm.
3. If an existing spec partially covers it, consider whether the gap is better addressed by noting it as a suggestion in your answer (e.g., "SPEC-005 may need an additional acceptance criterion for X") rather than creating a new spec.
4. Only create a new spec if the gap is clearly not covered by any existing spec.

If you identify a valid gap, create the missing spec using the `/gen-spec` format and reference it in your answer.

## Rules

- Be direct and actionable. Recommend a single approach when possible.
- Ground answers in documentation from `docs/`. If docs are ambiguous, say so and recommend with reasoning.
- Do NOT modify the question file — only create the answer file.
- Do NOT modify existing specs — only create new ones if gaps are found.
