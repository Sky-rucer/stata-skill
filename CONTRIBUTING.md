# Contributing to stata-skill

Thanks for considering a contribution! The easiest way to help is by adding documentation for a Stata package you know well.

## Adding a New Package

1. **Fork this repo** and create a branch.

2. **Create a new file** in `plugins/stata/skills/stata/packages/` named after the package:
   ```
   plugins/stata/skills/stata/packages/your-package.md
   ```

3. **Use this template** as a starting point:

   ````markdown
   # your-package: One-Line Description

   ## Installation

   ```stata
   ssc install your-package
   * or
   net install your-package, from("https://...")
   ```

   ## Overview

   Brief description of what the package does and when to use it.
   Mention what makes it different from built-in alternatives.

   ## Basic Usage

   ```stata
   * Minimal working example
   sysuse auto, clear
   your_command price mpg weight, option1 option2
   ```

   ## Key Options

   | Option | Description |
   |--------|-------------|
   | `option1` | What it does |
   | `option2` | What it does |

   ## Common Workflows

   Show 2-3 realistic use cases with complete code examples.

   ## Gotchas

   - List non-obvious behavior, common mistakes, version quirks
   - Note any dependencies on other packages

   ## See Also

   - Related built-in commands
   - Related community packages
   ````

4. **Add a routing table entry** in `plugins/stata/skills/stata/SKILL.md` under the `### Community Packages` table:
   ```
   | `packages/your-package.md` | Brief description of what it does |
   ```

   **Important:** The description column is a **trigger condition**, not a summary. It tells the model *when* to load this file. Write it from the perspective of "what is the user asking about?" — not "what does this file contain?"

   ```
   # Bad — describes the file
   | `packages/reghdfe.md` | reghdfe package documentation |

   # Good — describes when to load it
   | `packages/reghdfe.md` | High-dimensional fixed effects OLS (absorbs multiple FE sets efficiently) |
   ```

   Ask yourself: "If a user's question matches this description, should Claude load this file?" If yes, it's a good trigger.

5. **Test your package documentation.** The goal is to verify that Claude can actually use what you wrote to solve real problems. Ask Claude Code to run the test pipeline for you — it handles everything. (See [`tests/README.md`](tests/README.md) for full details on the pipeline, output format, and scoring rubric.)

   a. **Write a test task** in `tests/tasks/` that asks Claude to do something realistic with the package. Follow the format of existing tasks — each needs a `## Task Prompt` section with the actual prompt, a `## Capabilities Exercised` section listing what's being tested, and a `## Reference Files` section pointing to the relevant docs.

   b. **Ask Claude Code to run the eval pipeline.** The repo includes `tests/eval.py`, a Claude Agent SDK harness that sends each task to a fresh Claude instance with the skill installed, has a separate judge instance score the response against `tests/rubric.md`, and reports metrics. Tell Claude Code something like:

   > "Run the eval pipeline on my new task with 3 runs and save a baseline."

   Claude Code will execute the appropriate commands:
   ```bash
   # What Claude runs under the hood:
   python tests/eval.py tests/tasks/your_task.md --runs 3 --save tests/results/baseline_yourpkg.json
   ```

   c. **Review the results together.** Each run produces a `tests/results/run_NNN/` directory with:
   - `transcript.json` — the agent's full response
   - `judge_findings.md` — per-category scores with justifications
   - `metadata.json` — score, cost, tokens, duration, model

   Ask Claude Code to review the judge findings and explain what went wrong. If scores are low, the issue is usually in the documentation — not the test. Common causes:
   - Missing or ambiguous option descriptions
   - Gotchas that aren't documented
   - Syntax examples that don't cover the use case

   d. **Iterate.** Have Claude Code update the package docs based on the judge findings, then re-run and compare against the baseline:

   > "The judge says the agent missed the X gotcha. Add a warning to the package docs, then re-run and compare against the baseline."

   Look for: mean score going up, stdev staying flat or going down, no new failure modes. If the score drops, the edit may have introduced confusing examples — simpler is better.

   Claude Code can also automate this entire loop: run the test, review the judge findings, propose doc improvements, re-run, and compare — all without manual intervention.

6. **Open a pull request** with a brief description of the package and why it's useful. Include your test results (scores, variance, before/after comparison if you iterated). PRs will be reviewed by Claude Code for accuracy, completeness, and consistency with the existing skill documentation before being accepted.

## Guidelines

- **Keep it practical.** Focus on syntax, options, and working examples. Skip generic theory that any LLM already knows.
- **Include gotchas.** Non-obvious behavior is the most valuable thing you can document.
- **One file per package.** Don't merge multiple packages into one file.
- **Test your examples.** Make sure code blocks actually run in Stata.
- **Add a table of contents** to any file over 100 lines. Place a `## Contents` section after the H1 heading with markdown links to each H2 section.
- **No personal info.** Don't include machine-specific paths, names, or credentials in examples. Use generic paths like `"$data/myfile.dta"`.

## Improving Existing Docs

Found an error or want to add a missing option? PRs for existing files are welcome too. Keep changes focused and explain what you're fixing.

## Questions?

Open an issue if you're unsure about anything.
