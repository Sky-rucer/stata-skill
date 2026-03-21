#!/usr/bin/env bash
# run_pipeline.sh — Run the full test pipeline for a single task
#
# Usage: ./run_pipeline.sh <task_file.md>
#
# Steps:
#   1. run_test.sh   -> transcript.json
#   2. judge.sh      -> judge_findings.md
#   3. propose_changes.sh -> proposed_changes.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <task_file.md>"
    exit 1
fi

TASK_FILE="$1"

# ── Step 1: Run test ────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  STEP 1/3: Running test                                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

bash "$SCRIPT_DIR/run_test.sh" "$TASK_FILE"

# Find the most recently created run directory
LATEST_RUN=$(ls -td "$REPO_ROOT/tests/results"/run_*/ 2>/dev/null | head -1)
if [[ -z "$LATEST_RUN" ]]; then
    echo "Error: No results directory found after run_test.sh"
    exit 1
fi
# Remove trailing slash
LATEST_RUN="${LATEST_RUN%/}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  STEP 2/3: Judge evaluation                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Step 2: Judge ───────────────────────────────────────────────────
bash "$SCRIPT_DIR/judge.sh" "$LATEST_RUN"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  STEP 3/3: Propose changes                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Step 3: Propose changes ────────────────────────────────────────
bash "$SCRIPT_DIR/propose_changes.sh" "$LATEST_RUN"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PIPELINE COMPLETE                                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Results directory: $LATEST_RUN"
echo ""
echo "Files produced:"
for f in "$LATEST_RUN"/*.{md,json,log} 2>/dev/null; do
    if [[ -f "$f" ]]; then
        echo "  $(basename "$f")"
    fi
done
