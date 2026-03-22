# Contributing to stata-skill

Thanks for considering a contribution! There are several ways to help:

- **Add documentation** for a Stata package you know well (see [Adding a New Package](#adding-a-new-package))
- **Report issues or submit PRs** based on problems you hit in your own Stata work (see [Report real-world issues](#report-real-world-issues))
- **Suggest new tests** based on real-world usage (see [Suggest new tests](#suggest-new-tests))
- **Tackle a bigger-picture item** on the [ROADMAP.md](ROADMAP.md) (see [Tackle a roadmap item](#tackle-a-roadmap-item))

## Contents

- [Adding a New Package](#adding-a-new-package)
- [Guidelines](#guidelines)
- [Other Ways to Contribute](#other-ways-to-contribute)
  - [Report real-world issues](#report-real-world-issues)
  - [Suggest new tests](#suggest-new-tests)
  - [Improve existing docs](#improve-existing-docs)
  - [Tackle a roadmap item](#tackle-a-roadmap-item)
- [Questions?](#questions)

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

## Other Ways to Contribute

### Report real-world issues

If Claude gets something wrong while you're using the Stata skill in your own work, open an issue describing what happened. The most useful reports include: what you asked, what Claude got wrong, and which reference file was (or should have been) involved. Don't include your actual data or project details — describe the issue in the abstract. See `plugins/stata/skills/stata/references/filing-issues.md` for a template.

### Suggest new tests

The best test ideas come from real-world usage. If you hit a case where Claude struggled — wrong command, missing gotcha, bad option — turn it into a test task. Write a `tests/tasks/task_NN_description.md` following the existing format and open a PR. You don't need to fix the documentation yourself; a good test case that exposes the gap is valuable on its own. It goes into the eval pipeline and gives us a measurable target.

### Improve existing docs

Found an error or want to add a missing option? PRs for existing files are welcome. Keep changes focused and explain what you're fixing. If you can, run the eval pipeline before and after to show the improvement.

### Tackle a roadmap item

See [`ROADMAP.md`](ROADMAP.md) for bigger-picture directions — things like building a real-world test suite, restructuring reference files, or adding dynamic help file access. These are open problems, not specifications. If any of them interest you, open an issue to discuss your approach before starting work.

## Questions?

Open an issue if you're unsure about anything.
