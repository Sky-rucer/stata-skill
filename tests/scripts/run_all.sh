#!/usr/bin/env bash
# run_all.sh — Run all test tasks through Claude CLI sequentially
#
# Usage: ./run_all.sh [--dry-run]
#
# Iterates over all tests/tasks/task_*.md files and runs each through
# run_test.sh. Results go to tests/results/run_NNN/ directories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TASKS_DIR="$REPO_ROOT/tests/tasks"
RUN_TEST="$SCRIPT_DIR/run_test.sh"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# ── Find task files ─────────────────────────────────────────────────
TASK_FILES=()
for f in "$TASKS_DIR"/task_*.md; do
    if [[ -f "$f" ]]; then
        TASK_FILES+=("$f")
    fi
done

if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
    echo "No task files found in $TASKS_DIR"
    echo "Expected files matching: task_*.md"
    exit 1
fi

echo "Found ${#TASK_FILES[@]} task(s):"
for f in "${TASK_FILES[@]}"; do
    echo "  - $(basename "$f")"
done
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would run ${#TASK_FILES[@]} tasks. Exiting."
    exit 0
fi

# ── Run each task ───────────────────────────────────────────────────
PASSED=0
FAILED=0
TOTAL=${#TASK_FILES[@]}

for f in "${TASK_FILES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $(basename "$f")"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if bash "$RUN_TEST" "$f"; then
        PASSED=$(( PASSED + 1 ))
    else
        FAILED=$(( FAILED + 1 ))
        echo "WARNING: Task $(basename "$f") had errors (continuing)"
    fi

    echo ""
done

# ── Summary ─────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ALL TASKS COMPLETE"
echo "  Total:  $TOTAL"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
