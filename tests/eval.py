#!/usr/bin/env python3
"""Agent SDK test harness for stata-skill evaluation.

Replaces the bash pipeline (run_test.sh → judge.sh) with a single script
that tracks metrics (tokens, cost, time, score) and supports variance
analysis and A/B comparison against baselines.

Usage:
    # Single task
    python tests/eval.py tests/tasks/task_01_data_cleaning.md

    # Multiple tasks
    python tests/eval.py tests/tasks/task_*.md

    # Variance analysis (run same task 3 times)
    python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 3

    # Compare against a saved baseline
    python tests/eval.py tests/tasks/task_*.md --compare tests/results/baseline.json

    # Save results as a baseline for future comparisons
    python tests/eval.py tests/tasks/task_*.md --save tests/results/baseline.json
"""

import argparse
import asyncio
import json
import re
import statistics
import sys
import time
from pathlib import Path

from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query

REPO_ROOT = Path(__file__).resolve().parent.parent
RUBRIC_FILE = REPO_ROOT / "tests" / "rubric.md"
RESULTS_BASE = REPO_ROOT / "tests" / "results"

# Default model for test + judge agents. Sonnet balances cost and quality
# for repeated eval runs. Use --model claude-opus-4-6 for higher quality.
DEFAULT_MODEL = "claude-sonnet-4-6"


def extract_task_prompt(task_path: Path) -> str:
    """Extract the ## Task Prompt section from a task file."""
    lines = task_path.read_text().splitlines()
    capturing = False
    prompt_lines = []
    for line in lines:
        if line.startswith("## Task Prompt"):
            capturing = True
            continue
        if capturing and re.match(r"^##? [^#]", line):
            break
        if capturing:
            prompt_lines.append(line)
    text = "\n".join(prompt_lines).strip()
    if not text:
        raise ValueError(f"No '## Task Prompt' section found in {task_path}")
    return text


def extract_score(judge_text: str) -> int | None:
    """Extract weighted total from judge findings.

    Takes the last match — judges sometimes self-correct arithmetic mid-response.
    """
    matches = re.findall(r"Weighted Total[:\s]*(\d+)\s*/\s*55", judge_text)
    return int(matches[-1]) if matches else None


def create_run_dir() -> Path:
    """Atomically create the next run_NNN directory.

    Uses mkdir (without exist_ok) as an atomic test-and-set: if two processes
    race for the same number, one gets FileExistsError and retries with the
    next number.  This eliminates the TOCTOU window that next_run_number() had.
    """
    RESULTS_BASE.mkdir(parents=True, exist_ok=True)
    for _ in range(200):  # generous upper bound to prevent infinite loops
        max_num = 0
        for d in RESULTS_BASE.iterdir():
            if d.is_dir() and d.name.startswith("run_"):
                try:
                    num = int(d.name.split("_", 1)[1])
                    max_num = max(max_num, num)
                except ValueError:
                    pass
        run_dir = RESULTS_BASE / f"run_{max_num + 1:03d}"
        try:
            run_dir.mkdir()  # atomic: fails if another process won the race
            return run_dir
        except FileExistsError:
            continue  # someone else grabbed it — rescan and retry
    raise RuntimeError("Could not allocate a run directory after 200 attempts")


JUDGE_PROMPT_TEMPLATE = """\
You are a Stata code quality judge. Evaluate how well the agent responded \
to a Stata programming task.

Focus on Stata code quality, correctness, and idiomatic usage — NOT general \
helpfulness or verbosity. Follow the rubric scoring instructions exactly, \
including the weighted total formula.

Output your evaluation in this exact format:

# Judge Findings

## Category Scores

### [Category Name]: X / 5
**Justification:** [2-3 sentences with specific code examples]

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

## Original Task

{task_text}

## Scoring Rubric

{rubric}

## Agent Transcript

{transcript}
"""


