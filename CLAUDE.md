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

## Example Applications

- **[stata-rapidfuzz](https://github.com/dylantmoore/stata-rapidfuzz)** — String similarity and fuzzy matching. Wraps the rapidfuzz-cpp header-only C++ library. Demonstrates the C++ wrapping workflow: vendoring headers, thin `extern "C"` glue, cross-platform static linking.
- **[drf_stata](https://github.com/dylantmoore/drf_stata)** — Distributional Random Forests for Stata. Wraps the R `drf` package's C++ backend (lorismichel/drf). Demonstrates C++ wrapping with pthreads parallelism, XorShift RNG, and correlation-based validation against R.
- **[microimpute_stata](https://github.com/dylantmoore/microimpute_stata)** — High-performance statistical imputation with C plugin acceleration. Multi-method package (QRF, KNN, Neural Network) demonstrating the full plugin lifecycle: dispatcher .ado, multiple C plugins, preserve/merge pattern, cross-platform builds.
- **[ranger_stata](https://github.com/dylantmoore/ranger_stata)** — Random forests for Stata (regression, classification, probability, survival). Wraps the ranger C++ library via `initR()` API. Demonstrates 4-forest-type dispatching, save/load for prediction on new data, and extensive option passthrough (case weights, class weights, regularization, split rules).
- **[grf_stata](https://github.com/dylantmoore/grf_stata)** — Generalized Random Forests for Stata (Athey, Tibshirani, Wager). Wraps the grf C++ backend (grf-labs/grf, v2.5.0). 12 forest types (causal, instrumental, quantile, survival, etc.), 7 post-estimation commands (ATE, BLP, RATE, tuning), 335+ test cases. Demonstrates large-scale C++ wrapping with nuisance estimation pipelines, cross-validation tuning in .ado, and comprehensive option-level test coverage.

## Conventions

- SKILL.md files must stay under 500 lines (hard limit for skills)
- Descriptions in YAML frontmatter must stay under 1024 characters
- No Mata content in the C plugins skill — if performance matters, go straight to C
- Reference files are pulled in on demand, so put detailed content there, not in SKILL.md
- The `stata` skill covers Mata adequately for anyone who actually wants it
