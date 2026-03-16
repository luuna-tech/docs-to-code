#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
SPECS_DIR="$PROJECT_ROOT/pm/specs"
QUESTIONS_DIR="$PROJECT_ROOT/pm/questions"
TASKS_DIR="$PROJECT_ROOT/pm/tasks"

# Tools: PM gets filesystem + web; Dev adds Bash for running tests/builds
AGENT_TOOLS="Read,Write,Edit,Glob,Grep,WebSearch,WebFetch"
DEV_AGENT_TOOLS="Read,Write,Edit,Glob,Grep,Bash,WebSearch,WebFetch"
VERBOSE=""

# --- Load config (defaults, then override from config.yaml) ---

MAX_CYCLES=3
SOURCE_DIR="src/"

if [ -f "$CONFIG_FILE" ]; then
  _cfg_val() { grep -m1 "^[[:space:]]*$1:" "$CONFIG_FILE" | sed "s/^[^:]*:[[:space:]]*//" | sed 's/[[:space:]]*#.*//'; }
  _max="$(_cfg_val max_cycles)"
  [ -n "$_max" ] && MAX_CYCLES="$_max"
  _src="$(_cfg_val source_dir)"
  [ -n "$_src" ] && SOURCE_DIR="$_src"
  unset _cfg_val _max _src
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

  dev-implement <SPEC-ID>    Implement a spec (plan→ask→answer→implement loop).

  dev-implement-next         Find and implement the next eligible spec from the backlog.

  dev-auto                   Unattended mode: continuously pick and implement specs.
                             Stop with Ctrl+C or 'touch .agents/.stop' from another terminal.

Examples:
  $(basename "$0") -v pm-seed "Marketplace de muebles con catálogo, carrito y checkout"
  $(basename "$0") pm-seed docs/project-vision.md
  $(basename "$0") pm-answer pm/questions/SPEC-003-q1.md
  $(basename "$0") -v pm-answer-pending
  $(basename "$0") dev-implement SPEC-001
  $(basename "$0") -v --max-cycles 5 dev-implement SPEC-002
  $(basename "$0") dev-implement-next
  $(basename "$0") -v dev-auto

EOF
  exit 1
}

# Invoke an agent with a prompt. Reads the agent identity file and appends the task.
# Args: <agent_file> <task> [tools_override]
invoke_agent() {
  local agent_file="$1"
  local task="$2"
  local tools="${3:-$AGENT_TOOLS}"

  local identity
  identity="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm{print}' "$SCRIPT_DIR/$agent_file")"

  local full_prompt="$identity

---

# Task

$task"

  if [ -n "$VERBOSE" ]; then
    (cd "$PROJECT_ROOT" && claude -p "$full_prompt" --allowedTools "$tools" --output-format stream-json --verbose) | \
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
    (cd "$PROJECT_ROOT" && claude -p "$full_prompt" --allowedTools "$tools")
  fi
}

# --- Helpers ---

# Read a spec's status from its frontmatter
get_spec_status() {
  local spec_id="$1"
  local spec_file="$SPECS_DIR/${spec_id}.md"

  if [ ! -f "$spec_file" ]; then
    echo "not_found"
    return
  fi

  grep -m1 '^status:' "$spec_file" | awk '{print $2}'
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

$prompt"
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

Use /gen-answer to write the answer. If you discover gaps in the backlog, use /gen-spec to create new specs."
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

    # Determine mode for logging
    local mode="plan"
    if [ "$status" = "in_progress" ] && [ -f "$TASKS_DIR/${spec_id}.md" ]; then
      mode="implement"
    fi

    echo "[orchestrator] Invoking Dev Agent — mode: $mode — cycle $cycle/$MAX_CYCLES"
    echo "---"

    invoke_agent "dev.md" "Implement spec $spec_id.

Read pm/specs/${spec_id}.md and follow your mode of operation (Plan or Implement) based on the spec's current status and the existence of pm/tasks/${spec_id}.md.

**Source directory:** All implementation code must be written inside \`$SOURCE_DIR\` (relative to project root). Create it if it doesn't exist.

If you have questions, use /gen-question to file them and then stop.
If all dependencies are met and you can proceed, implement the spec completely.
Use /update-status to transition the spec status as needed." "$DEV_AGENT_TOOLS"

    echo ""

    # Re-check status after dev agent ran
    local new_status
    new_status="$(get_spec_status "$spec_id")"
    echo "[orchestrator] Spec $spec_id status after dev: $new_status"

    if [ "$new_status" = "done" ]; then
      echo "[orchestrator] Spec $spec_id completed successfully."
      return 0
    fi

    # If status never moved from backlog, the dev hit a blocker (e.g. unmet deps) — no point retrying
    if [ "$new_status" = "backlog" ]; then
      echo "[orchestrator] Spec $spec_id still in backlog — dev reported a blocker. Stopping."
      return 1
    fi

    # Check for pending questions — only reason to loop is to answer them and retry
    local pending
    pending="$(get_pending_questions_for_spec "$spec_id")"

    if [ "$pending" -gt 0 ]; then
      echo "[orchestrator] Pending questions found: $pending"
      echo "[orchestrator] Invoking PM Agent to answer questions for $spec_id..."

      answer_pending_for_spec "$spec_id"
    else
      # No questions and not done — dev may have failed unexpectedly
      echo "[orchestrator] No pending questions and spec is not done."
      echo "[orchestrator] Dev agent may be stuck. Check pm/tasks/${spec_id}.md for details."
      echo "[orchestrator] Stopping — retries are only for pending questions."
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
  result="$(cd "$PROJECT_ROOT" && claude -p "Read pm/specs/BACKLOG.md. Find the highest-priority spec with status 'backlog' whose dependencies are ALL either empty or have status 'done' (check each dependency's status by reading its spec file in pm/specs/).

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

case "$command" in
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
  dev-implement)
    [ $# -lt 1 ] && { echo "Error: dev-implement requires a SPEC-ID"; usage; }
    cmd_dev_implement "$1"
    ;;
  dev-implement-next)
    cmd_dev_implement_next
    ;;
  dev-auto)
    cmd_dev_auto
    ;;
  *)
    echo "Unknown command: $command"
    usage
    ;;
esac