async def run_test(task_path: Path, model: str) -> dict:
    """Run a single test task and judge it. Returns structured results."""
    prompt = extract_task_prompt(task_path)
    rubric = RUBRIC_FILE.read_text()
    task_text = task_path.read_text()

    # --- Step 1: Test agent (unlimited turns, skill auto-discovered via cwd) ---
    test_result = None
    test_transcript = ""

    async for msg in query(
        prompt=prompt,
        options=ClaudeAgentOptions(
            model=model,
            permission_mode="bypassPermissions",
            cwd=str(REPO_ROOT),
            system_prompt=(
                "You are a Stata expert. Answer the user's Stata programming "
                "question with correct, idiomatic code."
            ),
        ),
    ):
        if isinstance(msg, ResultMessage):
            test_result = msg
            test_transcript = msg.result or ""

    if test_result is None:
        raise RuntimeError(f"No result from test agent for {task_path.name}")

    # --- Step 2: Judge agent ---
    judge_prompt = JUDGE_PROMPT_TEMPLATE.format(
        task_text=task_text,
        rubric=rubric,
        transcript=test_transcript,
    )

    judge_result = None
    judge_text = ""

    async for msg in query(
        prompt=judge_prompt,
        options=ClaudeAgentOptions(
            model=model,
            permission_mode="bypassPermissions",
            system_prompt="You are an expert Stata code reviewer and judge.",
        ),
    ):
        if isinstance(msg, ResultMessage):
            judge_result = msg
            judge_text = msg.result or ""

    return {
        "task": task_path.name,
        "score": extract_score(judge_text),
        "score_max": 55,
        "model": model,
        "test": {
            "duration_ms": test_result.duration_ms,
            "duration_api_ms": test_result.duration_api_ms,
            "cost_usd": test_result.total_cost_usd,
            "usage": test_result.usage,
            "num_turns": test_result.num_turns,
            "is_error": test_result.is_error,
            "transcript": test_transcript,
        },
        "judge": {
            "duration_ms": judge_result.duration_ms if judge_result else None,
            "cost_usd": judge_result.total_cost_usd if judge_result else None,
            "findings": judge_text,
        },
    }


