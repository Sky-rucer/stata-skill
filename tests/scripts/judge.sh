#!/usr/bin/env bash
# judge.sh — Score a test run against the rubric using Claude as judge
#
# Usage: ./judge.sh <results_dir>
#
# Reads from the results directory:
#   - task.md          (the original task file)
#   - transcript.json  (claude CLI output)
#
# Also reads:
#   - tests/rubric.md  (scoring rubric)
#
# Produces:
#   - judge_findings.md  (scores + justifications per rubric category)

set -euo pipefail

# Allow running claude inside a Claude Code session
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUBRIC_FILE="$REPO_ROOT/tests/rubric.md"

# ── Validate arguments ──────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <results_dir>"
    echo "  e.g. $0 tests/results/run_001"
    exit 1
fi

RESULTS_DIR="$1"

# Resolve relative paths
if [[ ! "$RESULTS_DIR" = /* ]]; then
    RESULTS_DIR="$(pwd)/$RESULTS_DIR"
fi

if [[ ! -d "$RESULTS_DIR" ]]; then
    echo "Error: Results directory not found: $RESULTS_DIR"
    exit 1
fi

# ── Check required files ────────────────────────────────────────────
TASK_FILE="$RESULTS_DIR/task.md"
TRANSCRIPT_FILE="$RESULTS_DIR/transcript.json"

for f in "$TASK_FILE" "$TRANSCRIPT_FILE" "$RUBRIC_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Required file not found: $f"
        exit 1
    fi
done

echo "=== Judge Evaluation ==="
echo "Results dir: $RESULTS_DIR"
echo "Rubric:      $RUBRIC_FILE"
echo ""

# ── Extract transcript text ─────────────────────────────────────────
TRANSCRIPT_TEXT=""
if command -v jq &>/dev/null; then
    TRANSCRIPT_TEXT=$(jq -r '.result // empty' "$TRANSCRIPT_FILE" 2>/dev/null || true)
fi
if [[ -z "$TRANSCRIPT_TEXT" ]]; then
    TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE")
fi

# ── Build prompt in temp file (avoids shell quoting issues) ─────────
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" << 'STATIC_END'
You are a Stata code quality judge. Your job is to evaluate how well a Claude Code agent responded to a Stata programming task.

You will be given:
1. The original task prompt
2. The scoring rubric with categories
3. The agent's response transcript

Focus on Stata code quality, correctness, and idiomatic usage -- NOT general helpfulness or verbosity. Follow the rubric scoring instructions exactly, including the weighted total formula.

Output your evaluation in this exact format:

# Judge Findings

## Category Scores

### [Category Name]: X / 5
**Justification:** [2-3 sentences explaining the score with specific code examples]

(repeat for each of the 7 rubric categories)

## Weighted Total: XX / 55
(PRIMARY categories count 2x, SECONDARY count 1x per the rubric formula)

## Errors Found
- [specific errors with code references]

## Key Strengths
- [bullet points]

## Key Weaknesses
- [bullet points]

## Summary
[1-2 sentence overall assessment]

---

STATIC_END

# Append dynamic content by writing to file (no shell interpolation issues)
printf '\n## Original Task\n\n' >> "$PROMPT_FILE"
cat "$TASK_FILE" >> "$PROMPT_FILE"
printf '\n\n## Scoring Rubric\n\n' >> "$PROMPT_FILE"
cat "$RUBRIC_FILE" >> "$PROMPT_FILE"
printf '\n\n## Agent Transcript\n\n%s\n' "$TRANSCRIPT_TEXT" >> "$PROMPT_FILE"

# ── Run judge ───────────────────────────────────────────────────────
echo "Running judge evaluation..."

claude --print \
    -p "$(cat "$PROMPT_FILE")" \
    > "$RESULTS_DIR/judge_findings.md" 2>"$RESULTS_DIR/judge_stderr.log" || {
        EXIT_CODE=$?
        echo "Warning: claude judge exited with code $EXIT_CODE"
        echo "Check $RESULTS_DIR/judge_stderr.log for details"
    }

echo ""
echo "=== Judge Complete ==="
echo "Output: $RESULTS_DIR/judge_findings.md"

if [[ -s "$RESULTS_DIR/judge_findings.md" ]]; then
    SCORE_LINE=$(grep -m1 "Weighted Total" "$RESULTS_DIR/judge_findings.md" || true)
    if [[ -n "$SCORE_LINE" ]]; then
        echo "$SCORE_LINE"
    fi
else
    echo "Warning: judge_findings.md is empty"
fi
