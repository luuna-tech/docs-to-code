#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
SPECS_DIR="$PROJECT_ROOT/pm/specs"
QUESTIONS_DIR="$PROJECT_ROOT/pm/questions"
TASKS_DIR="$PROJECT_ROOT/pm/tasks"
LOGS_DIR="$SCRIPT_DIR/logs"

# Tools: PM gets filesystem + web; Dev adds Bash for running tests/builds
AGENT_TOOLS="Read,Write,Edit,Glob,Grep,WebSearch,WebFetch"
DEV_AGENT_TOOLS="Read,Write,Edit,Glob,Grep,Bash,WebSearch,WebFetch"
VERBOSE=""

# --- Load config (defaults, then override from config.yaml) ---

MAX_CYCLES=3
SOURCE_DIR="src/"
BASE_BRANCH="main"
REVIEW_MODE="agent"
PM_MODEL=""
DEV_MODEL=""
ARCH_MODEL=""
REVIEWER_MODEL=""

if [ -f "$CONFIG_FILE" ]; then
  _cfg_val() { grep -m1 "^[[:space:]]*$1:" "$CONFIG_FILE" | sed "s/^[^:]*:[[:space:]]*//" | sed 's/[[:space:]]*#.*//'; }
  _max="$(_cfg_val max_cycles)"
  [ -n "$_max" ] && MAX_CYCLES="$_max"
  _src="$(_cfg_val source_dir)"
  [ -n "$_src" ] && SOURCE_DIR="$_src"
  _base="$(_cfg_val base_branch)"
  [ -n "$_base" ] && BASE_BRANCH="$_base"
  _review="$(_cfg_val review_mode)"
  [ -n "$_review" ] && REVIEW_MODE="$_review"
  _pm="$(_cfg_val pm_model)"
  [ -n "$_pm" ] && PM_MODEL="$_pm"
  _dev="$(_cfg_val dev_model)"
  [ -n "$_dev" ] && DEV_MODEL="$_dev"
  _arch="$(_cfg_val arch_model)"
  [ -n "$_arch" ] && ARCH_MODEL="$_arch"
  _reviewer="$(_cfg_val reviewer_model)"
  [ -n "$_reviewer" ] && REVIEWER_MODEL="$_reviewer"
  unset _cfg_val _max _src _base _review _pm _dev _arch _reviewer
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [-v] [--max-cycles N] <command> [options]

Options:
  -v, --verbose        Show agent tool calls and progress in real time.
  --max-cycles N       Max dev→pm→dev cycles for implement commands (default: 3).

Commands:
  pm-seed <prompt|file>      Generate initial backlog from a high-level description.
                             Accepts an inline string or a path to a .md file.

  pm-answer <question>       Invoke PM Agent to answer a developer question.
                             <question> is the path to a question file in pm/questions/.

  pm-answer-pending          Find and answer all unanswered questions in pm/questions/.

  pm-add <prompt|file>       Add new spec(s) for a requirement to the existing backlog.

  pm-add-interactive         Start a conversation with the PM to refine a requirement
                             and generate spec(s) interactively.

  dev-implement <SPEC-ID>    Implement a spec (plan→ask→answer→implement→review loop).

  dev-implement-next         Find and implement the next eligible spec from the backlog.

  dev-address <SPEC-ID>      Address review comments on a spec's PR (human/hybrid mode).
                             Also detects merged PRs and marks specs as done.

  dev-auto                   Unattended mode: continuously pick and implement specs.
                             Stop with Ctrl+C or 'touch .agents/.stop' from another terminal.
                             In human/hybrid mode, stops after PR creation (cannot wait for human).

  review-pending             Review all specs currently in 'in_review' status.
                             In agent/hybrid mode, invokes the Reviewer Agent.
                             In human mode, prints PR URLs.

  arch-init <prompt|file>    Generate initial architecture doc (pm/architecture.md).
                             Pass tech stack, conventions, and constraints.

  arch-add <prompt|file>     Update architecture doc with new guidelines.
                             Requires pm/architecture.md to exist.

  arch-add-interactive       Start a conversation with the Architect to discuss
                             trade-offs and update architecture interactively.

  arch-review                Review codebase for compliance with architecture doc.
                             Generates corrective specs for deviations found.

  status                     Show backlog summary: specs, questions, and tasks.

Examples:
  $(basename "$0") -v pm-seed "Marketplace de muebles con catálogo, carrito y checkout"
  $(basename "$0") pm-seed docs/project-vision.md
  $(basename "$0") pm-answer pm/questions/SPEC-003-q1.md
  $(basename "$0") -v pm-answer-pending
  $(basename "$0") dev-implement SPEC-001
  $(basename "$0") -v --max-cycles 5 dev-implement SPEC-002
  $(basename "$0") dev-implement-next
  $(basename "$0") pm-add "Add user authentication with email/password"
  $(basename "$0") pm-add-interactive
  $(basename "$0") arch-init "React 18 + TypeScript frontend, Express backend, PostgreSQL"
  $(basename "$0") arch-add "Add Redis caching layer for API responses"
  $(basename "$0") arch-add-interactive
  $(basename "$0") arch-review
  $(basename "$0") -v dev-auto
  $(basename "$0") dev-address SPEC-003
  $(basename "$0") review-pending

EOF
  exit 1
}

