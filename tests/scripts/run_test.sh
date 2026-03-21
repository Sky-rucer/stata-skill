#!/usr/bin/env bash
# run_test.sh — Run a single skill test task through Claude CLI
#
# Usage: ./run_test.sh <task_file.md>
#
# Creates tests/results/run_NNN/ with:
#   - transcript.json   (claude --print --output-format json output)
#   - task.md            (copy of the original task file)

set -euo pipefail

# Allow running claude inside a Claude Code session
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_BASE="$REPO_ROOT/tests/results"

# ── Validate arguments ──────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <task_file.md>"
    exit 1
fi

TASK_FILE="$1"

if [[ ! -f "$TASK_FILE" ]]; then
    echo "Error: Task file not found: $TASK_FILE"
    exit 1
fi

# ── Create results directory with auto-incrementing run number ──────
mkdir -p "$RESULTS_BASE"

# Find the next run number
NEXT_RUN=1
for dir in "$RESULTS_BASE"/run_*/; do
    if [[ -d "$dir" ]]; then
        num="${dir%/}"
        num="${num##*run_}"
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= NEXT_RUN )); then
            NEXT_RUN=$(( num + 1 ))
        fi
    fi
done

RUN_DIR="$RESULTS_BASE/run_$(printf '%03d' "$NEXT_RUN")"
mkdir -p "$RUN_DIR"

echo "=== Test Run $NEXT_RUN ==="
echo "Task: $TASK_FILE"
echo "Results: $RUN_DIR"
echo ""

# ── Copy original task file ─────────────────────────────────────────
cp "$TASK_FILE" "$RUN_DIR/task.md"

# ── Extract prompt from "## Task Prompt" section ────────────────────
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

awk '
    /^## Task Prompt/ { found=1; next }
    found && /^##? [^#]/ { exit }
    found { print }
' "$TASK_FILE" > "$PROMPT_FILE"

if [[ ! -s "$PROMPT_FILE" ]]; then
    echo "Error: No '## Task Prompt' section found in $TASK_FILE"
    exit 1
fi

PROMPT_LEN=$(wc -c < "$PROMPT_FILE" | tr -d ' ')
echo "Prompt extracted ($PROMPT_LEN bytes)"
echo "Running claude..."
echo ""

# ── Run claude CLI ──────────────────────────────────────────────────
START_TIME=$(date +%s)

claude --print \
    --output-format json \
    -p "$(cat "$PROMPT_FILE")" \
    > "$RUN_DIR/transcript.json" 2>"$RUN_DIR/stderr.log" || {
        EXIT_CODE=$?
        echo "Warning: claude exited with code $EXIT_CODE"
        echo "Check $RUN_DIR/stderr.log for details"
    }

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# ── Record metadata ────────────────────────────────────────────────
TASK_BASENAME=$(basename "$TASK_FILE")
cat > "$RUN_DIR/metadata.json" <<EOF
{
    "task_file": "$TASK_BASENAME",
    "run_number": $NEXT_RUN,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "elapsed_seconds": $ELAPSED
}
EOF

echo ""
echo "=== Complete ==="
echo "Duration: ${ELAPSED}s"
echo "Transcript: $RUN_DIR/transcript.json"
echo "Metadata:   $RUN_DIR/metadata.json"

if [[ -s "$RUN_DIR/transcript.json" ]]; then
    echo "Transcript size: $(wc -c < "$RUN_DIR/transcript.json" | tr -d ' ') bytes"
else
    echo "Warning: transcript.json is empty"
fi
