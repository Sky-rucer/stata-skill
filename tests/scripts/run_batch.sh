#!/usr/bin/env bash
# run_batch.sh — Run multiple tasks through the full pipeline in parallel
#
# Usage: ./run_batch.sh [task_files...]
#   If no files given, runs all tests/tasks/task_*.md
#
# Runs in 3 phases:
#   Phase 1: All test runs in parallel
#   Phase 2: All judge evaluations in parallel
#   Phase 3: All change proposals in parallel

set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_BASE="$REPO_ROOT/tests/results"

MAX_PARALLEL=5  # limit concurrent claude calls to avoid rate limits

# ── Collect task files ───────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    TASK_FILES=("$@")
else
    TASK_FILES=("$REPO_ROOT"/tests/tasks/task_*.md)
fi

NUM_TASKS=${#TASK_FILES[@]}

echo "=== Batch Pipeline ==="
echo "Tasks: $NUM_TASKS"
echo "Max parallel: $MAX_PARALLEL"
echo ""

# ── Create run directories upfront (avoid race conditions) ───────────
mkdir -p "$RESULTS_BASE"

# Find next available run number
NEXT_RUN=1
for dir in "$RESULTS_BASE"/run_*/; do
    if [[ -d "$dir" ]]; then
        num="${dir%/}"; num="${num##*run_}"
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= NEXT_RUN )); then
            NEXT_RUN=$(( num + 1 ))
        fi
    fi
done

# Parallel array: RUN_DIRS[i] corresponds to TASK_FILES[i]
RUN_DIRS=()
for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    task_file="${TASK_FILES[$i]}"
    run_dir="$RESULTS_BASE/run_$(printf '%03d' "$NEXT_RUN")"
    mkdir -p "$run_dir"
    cp "$task_file" "$run_dir/task.md"
    RUN_DIRS+=("$run_dir")
    echo "  $(basename "$task_file") -> $(basename "$run_dir")"
    NEXT_RUN=$(( NEXT_RUN + 1 ))
done

echo ""

# ── Helper: throttled parallel execution ─────────────────────────────
run_throttled() {
    local max_j=$1; shift
    local running=0
    local pids=""

    for cmd in "$@"; do
        eval "$cmd" &
        pids="$pids $!"
        running=$(( running + 1 ))

        if (( running >= max_j )); then
            wait -n 2>/dev/null || wait $(echo "$pids" | awk '{print $1}') 2>/dev/null || true
            running=$(( running - 1 ))
            pids=$(echo "$pids" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i}')
        fi
    done

    for pid in $pids; do
        wait "$pid" 2>/dev/null || true
    done
}

# ── Phase 1: Run all tests ──────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PHASE 1: Running $NUM_TASKS tests                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE1_START=$(date +%s)

CMDS=()
for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    task_file="${TASK_FILES[$i]}"
    run_dir="${RUN_DIRS[$i]}"
    prompt_file="$run_dir/_prompt.txt"

    # Extract prompt to file
    awk '
        /^## Task Prompt/ { found=1; next }
        found && /^##? [^#]/ { exit }
        found { print }
    ' "$task_file" > "$prompt_file"

    CMDS+=("unset CLAUDECODE; claude --print --output-format json -p \"\$(cat '$prompt_file')\" > '$run_dir/transcript.json' 2>'$run_dir/stderr.log' || true; echo '  Done: $(basename "$run_dir") - $(basename "$task_file")'")
done

run_throttled $MAX_PARALLEL "${CMDS[@]}"

PHASE1_ELAPSED=$(( $(date +%s) - PHASE1_START ))
echo ""
echo "Phase 1 complete (${PHASE1_ELAPSED}s)"

# Check results
FAILED=0
for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    run_dir="${RUN_DIRS[$i]}"
    if [[ ! -s "$run_dir/transcript.json" ]]; then
        echo "  WARNING: Empty transcript in $(basename "$run_dir")"
        FAILED=$(( FAILED + 1 ))
    fi
done
echo "  Success: $(( NUM_TASKS - FAILED ))/$NUM_TASKS"
echo ""

# ── Phase 2: Judge all runs ──────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PHASE 2: Judging $NUM_TASKS runs                                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE2_START=$(date +%s)

CMDS=()
for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    run_dir="${RUN_DIRS[$i]}"
    if [[ ! -s "$run_dir/transcript.json" ]]; then
        continue
    fi
    CMDS+=("bash '$SCRIPT_DIR/judge.sh' '$run_dir' 2>/dev/null || true; echo '  Judged: $(basename "$run_dir")'")
done

run_throttled $MAX_PARALLEL "${CMDS[@]}"

PHASE2_ELAPSED=$(( $(date +%s) - PHASE2_START ))
echo ""
echo "Phase 2 complete (${PHASE2_ELAPSED}s)"
echo ""

# ── Phase 3: Propose changes for all runs ────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PHASE 3: Proposing changes                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE3_START=$(date +%s)

CMDS=()
for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    run_dir="${RUN_DIRS[$i]}"
    if [[ ! -s "$run_dir/judge_findings.md" ]]; then
        continue
    fi
    CMDS+=("bash '$SCRIPT_DIR/propose_changes.sh' '$run_dir' 2>/dev/null || true; echo '  Proposed: $(basename "$run_dir")'")
done

run_throttled $MAX_PARALLEL "${CMDS[@]}"

PHASE3_ELAPSED=$(( $(date +%s) - PHASE3_START ))
echo ""
echo "Phase 3 complete (${PHASE3_ELAPSED}s)"
echo ""

# ── Summary ──────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  BATCH COMPLETE                                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

printf "  %-40s %-10s %s\n" "TASK" "SCORE" "CHANGES"
printf "  %-40s %-10s %s\n" "----" "-----" "-------"

for i in $(seq 0 $(( NUM_TASKS - 1 ))); do
    task_file="${TASK_FILES[$i]}"
    run_dir="${RUN_DIRS[$i]}"
    task_name=$(basename "$task_file" .md)
    score=$(grep -m1 "Weighted Total" "$run_dir/judge_findings.md" 2>/dev/null | grep -o '[0-9]*/[0-9]*' || echo "N/A")
    changes=$(grep -c "^## Change [0-9]" "$run_dir/proposed_changes.md" 2>/dev/null || echo "0")
    printf "  %-40s %-10s %s\n" "$task_name" "$score" "$changes"
done

TOTAL_ELAPSED=$(( PHASE1_ELAPSED + PHASE2_ELAPSED + PHASE3_ELAPSED ))
echo ""
echo "Total time: ${TOTAL_ELAPSED}s"
