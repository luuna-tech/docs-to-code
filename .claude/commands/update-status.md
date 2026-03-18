# Update Status

Transition the status of a spec and sync the change to BACKLOG.md.

## Input

$ARGUMENTS

Expected format: `SPEC-XXX <new_status>` where `new_status` is one of: `backlog`, `in_progress`, `in_review`, `done`.

## Process

1. Parse the input to extract the spec ID and the target status.
2. Read `pm/specs/SPEC-XXX.md`.
3. Extract the current `status` from the frontmatter.
4. Validate the transition:
   - `backlog` → `in_progress` — allowed
   - `in_progress` → `in_review` — allowed (dev created PR)
   - `in_progress` → `done` — allowed (no review mode)
   - `in_progress` → `backlog` — allowed (rollback)
   - `in_review` → `in_progress` — allowed (reviewer requested changes)
   - `in_review` → `done` — allowed (PR merged)
   - Same status → no-op (no error, no changes needed)
   - Any other transition → **error**, report invalid transition and stop
5. If valid and not a no-op:
   - Update the `status` field in the frontmatter of `pm/specs/SPEC-XXX.md`.
   - Update the Status column for this spec's row in `pm/specs/BACKLOG.md`.
6. Confirm the change.

## Rules

- Only modify the `status` field in the spec frontmatter. Do NOT change any other field or content.
- Only modify the Status column in BACKLOG.md for the matching row. Do NOT change any other column or row.
- If the spec file does not exist, report an error.
- If the target status is not one of `backlog`, `in_progress`, `in_review`, `done`, report an error.
