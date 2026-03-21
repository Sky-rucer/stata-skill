#!/usr/bin/env bash
# propose_changes.sh — Propose skill file edits based on judge findings
#
# Usage: ./propose_changes.sh <results_dir>
#
# Reads from the results directory:
#   - task.md             (the original task file)
#   - transcript.json     (claude CLI output)
#   - judge_findings.md   (judge scores + justifications)
#
# Also reads:
#   - skills/stata/SKILL.md  (current skill routing table)
#
# Produces:
#   - proposed_changes.md  (concrete file edits to improve the skill)

set -euo pipefail

# Allow running claude inside a Claude Code session
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/stata"
SKILL_FILE="$SKILL_DIR/SKILL.md"

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
JUDGE_FILE="$RESULTS_DIR/judge_findings.md"

for f in "$TASK_FILE" "$TRANSCRIPT_FILE" "$JUDGE_FILE" "$SKILL_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Required file not found: $f"
        exit 1
    fi
done

echo "=== Change Proposer ==="
echo "Results dir: $RESULTS_DIR"
echo "Skill file:  $SKILL_FILE"
echo ""

# ── Extract transcript text ─────────────────────────────────────────
TRANSCRIPT_TEXT=""
if command -v jq &>/dev/null; then
    TRANSCRIPT_TEXT=$(jq -r '.result // empty' "$TRANSCRIPT_FILE" 2>/dev/null || true)
fi
if [[ -z "$TRANSCRIPT_TEXT" ]]; then
    TRANSCRIPT_TEXT=$(cat "$TRANSCRIPT_FILE")
fi

# ── Collect reference file listing ──────────────────────────────────
REF_LISTING=""
if [[ -d "$SKILL_DIR/references" ]]; then
    REF_LISTING=$(ls -1 "$SKILL_DIR/references/" 2>/dev/null || true)
fi
PKG_LISTING=""
if [[ -d "$SKILL_DIR/packages" ]]; then
    PKG_LISTING=$(ls -1 "$SKILL_DIR/packages/" 2>/dev/null || true)
fi

# ── Build prompt in temp file (avoids shell quoting issues) ─────────
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" << 'STATIC_END'
You are a skill improvement advisor for a Claude Code Stata skill. Your job is to analyze judge findings from a test evaluation and propose concrete edits to the skill files that would fix the identified weaknesses.

You will be given:
1. The original task prompt that was tested
2. The agent response transcript
3. The judge findings (scores and justifications)
4. The current SKILL.md file (the main routing table)
5. A listing of available reference and package files

Propose specific, actionable changes. Each proposal should include:
- File: The exact file path relative to skills/stata/
- Action: Add, Modify, or Create
- What to change: The specific content to add, modify, or remove
- Justification: How this change addresses a specific weakness from the judge findings
- Priority: High / Medium / Low

Rules:
- SKILL.md must stay under 500 lines
- Detailed content belongs in reference files, not SKILL.md
- Focus on Stata correctness and idiomatic patterns, not general verbosity
- Only propose changes that directly address judge-identified weaknesses
- If the agent performed well (scores 4-5), propose minimal or no changes
- Be specific: include example code snippets or exact text to add

Output format:

# Proposed Changes

## Summary
[1-2 sentences: what the main gaps are and how many changes are proposed]

## Change 1: [Brief title]
- File: [path]
- Action: [Add/Modify/Create]
- Priority: [High/Medium/Low]
- Justification: [Which judge finding this addresses]
- Details: [exact content to add or change]

(repeat for each proposed change)

## No Changes Needed
[If scores are all 4+, state that no changes are needed and why]

STATIC_END

# Append dynamic content by writing to file (no shell interpolation issues)
printf '\n---\n\n## Original Task\n\n' >> "$PROMPT_FILE"
cat "$TASK_FILE" >> "$PROMPT_FILE"
printf '\n\n## Agent Transcript\n\n%s\n' "$TRANSCRIPT_TEXT" >> "$PROMPT_FILE"
printf '\n\n## Judge Findings\n\n' >> "$PROMPT_FILE"
cat "$JUDGE_FILE" >> "$PROMPT_FILE"
printf '\n\n## Current SKILL.md\n\n' >> "$PROMPT_FILE"
cat "$SKILL_FILE" >> "$PROMPT_FILE"
printf '\n\n## Available Reference Files (skills/stata/references/)\n%s\n' "${REF_LISTING:-[none found]}" >> "$PROMPT_FILE"
printf '\n## Available Package Files (skills/stata/packages/)\n%s\n' "${PKG_LISTING:-[none found]}" >> "$PROMPT_FILE"

# ── Run proposer ────────────────────────────────────────────────────
echo "Running change proposer..."

claude --print \
    -p "$(cat "$PROMPT_FILE")" \
    > "$RESULTS_DIR/proposed_changes.md" 2>"$RESULTS_DIR/proposer_stderr.log" || {
        EXIT_CODE=$?
        echo "Warning: claude proposer exited with code $EXIT_CODE"
        echo "Check $RESULTS_DIR/proposer_stderr.log for details"
    }

echo ""
echo "=== Proposer Complete ==="
echo "Output: $RESULTS_DIR/proposed_changes.md"

if [[ -s "$RESULTS_DIR/proposed_changes.md" ]]; then
    CHANGE_COUNT=$(grep -c "^## Change [0-9]" "$RESULTS_DIR/proposed_changes.md" || echo "0")
    echo "Proposed changes: $CHANGE_COUNT"
else
    echo "Warning: proposed_changes.md is empty"
fi