async def run_single(task_path: Path, model: str, run_dir: Path) -> dict:
    """Run a single test, save results, return the result dict."""
    print(f"  Running: {task_path.name}")
    result = await run_test(task_path, model)

    # Save artifacts (same layout as bash pipeline for compatibility)
    (run_dir / "task.md").write_text(task_path.read_text())
    (run_dir / "transcript.json").write_text(
        json.dumps({"result": result["test"]["transcript"]}, indent=2)
    )
    (run_dir / "judge_findings.md").write_text(result["judge"]["findings"])

    metadata = {
        "task_file": result["task"],
        "model": result["model"],
        "score": result["score"],
        "score_max": result["score_max"],
        "test_duration_ms": result["test"]["duration_ms"],
        "test_cost_usd": result["test"]["cost_usd"],
        "test_usage": result["test"]["usage"],
        "test_num_turns": result["test"]["num_turns"],
        "judge_duration_ms": result["judge"]["duration_ms"],
        "judge_cost_usd": result["judge"]["cost_usd"],
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (run_dir / "metadata.json").write_text(json.dumps(metadata, indent=2))

    score_str = (
        f"{result['score']}/55" if result["score"] is not None else "parse error"
    )
    cost = result["test"]["cost_usd"]
    cost_str = f"${cost:.4f}" if cost else "n/a"
    dur = result["test"]["duration_ms"] / 1000
    print(
        f"  Done: {task_path.name} — score={score_str}, "
        f"cost={cost_str}, time={dur:.1f}s"
    )

    return result


def print_summary_table(results: list[dict]):
    """Print a summary table of all results."""
    print()
    print(
        f"{'Task':<40} {'Score':>8} {'Cost':>10} {'Time (s)':>10} {'Turns':>6}"
    )
    print("-" * 78)
    for r in results:
        score = f"{r['score']}/55" if r["score"] is not None else "err"
        cost = (
            f"${r['test']['cost_usd']:.4f}" if r["test"]["cost_usd"] else "n/a"
        )
        dur = f"{r['test']['duration_ms'] / 1000:.1f}"
        turns = str(r["test"]["num_turns"])
        print(f"{r['task']:<40} {score:>8} {cost:>10} {dur:>10} {turns:>6}")
    print()


def print_variance_report(
    task_name: str,
    scores: list[int | None],
    costs: list[float | None],
    durations: list[float],
):
    """Print variance statistics for repeated runs."""
    valid_scores = [s for s in scores if s is not None]
    valid_costs = [c for c in costs if c is not None]

    print(f"\n  Variance report for {task_name} ({len(scores)} runs):")

    if len(valid_scores) >= 2:
        mean_s = statistics.mean(valid_scores)
        stdev_s = statistics.stdev(valid_scores)
        print(
            f"    Score:    mean={mean_s:.1f}/55  stdev={stdev_s:.1f}  "
            f"range=[{min(valid_scores)}, {max(valid_scores)}]"
        )
    elif valid_scores:
        print(f"    Score:    {valid_scores[0]}/55 (single run)")

    if len(valid_costs) >= 2:
        mean_c = statistics.mean(valid_costs)
        stdev_c = statistics.stdev(valid_costs)
        print(f"    Cost:     mean=${mean_c:.4f}  stdev=${stdev_c:.4f}")

    if len(durations) >= 2:
        mean_d = statistics.mean(durations)
        stdev_d = statistics.stdev(durations)
        print(f"    Duration: mean={mean_d:.1f}s  stdev={stdev_d:.1f}s")
    print()


def compare_with_baseline(results: list[dict], baseline_path: Path):
    """Compare current results against a saved baseline."""
    baseline = json.loads(baseline_path.read_text())
    baseline_by_task = {r["task"]: r for r in baseline}

    print(f"\n  A/B comparison against {baseline_path.name}:")
    print(f"  {'Task':<35} {'Baseline':>10} {'Current':>10} {'Delta':>8}")
    print("  " + "-" * 67)

    for r in results:
        b = baseline_by_task.get(r["task"])
        if b and b.get("score") is not None and r["score"] is not None:
            delta = r["score"] - b["score"]
            sign = "+" if delta > 0 else ""
            print(
                f"  {r['task']:<35} {b['score']:>7}/55 "
                f"{r['score']:>7}/55 {sign}{delta:>7}"
            )
        elif r["score"] is not None:
            print(
                f"  {r['task']:<35} {'n/a':>10} "
                f"{r['score']:>7}/55 {'new':>8}"
            )
    print()


async def main():
    parser = argparse.ArgumentParser(
        description="Stata skill test harness (Agent SDK)"
    )
    parser.add_argument("tasks", nargs="+", help="Task file(s) to evaluate")
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"Model for test + judge (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=5,
        help="Run each task N times for variance analysis (default: 5)",
    )
    parser.add_argument(
        "--compare",
        type=Path,
        metavar="BASELINE",
        help="Compare results against a baseline JSON file",
    )
    parser.add_argument(
        "--save",
        type=Path,
        metavar="FILE",
        help="Save results summary to JSON (for use as future baseline)",
    )
    args = parser.parse_args()

    task_paths = [Path(t).resolve() for t in args.tasks]
    for tp in task_paths:
        if not tp.exists():
            print(f"Error: task file not found: {tp}", file=sys.stderr)
            sys.exit(1)

    if not RUBRIC_FILE.exists():
        print(f"Error: rubric not found: {RUBRIC_FILE}", file=sys.stderr)
        sys.exit(1)

    print(f"Model: {args.model}")
    print(f"Tasks: {len(task_paths)}, Runs per task: {args.runs}")
    print()

    all_results = []

    for task_path in task_paths:
        task_results = []
        for run_idx in range(args.runs):
            run_dir = create_run_dir()

            if args.runs > 1:
                print(f"  [{run_idx + 1}/{args.runs}]", end=" ")

            result = await run_single(task_path, args.model, run_dir)
            task_results.append(result)

        all_results.extend(task_results)

        # Variance report if multiple runs
        if args.runs > 1:
            scores = [r["score"] for r in task_results]
            costs = [r["test"]["cost_usd"] for r in task_results]
            durations = [r["test"]["duration_ms"] / 1000 for r in task_results]
            print_variance_report(task_path.name, scores, costs, durations)

    # Summary table
    print_summary_table(all_results)

    # A/B comparison
    if args.compare:
        compare_with_baseline(all_results, args.compare)

    # Save results
    save_path = args.save
    if save_path is None and len(all_results) > 1:
        save_path = RESULTS_BASE / "latest_batch.json"

    if save_path:
        summary = [
            {
                "task": r["task"],
                "score": r["score"],
                "score_max": r["score_max"],
                "model": r["model"],
                "cost_usd": r["test"]["cost_usd"],
                "duration_ms": r["test"]["duration_ms"],
                "num_turns": r["test"]["num_turns"],
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            }
            for r in all_results
        ]
        save_path.parent.mkdir(parents=True, exist_ok=True)
        save_path.write_text(json.dumps(summary, indent=2))
        print(f"Results saved to {save_path}")


if __name__ == "__main__":
    asyncio.run(main())
