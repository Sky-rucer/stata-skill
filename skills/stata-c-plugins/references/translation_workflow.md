# Translating Python/R Packages into Stata

A complete workflow for porting a Python or R statistical package into a native Stata implementation with C plugin acceleration. Based on lessons learned from translating PolicyEngine's `microimpute` Python package into `microimpute_stata`.

## Phase 1: Scope and Understand the Source

Before writing any code, thoroughly understand the source package.

1. **Read the source package structure.** Identify all public-facing functions, their signatures, inputs, outputs, and options. Map Python classes/functions to what will become Stata commands.

2. **Identify the computational core.** Separate the algorithm (what computes) from the interface (how users call it). In Python, the algorithm is usually in model classes; in Stata, it will be in C plugins.

3. **Check the source license.** The translated package inherits licensing obligations. MIT and BSD allow any re-use. GPL requires the Stata package to also be GPL. If the source is proprietary or has no license, get permission before translating.

4. **Decide what to translate.** Not everything needs to come over. Prioritize:
   - Core algorithms that users actually need
   - Features that are tractable to implement in Stata/C
   - Skip: visualization, I/O utilities, Python-specific abstractions

5. **Create `requirements.txt` for reference generation.** Pin the exact versions of the original package and its dependencies so reference test data can be reproduced:
   ```
   numpy==1.26.4
   pandas==2.2.0
   scikit-learn==1.4.0
   original-package==1.2.3
   ```

6. **Map source concepts to Stata equivalents:**

   | Python/R Concept | Stata Equivalent |
   |-----------------|-----------------|
   | Function/method with args | `.ado` command with `syntax` options |
   | Class with fit/predict | C plugin called from `.ado` wrapper |
   | DataFrame I/O | Stata variables accessed via `SF_vdata()`/`SF_vstore()` |
   | Return values | `r()` stored results, new variables via `generate()` |
   | Optional parameters | Stata `syntax` options with defaults |
   | Configuration object | Local macros in `.ado` file |

## Phase 2: Choose Architecture

Three tiers of implementation. Choose based on performance needs.

### Tier 1: Pure Stata (ado-files only)
- **When:** Simple operations, linear algebra Stata already does well (OLS, quantile regression)
- **How:** Use native Stata commands (`regress`, `qreg`, `matrix`) inside `.ado` wrappers
- **Performance:** Limited. Loops over observations are extremely slow.

### Tier 2: C Plugins (recommended for anything compute-heavy)
- **When:** Anything beyond what native Stata commands handle — tree algorithms, neural nets, custom distance computations, anything with nested loops
- **How:** Write C code using Stata's plugin SDK (see main SKILL.md)
- **Skip Mata.** It's 10-50x slower than C, nobody understands the syntax, and you'll end up rewriting in C anyway. Go straight to C.

**Recommendation:** `.ado` for user interface + C plugin for compute + native Stata commands for trivial methods (OLS, quantile regression).

## Phase 3: Package Structure

```
packagename/
├── stata.toc              # net install table of contents
├── packagename.pkg        # Package manifest
├── packagename.ado        # Main command (dispatcher)
├── packagename_sub.ado    # Method-specific wrapper (one per method)
├── packagename.sthlp      # Help file (SMCL format)
├── *.plugin               # Precompiled C plugins (4 platforms each)
├── c_plugin/              # C source (not distributed)
└── tests/
    ├── generate_test_data.py  # Reference outputs from source package
    ├── run_tests.do           # Correctness tests
    └── test_features.do       # Feature verification
```

**One main command, multiple methods** using a dispatcher pattern. Each method also callable directly for advanced users.

**Subprograms in the same .ado file** are NOT auto-discoverable. Only the first `program define` matching the filename is auto-found. Prefer separate .ado files.

## Phase 4: Testing Against the Reference

The most critical translation-specific phase. See `testing_strategy.md` for detailed templates.

### Reference Data Generation (Python)

Write `tests/generate_test_data.py` that generates synthetic data with known signal, runs the ORIGINAL package, and saves inputs + outputs as CSV.

### Correlation Thresholds

| Algorithm Type | Stata vs Python | Rationale |
|----------------|-----------------|-----------|
| Deterministic (KNN) | r > 0.99 (ideally 1.0) | Should match exactly |
| Stochastic, same algorithm (QRF) | r > 0.95 | Random splits differ |
| Stochastic, different impl (NN) | r > 0.90 | Training path diverges |

**Also check correlation with GROUND TRUTH**, not just with Python.

### Integration and Stress Tests

- Test every feature end-to-end (missing data, each method, `if`/`in`, `replace`, edge cases)
- Stress: high dimensions, large n, correlated features, near-singular data

### Debugging Test Failures

| Symptom | Likely Cause |
|---------|-------------|
| Low correlation | Sorting mismatch, missing data handling, merge key corruption |
| All missing output | Wrong variable count, plugin not loaded, zero obs after `keep if` |
| Platform differences | Integer sizes (`int` vs `int32_t`), thread scheduling |

## Phase 5: Documentation

Be honest about what works, what has limitations, and how it was built. Don't claim features that are silently ignored — in microimpute, the README falsely claimed mahalanobis distance and hotdeck support. Only document what actually works.

## Translation-Specific Pitfalls

1. **Don't translate the interface literally.** Python OOP maps poorly to Stata. Use Stata idioms.
2. **Silently ignored options erode trust.** Either implement or reject with an error.
3. **Pin your reference package version.** Use `requirements.txt`.
4. **Get correctness right first, optimize second.**
5. **Stata's `.` differs from Python's NaN.** `.` sorts to the top and compares as larger than all numbers.
6. **Be transparent about AI-assisted development.**

## Workflow Summary

```
1. Read and understand source package
2. Check license compatibility
3. Map functions → Stata commands, identify compute-heavy algorithms
4. Decide: pure Stata or C plugin for each algorithm
5. Scaffold: .ado dispatcher, method wrappers, .sthlp, .pkg, .toc
6. Implement C plugins (see main SKILL.md)
7. Write Python reference data generator with pinned dependencies
8. Write Stata test suite comparing to Python output
9. Debug until correlation thresholds are met
10. Write honest README, package, distribute via net install
```
