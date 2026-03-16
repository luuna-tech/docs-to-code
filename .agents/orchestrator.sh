#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SPECS_DIR="$PROJECT_ROOT/pm/specs"
QUESTIONS_DIR="$PROJECT_ROOT/pm/questions"

# Tools agents need for filesystem access
AGENT_TOOLS="Read,Write,Edit,Glob,Grep"
VERBOSE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [-v] <command> [options]

Options:
  -v, --verbose   Show agent tool calls and progress in real time.

Commands:
  pm-seed <prompt|file>   Generate initial backlog from a high-level description.
                          Accepts an inline string or a path to a .md file.

  pm-answer <question>    Invoke PM Agent to answer a developer question.
                          <question> is the path to a question file in pm/questions/.

  pm-answer-pending       Find and answer all unanswered questions in pm/questions/.

Examples:
  $(basename "$0") -v pm-seed "Marketplace de muebles con catálogo, carrito y checkout"
  $(basename "$0") pm-seed docs/project-vision.md
  $(basename "$0") pm-answer pm/questions/SPEC-003-q1.md
  $(basename "$0") -v pm-answer-pending

EOF
  exit 1
}

# Invoke an agent with a prompt. Reads the agent identity file and appends the task.
invoke_agent() {
  local agent_file="$1"
  local task="$2"

  local identity
  identity="$(awk 'NR==1 && /^---$/{fm=1; next} fm && /^---$/{fm=0; next} !fm{print}' "$SCRIPT_DIR/$agent_file")"

  local full_prompt="$identity

---

# Task

$task"

  local verbose_flag=""
  [ -n "$VERBOSE" ] && verbose_flag="--verbose"

  (cd "$PROJECT_ROOT" && claude -p "$full_prompt" --allowedTools "$AGENT_TOOLS" $verbose_flag)
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

# --- Main ---

[ $# -lt 1 ] && usage

# Parse global flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
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
  *)
    echo "Unknown command: $command"
    usage
    ;;
esac