# Invoke an agent with a prompt. Reads the agent identity file and appends the task.
# Args: <agent_file> <task> [tools_override] [log_label] [model]
invoke_agent() {
  local agent_file="$1"
  local task="$2"
  local tools="${3:-$AGENT_TOOLS}"
  local log_label="${4:-}"
  local model="${5:-}"

  local identity
  identity="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm{print}' "$SCRIPT_DIR/$agent_file")"

  local full_prompt="$identity

---

# Task

$task"

  # Prepare log file
  mkdir -p "$LOGS_DIR"
  local agent_name="${agent_file%.md}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
  local log_file="$LOGS_DIR/${timestamp}_${agent_name}${log_label:+_${log_label}}.log"

  local model_flag=""
  [ -n "$model" ] && model_flag="--model $model"

  echo "[orchestrator] Log: $log_file"
  [ -n "$model" ] && echo "[orchestrator] Model: $model"

  if [ -n "$VERBOSE" ]; then
    # Stream-json mode: log raw JSON, display filtered human-readable output
    (cd "$PROJECT_ROOT" && claude -p "$full_prompt" --allowedTools "$tools" $model_flag --output-format stream-json --verbose) | \
      stdbuf -oL tee "$log_file" | \
      jq --unbuffered -r '
        if .type == "assistant" then
          .message.content[]? |
          if .type == "tool_use" then
            "  \u2192 [\(.name)] \(.input | to_entries | map(.value | tostring) | first // "" | .[0:120])"
          elif .type == "text" then
            .text
          else empty end
        else empty end
      '
  else
    (cd "$PROJECT_ROOT" && claude -p "$full_prompt" --allowedTools "$tools" $model_flag) | tee "$log_file"
  fi
}

# --- Helpers ---

# Read a spec's status from its frontmatter.
# Normalizes unknown statuses to "backlog".
get_spec_status() {
  local spec_id="$1"
  local spec_file="$SPECS_DIR/${spec_id}.md"

  if [ ! -f "$spec_file" ]; then
    echo "not_found"
    return
  fi

  local raw
  raw="$(grep -m1 '^status:' "$spec_file" | awk '{print $2}')"
  case "$raw" in
    backlog|in_progress|in_review|done) echo "$raw" ;;
    *) echo "backlog" ;;
  esac
}

