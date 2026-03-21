# Stata Skill Test Suite

Automated evaluation pipeline for the `stata` Claude Code skill. Sends test tasks to a fresh Claude instance with the skill loaded, judges the output against a rubric, and reports scores with metrics.

## Quick Start

```bash
# Single task — score + metrics
python tests/eval.py tests/tasks/task_01_data_cleaning.md

# Multiple runs for variance analysis
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5

# All tasks
python tests/eval.py tests/tasks/task_*.md

# Save results as a baseline
python tests/eval.py tests/tasks/task_*.md --runs 3 --save tests/results/baseline.json

# Compare current results against a baseline
python tests/eval.py tests/tasks/task_*.md --runs 3 --compare tests/results/baseline.json

# Override model (default: claude-sonnet-4-6)
python tests/eval.py tests/tasks/task_01_data_cleaning.md --model claude-opus-4-6
```

## How It Works

`eval.py` uses the Claude Agent SDK to run two independent `query()` calls per test:

```
task_*.md ──> Test Agent ──> Judge Agent ──> results/run_NNN/
                 │                │
                 v                v
          transcript.json   judge_findings.md
                                  │
                                  v
                            metadata.json (score, cost, tokens, time)
```

1. **Test Agent** — receives the task prompt, runs with the skill loaded via `cwd` auto-discovery (the repo's `.claude-plugin/plugin.json`). Unlimited turns, `bypassPermissions` mode.
2. **Judge Agent** — receives the task, rubric, and transcript. Scores 7 categories (1-5 each) and computes a weighted total out of 55.

Each `query()` call is stateless — no context bleed between tests.

## Pipeline Modes

### Single Run
```bash
python tests/eval.py tests/tasks/task_07_did.md
```
Produces one `run_NNN/` directory with score, transcript, judge findings, and metadata.

### Variance Analysis (`--runs N`)
```bash
python tests/eval.py tests/tasks/task_07_did.md --runs 5
```
Runs the same task N times and reports mean, stdev, and range. Use this to measure consistency. Aim for stdev < 3. High variance signals a documentation gap that causes the agent to take different (sometimes wrong) approaches.

### A/B Comparison (`--compare`)
```bash
# Before editing docs
python tests/eval.py tests/tasks/task_*.md --runs 3 --save tests/results/before.json

# After editing docs
python tests/eval.py tests/tasks/task_*.md --runs 3 --compare tests/results/before.json
```
Prints a delta table showing score changes per task. Look for: mean going up, stdev flat or down, no new failure modes in judge findings. If scores drop, the edit may have introduced confusing examples — simpler is better.

### Parallel Execution
To run multiple tasks in parallel, launch separate processes:
```bash
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5 &
python tests/eval.py tests/tasks/task_07_did.md --runs 5 &
wait
```
Run directories are created atomically, so parallel execution is safe.

## Output Structure

Each run creates `tests/results/run_NNN/` containing:

| File | Contents |
|------|----------|
| `task.md` | Copy of the original task file |
| `transcript.json` | `{"result": "..."}` — the test agent's full response |
| `judge_findings.md` | Per-category scores, justifications, errors, strengths/weaknesses |
| `metadata.json` | Score, model, cost, tokens, duration, timestamp |

### metadata.json fields

```json
{
    "task_file": "task_01_data_cleaning.md",
    "model": "claude-sonnet-4-6",
    "score": 54,
    "score_max": 55,
    "test_duration_ms": 36179,
    "test_cost_usd": 0.0548,
    "test_usage": { "input_tokens": ..., "output_tokens": ..., ... },
    "test_num_turns": 1,
    "judge_duration_ms": 32319,
    "judge_cost_usd": 0.0401,
    "timestamp": "2026-03-20T19:19:50Z"
}
```

## Task File Format

```markdown
# Task N: Title

## Task Prompt

The actual prompt sent to the test agent. Everything under this heading
(until the next ## or # heading, or end of file) is extracted.

## Capabilities Exercised

- What skill areas this tests (gotchas, commands, patterns)

## Reference Files

- Which skill reference files are relevant to this task
```

The `## Task Prompt` heading is required.

## Rubric

Scoring rubric is in `tests/rubric.md`. Seven categories, weighted:

| # | Category | Weight | What it measures |
|---|----------|--------|------------------|
| 1 | Syntax Correctness | PRIMARY (2x) | Valid Stata syntax that would run |
| 2 | Command Selection | PRIMARY (2x) | Right command for the task |
| 3 | Option & Usage Correctness | PRIMARY (2x) | Correct options and arguments |
| 4 | Information Retrieval | PRIMARY (2x) | Found and used correct references |
| 5 | Gotcha Awareness | SECONDARY (1x) | Handled known Stata pitfalls |
| 6 | Completeness | SECONDARY (1x) | Addressed all parts of the request |
| 7 | Idiomaticness | SECONDARY (1x) | Follows Stata conventions |

**Weighted total**: (sum of PRIMARY) * 2 + (sum of SECONDARY) = max 55

## Improving Documentation Based on Test Results

The test-and-improve workflow:

1. **Run with variance** (`--runs 3+`) and save a baseline
2. **Read judge findings** from the lowest-scoring runs — they identify specific documentation gaps
3. **Edit the reference file** to address the gap (add a gotcha, fix an example, clarify an option)
4. **Re-run and compare** against the baseline
5. **Check for regressions** — if scores drop, the edit may be too complex. Keep examples simple; overly clever code patterns get cargo-culted incorrectly

Common documentation issues that lower scores:
- Missing gotcha warnings (missing values, variable naming, operator precedence)
- Incorrect or incomplete code examples
- Complex patterns that the agent reproduces incorrectly (prefer simple, direct examples)
- Conflicting patterns across sections of the same reference file

## Legacy Bash Scripts

The `tests/scripts/` directory contains the original bash pipeline (`run_test.sh`, `judge.sh`, `propose_changes.sh`, `run_pipeline.sh`). These still work for quick one-offs but lack metrics tracking, variance analysis, and A/B comparison. Use `eval.py` for all testing.

## Requirements

- Python 3.10+
- `claude-agent-sdk` (installed via `pip install claude-agent-sdk`)
- Claude Code authenticated (the SDK inherits auth from the session)
