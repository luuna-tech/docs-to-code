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
specs_modified: []
---

## Answer

<Direct, actionable answer. If multiple approaches are valid, recommend one and explain why.>

## Specs Modified

<If any, list each modified spec ID with a summary of what changed and why. Omit this section if none were modified.>

## New Specs Created

<If any, list each new spec ID with a one-line explanation of why it was needed. Omit this section if none were created.>
```

## Gap Detection & Spec Refinement

While answering, critically assess whether the question reveals gaps or needed refinements in existing specs:

- Does the question imply a prerequisite that no existing spec covers?
- Does the answer require functionality that isn't in any current spec?
- Has an edge case surfaced that needs to be captured?
- Does an existing spec need additional acceptance criteria, technical notes, or clarifications?

### Refinement of existing specs

When you identify that an existing spec needs refinements (additional ACs, clarifications, edge cases):

1. **Check the spec's `status` field.**
2. **If `status: backlog`** — edit the spec directly. Add or update acceptance criteria, technical notes, or out-of-scope sections as needed. Do not remove existing content; append or refine. List the spec in `specs_modified` in your answer frontmatter and in the "Specs Modified" section.
3. **If `status: in_progress` or `status: done`** — do NOT modify the spec. Instead, create a new complementary spec using `/gen-spec` that covers the missing edge cases or refinements, with a dependency on the original spec. List it in `new_specs_created`.

### Creation of new specs

Before creating any new spec, validate it is not a duplicate:

1. Read `pm/specs/BACKLOG.md` and scan the `Summary` column to check if any existing spec already covers the same functionality — even partially.
2. Only if a summary looks potentially overlapping, open that specific spec file to confirm.
3. If an existing spec with `status: backlog` partially covers it, prefer editing that spec (see above) over creating a new one.
4. Only create a new spec if the gap is clearly not covered by any existing spec, or if the relevant spec is already `in_progress`/`done`.

If you identify a valid gap that requires a new spec, create it using the `/gen-spec` format and reference it in your answer.

## Rules

- Be direct and actionable. Recommend a single approach when possible.
- Ground answers in documentation from `docs/`. If docs are ambiguous, say so and recommend with reasoning.
- Do NOT modify the question file — only create the answer file.
- When modifying backlog specs, only append or refine — never remove existing acceptance criteria or change the spec's scope significantly.
- Always update `pm/specs/BACKLOG.md` Summary column if you modify a spec's scope.