# Find pending (unanswered) questions for a specific spec
# Returns the count of pending questions
get_pending_questions_for_spec() {
  local spec_id="$1"
  local count=0

  for qfile in "$QUESTIONS_DIR"/${spec_id}-q*.md; do
    [ -f "$qfile" ] || continue
    [[ "$qfile" == *.answer.md ]] && continue

    local qbase
    qbase="$(basename "$qfile" .md)"
    local answer_file="$QUESTIONS_DIR/${qbase}.answer.md"

    if [ ! -f "$answer_file" ]; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

# Answer pending questions filtered to a specific spec
answer_pending_for_spec() {
  local spec_id="$1"
  local found=0

  for qfile in "$QUESTIONS_DIR"/${spec_id}-q*.md; do
    [ -f "$qfile" ] || continue
    [[ "$qfile" == *.answer.md ]] && continue

    local qbase
    qbase="$(basename "$qfile" .md)"
    local answer_file="$QUESTIONS_DIR/${qbase}.answer.md"

    if [ ! -f "$answer_file" ]; then
      found=1
      echo ""
      cmd_pm_answer "$qfile"
      echo ""
    fi
  done

  return 0
}

# Print a summary of the current project state: specs, questions, tasks.
# Args: [--verbose] — when set, list each spec individually
show_status() {
  local verbose_status=""
  [ "${1:-}" = "--verbose" ] && verbose_status=1

  local total=0 s_backlog=0 s_in_progress=0 s_in_review=0 s_done=0
  local q_total=0 q_answered=0 q_pending=0
  local t_total=0 t_planning=0 t_implementing=0 t_done=0 t_blocked=0

  # Collect spec details for verbose output
  local spec_lines=""

  # --- Specs ---
  for spec_file in "$SPECS_DIR"/SPEC-*.md; do
    [ -f "$spec_file" ] || continue
    total=$((total + 1))
    local st id title
    st="$(grep -m1 '^status:' "$spec_file" | awk '{print $2}')"
    id="$(grep -m1 '^id:' "$spec_file" | awk '{print $2}')"
    title="$(grep -m1 '^title:' "$spec_file" | sed 's/^title:[[:space:]]*//' | tr -d '"')"
    case "$st" in
      in_progress) s_in_progress=$((s_in_progress + 1)) ;;
      in_review)   s_in_review=$((s_in_review + 1)) ;;
      done)        s_done=$((s_done + 1)) ;;
      *)           s_backlog=$((s_backlog + 1)); st="backlog" ;;
    esac

    if [ -n "$verbose_status" ]; then
      local marker="  "
      case "$st" in
        done)        marker="x " ;;
        in_review)   marker="R " ;;
        in_progress) marker="> " ;;
        backlog)     marker="  " ;;
      esac
      spec_lines="${spec_lines}  [${marker}] ${id} — ${title} (${st})\n"
    fi
  done

  # --- Questions ---
  local question_lines=""
  for qfile in "$QUESTIONS_DIR"/*.md; do
    [ -f "$qfile" ] || continue
    [[ "$qfile" == *.answer.md ]] && continue
    q_total=$((q_total + 1))

    local qbase
    qbase="$(basename "$qfile" .md)"
    if [ -f "$QUESTIONS_DIR/${qbase}.answer.md" ]; then
      q_answered=$((q_answered + 1))
      [ -n "$verbose_status" ] && question_lines="${question_lines}  [x ] ${qbase} — answered\n"
    else
      q_pending=$((q_pending + 1))
      [ -n "$verbose_status" ] && question_lines="${question_lines}  [  ] ${qbase} — pending\n"
    fi
  done

  # --- Tasks ---
  for task_file in "$TASKS_DIR"/SPEC-*.md; do
    [ -f "$task_file" ] || continue
    t_total=$((t_total + 1))
    local ts
    ts="$(grep -m1 '^status:' "$task_file" | awk '{print $2}')"
    case "$ts" in
      planning)      t_planning=$((t_planning + 1)) ;;
      implementing)  t_implementing=$((t_implementing + 1)) ;;
      done)          t_done=$((t_done + 1)) ;;
      blocked)       t_blocked=$((t_blocked + 1)) ;;
    esac
  done

  # --- Display ---
  echo "[status] Specs:     $total total | $s_done done | $s_in_review in review | $s_in_progress in progress | $s_backlog backlog"
  if [ -n "$verbose_status" ] && [ -n "$spec_lines" ]; then
    echo -e "$spec_lines" | head -n -1
  fi
  echo "[status] Questions: $q_total total | $q_answered answered | $q_pending pending"
  if [ -n "$verbose_status" ] && [ -n "$question_lines" ]; then
    echo -e "$question_lines" | head -n -1
  fi
  echo "[status] Tasks:     $t_total total | $t_done done | $t_implementing implementing | $t_planning planning | $t_blocked blocked"

  # Progress bar
  if [ "$total" -gt 0 ]; then
    local pct=$((s_done * 100 / total))
    local filled=$((pct / 5))
    local empty=$((20 - filled))
    local bar
    bar="$(printf '%0.s#' $(seq 1 $filled 2>/dev/null))$(printf '%0.s-' $(seq 1 $empty 2>/dev/null))"
    echo "[status] Progress:  [${bar}] ${pct}%"
  fi
}

# Check if a PR exists for a spec branch.
# Returns: "open", "merged", or "none"
get_pr_state() {
  local spec_id="$1"
  local open_count
  open_count="$(cd "$PROJECT_ROOT" && gh pr list --head "spec/$spec_id" --state open --json number -q 'length' 2>/dev/null || echo 0)"
  if [ "$open_count" -gt 0 ]; then
    echo "open"
    return
  fi
  local merged_count
  merged_count="$(cd "$PROJECT_ROOT" && gh pr list --head "spec/$spec_id" --state merged --json number -q 'length' 2>/dev/null || echo 0)"
  if [ "$merged_count" -gt 0 ]; then
    echo "merged"
    return
  fi
  echo "none"
}

# Get the review decision for an open PR.
# Returns: APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or ""
get_pr_review_decision() {
  local spec_id="$1"
  cd "$PROJECT_ROOT" && gh pr view "spec/$spec_id" --json reviewDecision -q '.reviewDecision' 2>/dev/null || echo ""
}

# Get the PR number for an open PR on a spec branch.
# Returns the number, or "" if none.
get_pr_number() {
  local spec_id="$1"
  cd "$PROJECT_ROOT" && gh pr list --head "spec/$spec_id" --state open --json number -q '.[0].number' 2>/dev/null || echo ""
}

# Get the PR URL for an open PR on a spec branch.
get_pr_url() {
  local spec_id="$1"
  cd "$PROJECT_ROOT" && gh pr list --head "spec/$spec_id" --state open --json url -q '.[0].url' 2>/dev/null || echo ""
}

# After a PR is merged and status updated to done, ensure the status changes
# (pm/specs/ and pm/specs/BACKLOG.md) are committed and pushed on the base branch.
sync_status_to_base() {
  local spec_id="$1"

  echo "[orchestrator] Syncing status changes to $BASE_BRANCH..."

  (
    cd "$PROJECT_ROOT"
    git checkout "$BASE_BRANCH"
    git pull origin "$BASE_BRANCH" || true

    # Stage only spec and backlog status files
    git add pm/specs/"${spec_id}.md" pm/specs/BACKLOG.md 2>/dev/null || true

    # Also stage task file if it was updated
    [ -f "pm/tasks/${spec_id}.md" ] && git add "pm/tasks/${spec_id}.md" 2>/dev/null || true

    # Only commit if there are staged changes
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "chore(${spec_id}): mark spec as done" --no-verify
      git push origin "$BASE_BRANCH"
      echo "[orchestrator] Status changes committed and pushed to $BASE_BRANCH."
    else
      echo "[orchestrator] No status changes to commit."
    fi
  )
}

# Invoke the review cycle for a spec that is in_review.
# Returns: 0 if review completed (done or approved for human merge), 1 to continue cycling.
review_cycle() {
  local spec_id="$1"

  if [ "$REVIEW_MODE" = "human" ]; then
    local pr_url
    pr_url="$(get_pr_url "$spec_id")"
    echo "[orchestrator] PR ready for human review: $pr_url"
    echo "[orchestrator] After reviewing, run: orchestrator.sh dev-address $spec_id"
    return 0
  fi

  # agent or hybrid mode — invoke reviewer
  echo "[orchestrator] Invoking Reviewer Agent for $spec_id (mode: $REVIEW_MODE)"
  echo "---"

  invoke_agent "reviewer.md" "Review the PR for spec $spec_id.

Read pm/specs/${spec_id}.md for acceptance criteria.
Read pm/architecture.md if it exists for architectural guidelines.
Get the open PR with: gh pr list --head \"spec/$spec_id\" --state open --json number,url -q '.[0]'
Read the PR diff with: gh pr diff <number>
Read full source files for context.

**Review mode:** $REVIEW_MODE
**Base branch:** $BASE_BRANCH
**Source directory:** \`$SOURCE_DIR\`

Follow your review process: gather context, review against all dimensions, submit review via gh api, and take the appropriate action based on review mode and findings.

Use /update-status to transition the spec status as needed." "$DEV_AGENT_TOOLS" "${spec_id}_review" "$REVIEWER_MODEL"

  echo ""

  # Check what the reviewer did
  local review_status
  review_status="$(get_spec_status "$spec_id")"
  echo "[orchestrator] Spec $spec_id status after review: $review_status"

  if [ "$review_status" = "done" ]; then
    echo "[orchestrator] Spec $spec_id merged and completed by reviewer."
    sync_status_to_base "$spec_id"
    return 0
  fi

  if [ "$review_status" = "in_review" ]; then
    # hybrid mode: reviewer approved but didn't merge
    local pr_url
    pr_url="$(get_pr_url "$spec_id")"
    echo "[orchestrator] PR approved, awaiting human merge: $pr_url"
    echo "[orchestrator] After merging, run: orchestrator.sh dev-address $spec_id"
    return 0
  fi

  if [ "$review_status" = "in_progress" ]; then
    # Reviewer requested changes — signal to continue cycling
    echo "[orchestrator] Reviewer requested changes. Will re-invoke dev in address mode."
    return 1
  fi

  echo "[orchestrator] Unexpected status after review: $review_status"
  return 1
}

# --- Commands ---

cmd_pm_seed() {
  local input="$1"
  local prompt

  if [ -f "$input" ]; then
    prompt="$(cat "$input")"
    echo "[orchestrator] Reading prompt from file: $input"
  else
    prompt="$input"
  fi

  echo "[orchestrator] Invoking PM Agent — mode: seed"
  echo "[orchestrator] Working directory: $PROJECT_ROOT"
  echo "---"

  invoke_agent "pm.md" "Generate the initial product backlog for this project.

Use /gen-spec to create each spec. After creating all specs, ensure pm/specs/BACKLOG.md exists with the full summary.

## Project Description

$prompt" "" "seed" "$PM_MODEL"
}

cmd_pm_answer() {
  local question_file="$1"

  if [ ! -f "$question_file" ]; then
    echo "[orchestrator] Error: Question file not found: $question_file"
    exit 1
  fi

  local basename
  basename="$(basename "$question_file" .md)"
  local answer_file="$QUESTIONS_DIR/${basename}.answer.md"

  if [ -f "$answer_file" ]; then
    echo "[orchestrator] Already answered: $answer_file — skipping."
    return 0
  fi

  echo "[orchestrator] Invoking PM Agent — mode: answer"
  echo "[orchestrator] Question: $question_file"
  echo "---"

  invoke_agent "pm.md" "Answer the developer question in: $question_file

Use /gen-answer to write the answer. If you discover gaps in the backlog, use /gen-spec to create new specs." "" "answer_$(basename "$question_file" .md)" "$PM_MODEL"
}

cmd_pm_answer_pending() {
  local found=0

  for qfile in "$QUESTIONS_DIR"/*.md; do
    [ -f "$qfile" ] || continue
    [[ "$qfile" == *.answer.md ]] && continue

    local basename
    basename="$(basename "$qfile" .md)"
    local answer_file="$QUESTIONS_DIR/${basename}.answer.md"

    if [ ! -f "$answer_file" ]; then
      found=1
      echo ""
      cmd_pm_answer "$qfile"
      echo ""
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "[orchestrator] No pending questions found."
  fi
}

cmd_pm_add() {
  local input="$1"
  local prompt

  if [ -f "$input" ]; then
    prompt="$(cat "$input")"
    echo "[orchestrator] Reading requirement from file: $input"
  else
    prompt="$input"
  fi

  echo "[orchestrator] Invoking PM Agent — mode: add requirement"
  echo "[orchestrator] Working directory: $PROJECT_ROOT"
  echo "---"

  invoke_agent "pm.md" "A new requirement has been requested for the project. Your job is to analyze it and create the spec(s) needed to implement it.

## Process

1. Read the existing backlog at pm/specs/BACKLOG.md to understand what is already built or planned.
2. Read docs/AGENT_INDEX.md and relevant documentation.
3. Analyze the new requirement below and determine what spec(s) are needed.
4. Check for overlap with existing specs — do not duplicate work that is already covered.
5. Create new spec(s) using /gen-spec. Set correct dependencies on existing specs.
6. Update pm/specs/BACKLOG.md with the new entries.

## New Requirement

$prompt" "" "add" "$PM_MODEL"
}

cmd_pm_add_interactive() {
  echo "[orchestrator] Starting interactive PM session..."
  echo "[orchestrator] Describe your requirement. The PM will ask clarifying questions."
  echo "[orchestrator] When the requirement is clear, the PM will generate specs."
  echo "[orchestrator] Type 'exit' or Ctrl+C to end the session."
  echo "---"

  local identity
  identity="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm{print}' "$SCRIPT_DIR/pm.md")"

  local system_prompt="$identity

---

# Mode: Interactive Requirement Refinement

You are in an interactive session with a stakeholder who wants to add a new requirement to the project.

## Your process

1. At the START of the conversation, read pm/specs/BACKLOG.md and docs/AGENT_INDEX.md to understand the current state of the project. Do this silently — do not dump the contents to the user.
2. Listen to the user's requirement.
3. Ask clarifying questions to fill in gaps: scope, edge cases, constraints, what is in/out of scope.
4. When the requirement is fully understood, summarize it back to the user for confirmation.
5. Once confirmed, generate the spec(s) using /gen-spec and update pm/specs/BACKLOG.md.

## Rules

- Ask focused questions — one or two at a time, not a wall of questions.
- Ground your understanding in the existing documentation from docs/.
- Be aware of existing specs to avoid duplicates and set correct dependencies.
- Do not generate specs until the user confirms the requirement is complete.
- After generating specs, tell the user: 'Specs generated. You can describe another requirement or type /quit to exit.'"

  local model_flag=""
  [ -n "$PM_MODEL" ] && model_flag="--model $PM_MODEL"

  (cd "$PROJECT_ROOT" && claude --append-system-prompt "$system_prompt" --allowedTools "$AGENT_TOOLS" $model_flag)
}

cmd_arch_init() {
  local input="$1"
  local prompt

  if [ -f "$input" ]; then
    prompt="$(cat "$input")"
    echo "[orchestrator] Reading guidelines from file: $input"
  else
    prompt="$input"
  fi

  echo "[orchestrator] Invoking Architect Agent — mode: init"
  echo "[orchestrator] Working directory: $PROJECT_ROOT"
  echo "---"

  invoke_agent "architect.md" "Generate the initial architecture document for this project.

## Process

1. Read docs/AGENT_INDEX.md and all relevant domain documentation.
2. Read pm/specs/BACKLOG.md to understand what is planned.
3. Use /gen-arch to create pm/architecture.md based on the guidelines below.
4. If the architecture implies foundational work not covered by existing specs, create those specs with /gen-spec and update pm/specs/BACKLOG.md.

**Source directory:** \`$SOURCE_DIR\`

## Architecture Guidelines

$prompt" "" "arch_init" "$ARCH_MODEL"
}

cmd_arch_add() {
  local input="$1"
  local prompt

  if [ -f "$input" ]; then
    prompt="$(cat "$input")"
    echo "[orchestrator] Reading guidelines from file: $input"
  else
    prompt="$input"
  fi

  if [ ! -f "$PROJECT_ROOT/pm/architecture.md" ]; then
    echo "[orchestrator] Error: pm/architecture.md does not exist. Run arch-init first."
    exit 1
  fi

  echo "[orchestrator] Invoking Architect Agent — mode: add"
  echo "[orchestrator] Working directory: $PROJECT_ROOT"
  echo "---"

  invoke_agent "architect.md" "Update the architecture document with new guidelines.

## Process

1. Read the current pm/architecture.md.
2. Read pm/specs/BACKLOG.md to understand the current state.
3. Analyze the change requested below and its implications.
4. Use /gen-arch to update the doc (merge with existing content, do NOT overwrite unchanged sections).
5. If the update requires implementation work, generate migration or change specs with /gen-spec and update pm/specs/BACKLOG.md.

**Source directory:** \`$SOURCE_DIR\`

## Requested Change

$prompt" "" "arch_add" "$ARCH_MODEL"
}

cmd_arch_add_interactive() {
  echo "[orchestrator] Starting interactive Architect session..."
  echo "[orchestrator] Discuss architectural trade-offs and guidelines."
  echo "[orchestrator] When aligned, the Architect will update the doc and generate specs."
  echo "[orchestrator] Type 'exit' or Ctrl+C to end the session."
  echo "---"

  local identity
  identity="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm{print}' "$SCRIPT_DIR/architect.md")"

  local system_prompt="$identity

---

# Mode: Interactive Architecture Discussion

You are in an interactive session with a stakeholder who wants to discuss and update the project's architecture.

## Your process

1. At the START of the conversation, read pm/architecture.md (if it exists), pm/specs/BACKLOG.md, and docs/AGENT_INDEX.md to understand the current state. Do this silently — do not dump the contents to the user.
2. Listen to the user's architectural concern or proposal.
3. Discuss trade-offs, ask about constraints, and present alternatives with pros/cons.
4. When aligned on the approach, summarize the changes for confirmation.
5. Once confirmed, update pm/architecture.md using /gen-arch and generate any needed specs using /gen-spec (update pm/specs/BACKLOG.md).

## Rules

- Ask focused questions — one or two at a time, not a wall of questions.
- Ground your recommendations in the existing documentation from docs/.
- Present trade-offs honestly — every decision has costs.
- Do not update the architecture doc until the user confirms.
- After updating, tell the user: 'Architecture updated. You can discuss another topic or type /quit to exit.'

**Source directory:** \`$SOURCE_DIR\`"

  local model_flag=""
  [ -n "$ARCH_MODEL" ] && model_flag="--model $ARCH_MODEL"

  (cd "$PROJECT_ROOT" && claude --append-system-prompt "$system_prompt" --allowedTools "$AGENT_TOOLS" $model_flag)
}

cmd_arch_review() {
  if [ ! -f "$PROJECT_ROOT/pm/architecture.md" ]; then
    echo "[orchestrator] Error: pm/architecture.md does not exist. Run arch-init first."
    exit 1
  fi

  echo "[orchestrator] Invoking Architect Agent — mode: review"
  echo "[orchestrator] Working directory: $PROJECT_ROOT"
  echo "---"

  invoke_agent "architect.md" "Review the codebase for compliance with the architecture document.

## Process

1. Read pm/architecture.md (the expected standard).
2. Explore the source code in \`$SOURCE_DIR\` using Glob and Grep to discover the actual structure, frameworks, patterns, and conventions in use.
3. Compare actual state against each guideline in the architecture doc.
4. For each deviation found:
   - Check if a spec in pm/specs/ already covers this gap.
   - If no existing spec covers it, create a corrective spec with /gen-spec and update pm/specs/BACKLOG.md.
   - Set priority: critical for structural issues, high for convention violations, medium for minor inconsistencies.
5. Only flag deviations from EXPLICIT guidelines in the architecture doc. Do NOT impose preferences that are not declared.
6. Output a summary with: total deviations found, existing specs that already cover gaps, and new specs created.

**Source directory:** \`$SOURCE_DIR\`" "" "arch_review" "$ARCH_MODEL"
}

cmd_dev_implement() {
  local spec_id="$1"
  local spec_file="$SPECS_DIR/${spec_id}.md"

  if [ ! -f "$spec_file" ]; then
    echo "[orchestrator] Error: Spec file not found: $spec_file"
    return 1
  fi

  mkdir -p "$TASKS_DIR"

  for cycle in $(seq 1 "$MAX_CYCLES"); do
    local status
    status="$(get_spec_status "$spec_id")"

    echo ""
    echo "[orchestrator] === Cycle $cycle/$MAX_CYCLES ==="
    echo "[orchestrator] Spec $spec_id status: $status"

    # Already done — nothing to do
    if [ "$status" = "done" ]; then
      echo "[orchestrator] Spec $spec_id is already done."
      return 0
    fi

    # If in_review, enter the review cycle
    if [ "$status" = "in_review" ]; then
      local review_result=0
      review_cycle "$spec_id" || review_result=$?
      if [ "$review_result" -eq 0 ]; then
        # Review completed (done, or awaiting human merge/review)
        local final_status
        final_status="$(get_spec_status "$spec_id")"
        if [ "$final_status" = "done" ]; then
          echo "[orchestrator] Spec $spec_id completed successfully."
        fi
        return 0
      fi
      # review_result=1 means changes requested, continue cycling (dev will address)
      continue
    fi

    # Determine mode hint for the dev agent
    local mode_hint="implement"
    local mode="plan"
    if [ "$status" = "backlog" ]; then
      mode="plan"
      mode_hint="implement"
    elif [ "$status" = "in_progress" ] && [ ! -f "$TASKS_DIR/${spec_id}.md" ]; then
      mode="plan"
      mode_hint="implement"
    elif [ "$status" = "in_progress" ] && [ -f "$TASKS_DIR/${spec_id}.md" ]; then
      # Check if there's an open PR with changes requested → address mode
      local pr_state
      pr_state="$(get_pr_state "$spec_id")"
      if [ "$pr_state" = "open" ]; then
        mode="address"
        mode_hint="address_review"
      else
        mode="implement"
        mode_hint="implement"
      fi
    fi

    echo "[orchestrator] Invoking Dev Agent — mode: $mode — cycle $cycle/$MAX_CYCLES"
    echo "---"

    invoke_agent "dev.md" "Implement spec $spec_id.

Read pm/specs/${spec_id}.md and follow your mode of operation (Plan, Implement, or Address) based on the spec's current status and the mode hint below.

**Source directory:** All implementation code must be written inside \`$SOURCE_DIR\` (relative to project root). Create it if it doesn't exist.
**Base branch:** $BASE_BRANCH
**Review mode:** $REVIEW_MODE
**Mode hint:** $mode_hint

**Architecture:** If pm/architecture.md exists, read it and follow its guidelines.

If you have questions, use /gen-question to file them and then stop.
If all dependencies are met and you can proceed, implement the spec completely.
Use /update-status to transition the spec status as needed." "$DEV_AGENT_TOOLS" "${spec_id}_cycle${cycle}" "$DEV_MODEL"

    echo ""

    # Re-check status after dev agent ran
    local new_status
    new_status="$(get_spec_status "$spec_id")"
    echo "[orchestrator] Spec $spec_id status after dev: $new_status"

    if [ "$new_status" = "done" ]; then
      # Ensure task file reflects completion (agent may skip this on token exhaustion)
      local task_file="$TASKS_DIR/${spec_id}.md"
      if [ -f "$task_file" ] && ! grep -q '^status: done' "$task_file"; then
        sed -i 's/^status: .*/status: done/' "$task_file"
        if ! grep -q '^completed:.*[0-9]' "$task_file"; then
          sed -i "s/^completed:.*/completed: $(date '+%Y-%m-%d')/" "$task_file"
        fi
        echo "[orchestrator] Task file synced to done."
      fi
      echo "[orchestrator] Spec $spec_id completed successfully."
      return 0
    fi

    # Dev created a PR and moved to in_review → enter review cycle on next iteration
    if [ "$new_status" = "in_review" ]; then
      echo "[orchestrator] Spec $spec_id moved to in_review. Entering review cycle."
      continue
    fi

    # If status never moved from backlog, the dev hit a blocker (e.g. unmet deps) — no point retrying
    if [ "$new_status" = "backlog" ]; then
      echo "[orchestrator] Spec $spec_id still in backlog — dev reported a blocker. Stopping."
      return 1
    fi

    # Check for pending questions
    local pending
    pending="$(get_pending_questions_for_spec "$spec_id")"

    if [ "$pending" -gt 0 ]; then
      echo "[orchestrator] Pending questions found: $pending"
      echo "[orchestrator] Invoking PM Agent to answer questions for $spec_id..."
      answer_pending_for_spec "$spec_id"
    elif [ "$new_status" = "in_progress" ] && [ ! -f "$TASKS_DIR/${spec_id}.md" ]; then
      # Status moved but no task file — likely token exhaustion mid-planning.
      echo "[orchestrator] Partial progress: status changed but no task file written."
      echo "[orchestrator] Retrying — agent will resume planning."
    elif [ "$new_status" = "in_progress" ] && [ "$(get_pr_state "$spec_id")" = "open" ]; then
      # Dev is in address mode, pushed changes — will re-enter review on next cycle
      echo "[orchestrator] Dev addressed review comments. Will re-enter review cycle."
    else
      echo "[orchestrator] No pending questions and spec is not done."
      echo "[orchestrator] Dev agent may be stuck. Check pm/tasks/${spec_id}.md for details."
      echo "[orchestrator] Stopping — retries are only for pending questions or partial progress."
      return 1
    fi
  done

  echo "[orchestrator] Max cycles ($MAX_CYCLES) exhausted for $spec_id. Human intervention required."
  return 1
}

