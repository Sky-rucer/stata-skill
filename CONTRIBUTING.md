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

5. **Add a test task** in `tests/tasks/` that exercises the package. Follow the format of existing tasks (see `tests/README.md`). Your task should:
   - Ask Claude to solve a realistic problem using the package
   - Exercise the key options and workflows you documented
   - Cover at least one gotcha if applicable

   Run the test through the pipeline to verify it passes:
   ```bash
   ./tests/scripts/run_pipeline.sh tests/tasks/your_task.md
   ```

6. **Open a pull request** with a brief description of the package and why it's useful.

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
