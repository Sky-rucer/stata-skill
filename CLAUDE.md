# stata-skill

Claude Code plugin containing two skills for Stata development.

## Skills

### 1. `stata` (skills/stata/)
General Stata reference — syntax, data management, econometrics, causal inference, graphics, and 20+ community packages. Uses progressive disclosure: a routing table in SKILL.md directs to 57 reference files loaded on demand.

### 2. `stata-c-plugins` (skills/stata-c-plugins/)
C plugin development for Stata — SDK setup, memory safety, .ado wrappers, cross-platform compilation, performance optimization, debugging, and packaging. Includes a translation workflow for porting Python/R packages into Stata with C plugin acceleration.

Reference files are loaded on demand:
- `performance_patterns.md` — pthreads, XorShift RNG, quickselect, pre-sorted indices
- `packaging_and_help.md` — .toc/.pkg/.sthlp templates, build scripts
- `translation_workflow.md` — scoping source packages, architecture decisions, correlation-based testing
- `testing_strategy.md` — reference data generation, correctness/integration/stress tests
- `cpp_plugins.md` — when to use C++ over C, extern "C" pattern, exception safety, compilation, wrapping libraries

## Repo Structure

```
.claude-plugin/
├── marketplace.json     # Registers both skills
└── plugin.json          # Plugin metadata
skills/
├── stata/               # General Stata reference
│   ├── SKILL.md
│   ├── references/      # 37 topic files
│   └── packages/        # 20 community package guides
└── stata-c-plugins/     # C plugin development
    ├── SKILL.md
    └── references/      # 5 reference files
```

## Conventions

- SKILL.md files must stay under 500 lines (hard limit for skills)
- Descriptions in YAML frontmatter must stay under 1024 characters
- No Mata content in the C plugins skill — if performance matters, go straight to C
- Reference files are pulled in on demand, so put detailed content there, not in SKILL.md
- The `stata` skill covers Mata adequately for anyone who actually wants it