# Resolve the next eligible spec from the backlog.
# Prints the SPEC-ID to stdout, or "NONE" if nothing is eligible.
resolve_next_spec() {
  local result
  result="$(cd "$PROJECT_ROOT" && claude -p "Read pm/specs/BACKLOG.md. Find the highest-priority spec that is NOT 'done', NOT 'in_progress', and NOT 'in_review' (any other status counts as eligible — 'backlog', 'ready', etc.), whose dependencies are ALL either empty or have status 'done' (check each dependency's status by reading its spec file in pm/specs/).

Priority order: critical > high > medium > low. For specs with equal priority, prefer the one listed first (lower SPEC number).

Reply with ONLY the SPEC-ID (e.g., SPEC-001) and nothing else. If no eligible spec exists, reply with NONE." --allowedTools "Read,Glob,Grep" 2>/dev/null)"

  # Trim whitespace
  echo "$result" | tr -d '[:space:]'
}

cmd_dev_implement_next() {
  echo "[orchestrator] Resolving next eligible spec from backlog..."

  local next_spec
  next_spec="$(resolve_next_spec)"

  if [ "$next_spec" = "NONE" ] || [ -z "$next_spec" ]; then
    echo "[orchestrator] No eligible spec found. All specs are either done, in progress, or have unmet dependencies."
    return 0
  fi

  echo "[orchestrator] Next eligible spec: $next_spec"
  cmd_dev_implement "$next_spec"
}

# Check if a stop signal has been received (stop file or SIGINT flag)
_STOP_REQUESTED=""
check_stop() {
  if [ -n "$_STOP_REQUESTED" ] || [ -f "$SCRIPT_DIR/.stop" ]; then
    return 0  # stop requested
  fi
  return 1    # keep going
}

ts() { date '+%H:%M:%S'; }

cmd_dev_auto() {
  local completed=0
  local failed=0

  # Clean up leftover stop file from a previous run
  rm -f "$SCRIPT_DIR/.stop"

  # Trap SIGINT: set flag so we exit gracefully after the current operation
  trap '_STOP_REQUESTED=1; echo ""; echo "[orchestrator] [$(ts)] Ctrl+C received — will stop after current operation."' INT

  echo ""
  echo "[orchestrator] ========================================="
  echo "[orchestrator]         UNATTENDED MODE"
  echo "[orchestrator] ========================================="
  echo "[orchestrator] To stop: Ctrl+C or 'touch .agents/.stop'"
  echo "[orchestrator] Max cycles per spec: $MAX_CYCLES"
  echo ""

  while true; do
    # --- Check stop before resolving ---
    if check_stop; then
      echo "[orchestrator] [$(ts)] Stop signal received."
      break
    fi

    show_status
    echo ""
    echo "[orchestrator] [$(ts)] Resolving next eligible spec..."
    local next_spec
    next_spec="$(resolve_next_spec)"

    if [ "$next_spec" = "NONE" ] || [ -z "$next_spec" ]; then
      echo "[orchestrator] [$(ts)] No more eligible specs."
      break
    fi

    # --- Check stop before implementing ---
    if check_stop; then
      echo "[orchestrator] [$(ts)] Stop signal received."
      break
    fi

    echo ""
    echo "[orchestrator] [$(ts)] --- Starting $next_spec (completed: $completed, failed: $failed) ---"

    # Run dev-implement, capture exit code without triggering set -e
    local result=0
    cmd_dev_implement "$next_spec" || result=$?

    if [ "$result" -eq 0 ]; then
      completed=$((completed + 1))
      echo "[orchestrator] [$(ts)] $next_spec completed."
    else
      failed=$((failed + 1))
      echo "[orchestrator] [$(ts)] $next_spec failed (exit $result). Moving on."
    fi

    echo ""
  done

  # Restore default signal handling and clean up
  trap - INT
  rm -f "$SCRIPT_DIR/.stop"

  echo ""
  echo "[orchestrator] ========================================="
  echo "[orchestrator]         SESSION SUMMARY"
  echo "[orchestrator]  Completed: $completed | Failed: $failed"
  echo "[orchestrator] ========================================="
}

cmd_dev_address() {
  local spec_id="$1"
  local spec_file="$SPECS_DIR/${spec_id}.md"

  if [ ! -f "$spec_file" ]; then
    echo "[orchestrator] Error: Spec file not found: $spec_file"
    return 1
  fi

  local status
  status="$(get_spec_status "$spec_id")"

  if [ "$status" = "done" ]; then
    echo "[orchestrator] Spec $spec_id is already done."
    return 0
  fi

  if [ "$status" = "in_review" ]; then
    # Check if the PR was already merged (human/hybrid mode)
    local pr_state
    pr_state="$(get_pr_state "$spec_id")"
    if [ "$pr_state" = "merged" ]; then
      echo "[orchestrator] PR for $spec_id was merged. Marking as done."
      # Ensure we're on base branch before updating status files
      (cd "$PROJECT_ROOT" && git checkout "$BASE_BRANCH" 2>/dev/null && git pull origin "$BASE_BRANCH" 2>/dev/null) || true
      # Use claude to update status so BACKLOG.md stays in sync
      cd "$PROJECT_ROOT" && claude -p "Use /update-status $spec_id done" --allowedTools "Read,Write,Edit,Glob,Grep" 2>/dev/null
      sync_status_to_base "$spec_id"
      return 0
    elif [ "$pr_state" = "none" ]; then
      echo "[orchestrator] No open PR found for $spec_id. Nothing to address."
      return 1
    fi
    echo "[orchestrator] PR for $spec_id is open and in review."
    local pr_url
    pr_url="$(get_pr_url "$spec_id")"
    echo "[orchestrator] PR URL: $pr_url"
    return 0
  fi

  if [ "$status" = "in_progress" ]; then
    local pr_state
    pr_state="$(get_pr_state "$spec_id")"
    if [ "$pr_state" != "open" ]; then
      echo "[orchestrator] No open PR found for $spec_id. Use dev-implement instead."
      return 1
    fi

    echo "[orchestrator] Invoking Dev Agent — mode: address — for $spec_id"
    echo "---"

    invoke_agent "dev.md" "Implement spec $spec_id.

Read pm/specs/${spec_id}.md and follow Address Mode — a reviewer has requested changes on your PR.

**Source directory:** All implementation code must be written inside \`$SOURCE_DIR\` (relative to project root).
**Base branch:** $BASE_BRANCH
**Review mode:** $REVIEW_MODE
**Mode hint:** address_review

**Architecture:** If pm/architecture.md exists, read it and follow its guidelines.

Use /update-status to transition the spec status as needed." "$DEV_AGENT_TOOLS" "${spec_id}_address" "$DEV_MODEL"

    echo ""

    local new_status
    new_status="$(get_spec_status "$spec_id")"
    echo "[orchestrator] Spec $spec_id status after address: $new_status"

    # If back to in_review, optionally run reviewer
    if [ "$new_status" = "in_review" ] && [ "$REVIEW_MODE" = "agent" ]; then
      review_cycle "$spec_id"
    fi

    return 0
  fi

  echo "[orchestrator] Spec $spec_id is in status '$status'. Cannot address — expected in_progress or in_review."
  return 1
}

cmd_review_pending() {
  local found=0

  for spec_file in "$SPECS_DIR"/SPEC-*.md; do
    [ -f "$spec_file" ] || continue
    local st
    st="$(grep -m1 '^status:' "$spec_file" | awk '{print $2}')"
    [ "$st" != "in_review" ] && continue

    local id
    id="$(grep -m1 '^id:' "$spec_file" | awk '{print $2}')"
    found=1

    echo ""
    echo "[orchestrator] Reviewing $id..."

    if [ "$REVIEW_MODE" = "human" ]; then
      local pr_url
      pr_url="$(get_pr_url "$id")"
      if [ -n "$pr_url" ]; then
        echo "[orchestrator] PR for $id: $pr_url"
      else
        echo "[orchestrator] No open PR found for $id."
      fi
    else
      # agent or hybrid — invoke reviewer
      local review_result=0
      review_cycle "$id" || review_result=$?
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "[orchestrator] No specs in review."
  fi
}

# --- Main ---

[ $# -lt 1 ] && usage

# Parse global flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    --max-cycles)
      shift
      [ $# -lt 1 ] && { echo "Error: --max-cycles requires a value"; usage; }
      MAX_CYCLES="$1"
      shift
      ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

[ $# -lt 1 ] && usage

command="$1"
shift

# Show status before any command (except status itself, to avoid double print)
if [ "$command" != "status" ]; then
  show_status
  echo ""
fi

case "$command" in
  status)
    if [ -n "$VERBOSE" ]; then
      show_status --verbose
    else
      show_status
    fi
    ;;
  pm-seed)
    [ $# -lt 1 ] && { echo "Error: pm-seed requires a prompt argument"; usage; }
    cmd_pm_seed "$1"
    ;;
  pm-answer)
    [ $# -lt 1 ] && { echo "Error: pm-answer requires a question file path"; usage; }
    cmd_pm_answer "$1"
    ;;
  pm-answer-pending)
    cmd_pm_answer_pending
    ;;
  pm-add)
    [ $# -lt 1 ] && { echo "Error: pm-add requires a prompt or file path"; usage; }
    cmd_pm_add "$1"
    ;;
  pm-add-interactive)
    cmd_pm_add_interactive
    ;;
  dev-implement)
    [ $# -lt 1 ] && { echo "Error: dev-implement requires a SPEC-ID"; usage; }
    cmd_dev_implement "$1"
    ;;
  dev-implement-next)
    cmd_dev_implement_next
    ;;
  dev-address)
    [ $# -lt 1 ] && { echo "Error: dev-address requires a SPEC-ID"; usage; }
    cmd_dev_address "$1"
    ;;
  dev-auto)
    cmd_dev_auto
    ;;
  review-pending)
    cmd_review_pending
    ;;
  arch-init)
    [ $# -lt 1 ] && { echo "Error: arch-init requires a prompt or file path"; usage; }
    cmd_arch_init "$1"
    ;;
  arch-add)
    [ $# -lt 1 ] && { echo "Error: arch-add requires a prompt or file path"; usage; }
    cmd_arch_add "$1"
    ;;
  arch-add-interactive)
    cmd_arch_add_interactive
    ;;
  arch-review)
    cmd_arch_review
    ;;
  *)
    echo "Unknown command: $command"
    usage
    ;;
esac
