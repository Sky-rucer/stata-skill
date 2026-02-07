# Stata Skill for Claude Code

A Claude Code plugin that helps Claude write correct, idiomatic Stata code. Covers core Stata syntax, data management, econometrics, causal inference, graphics, Mata programming, and 17+ community packages.

## What's Included

**37 core reference files** covering:
- Data import/export, management, and cleaning
- Linear regression, panel data, time series
- Limited dependent variables, survival analysis, SEM
- Causal inference: DiD, RD, matching, treatment effects
- Mata programming and matrix operations
- Graphics, tables, and reporting
- Workflow best practices

**20 community package guides** including:
- `reghdfe` — high-dimensional fixed effects
- `estout` / `outreg2` — publication-quality tables
- `csdid`, `did_multiplegt` — modern DiD estimators
- `rdrobust` — regression discontinuity
- `psmatch2` — propensity score matching
- `synth` — synthetic control
- `ivreg2` / `xtabond2` — IV and dynamic panel GMM
- And more (binsreg, coefplot, grstyle, winsor2, gtools, ...)

## Installation

In Claude Code, run:

```
/plugin marketplace add dylantmoore/stata-skill
/plugin install stata@dylantmoore-stata-skill
```

## How It Works

The skill uses **progressive disclosure**: a compact routing table (~370 lines) loaded on activation directs Claude to read only the 1-3 reference files relevant to the current task. This keeps context usage efficient while giving Claude access to 57 detailed reference documents when needed.

## Coverage

| Category | Files | Topics |
|----------|-------|--------|
| Data Operations | 7 | Import, management, strings, dates, math functions |
| Statistics | 10 | Regression, panel, time series, MLE, GMM, survey, MI |
| Causal Inference | 5 | DiD, RD, matching, treatment effects, selection |
| Advanced Methods | 5 | Survival, SEM, nonparametric, spatial, ML/lasso |
| Programming | 6 | Do-files, macros, loops, Mata |
| Output & Workflow | 3 | Tables, reporting, best practices, external tools |
| Packages | 20 | Community-contributed packages |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add documentation for new Stata packages. Pull requests welcome!

## Disclaimer

This reference material is derived in part from Stata's official documentation and community package documentation. No copyright is claimed. Stata is a registered trademark of StataCorp LLC. This project is not affiliated with or endorsed by StataCorp.
