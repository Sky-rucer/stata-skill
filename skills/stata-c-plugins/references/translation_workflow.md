# Translating Python/R Packages into Stata

A complete workflow for porting a Python or R statistical package into a native Stata implementation with C plugin acceleration.

## Phase 1: Scope and Understand the Source

Before writing any code, thoroughly understand the source package.

1. **Check for a C/C++ backend first.** Many R packages (and some Python packages) have compiled backends. In R, check the `src/` directory for `.c`, `.cpp`, or `.h` files. In Python, look for Cython (`.pyx`), C extensions, or `cffi`/`ctypes` bindings. **If a C/C++ backend exists, the recommended approach is to wrap that code directly in a Stata plugin** rather than reimplementing the algorithm from scratch. This gives you identical output (same code, not a reimplementation), the same performance, far less code to write, and easier maintenance when the upstream package is updated. See "Wrapping an Existing C++ Backend" below.

2. **Read the source package structure.** Identify all public-facing functions, their signatures, inputs, outputs, and options. Map Python classes/functions to what will become Stata commands.

3. **Identify the computational core.** Separate the algorithm (what computes) from the interface (how users call it). In Python, the algorithm is usually in model classes; in Stata, it will be in C plugins (or wrapped C++ code).

4. **Check the source license.** The translated package inherits licensing obligations. MIT and BSD allow any re-use. GPL requires the Stata package to also be GPL. If the source is proprietary or has no license, get permission before translating.

5. **Decide what to translate.** Not everything needs to come over. Prioritize:
   - Core algorithms that users actually need
   - Features that are tractable to implement in Stata/C
   - Skip: visualization, I/O utilities, Python-specific abstractions

6. **Pin the source package version.** Create `requirements.txt` (Python) or record the exact package version (R) so reference test data can be reproduced later. If the source changes, your tests become meaningless.

7. **Map source concepts to Stata equivalents:**

   | Python/R Concept | Stata Equivalent |
   |-----------------|-----------------|
   | Function/method with args | `.ado` command with `syntax` options |
   | Class with fit/predict | C plugin called from `.ado` wrapper |
   | DataFrame I/O | Stata variables accessed via `SF_vdata()`/`SF_vstore()` |
   | Return values | `r()` stored results, new variables via `generate()` |
   | Optional parameters | Stata `syntax` options with defaults |
   | Configuration object | Local macros in `.ado` file |

## Phase 2: Choose Architecture

Three tiers of implementation. Choose based on what the source package provides and your performance needs.

### Tier 1: Pure Stata (ado-files only)
- **When:** Simple operations, linear algebra Stata already does well (OLS, quantile regression)
- **How:** Use native Stata commands (`regress`, `qreg`, `matrix`) inside `.ado` wrappers
- **Performance:** Limited. Loops over observations are extremely slow.

### Tier 2: Wrap Existing C++ Backend (preferred when available)
- **When:** The source package has a C/C++ backend (many R packages do — check `src/` for `.cpp` files). Examples: grf, ranger, Rcpp-based packages, anything using Eigen/Armadillo.
- **How:** Compile the existing C++ source into a Stata plugin. Write a thin `extern "C"` wrapper around the library's API. The plugin internals are C++ — only the `stata_call` entry point needs C linkage. See `references/cpp_plugins.md` for the `extern "C"` pattern, exception safety, and compilation commands.
- **Why this is better than reimplementing:** Near-identical output (same core code path as the original — minor differences from compiler flags or RNG seeding are possible), same performance, far less code to write, and easier to update when the upstream package changes. You only write the glue between Stata's SDK and the library's API.

### Tier 3: Plugin from Scratch (when no compiled backend exists)
- **When:** The source is pure Python/R with no compiled backend, or the algorithm is simple enough that a clean implementation is straightforward.
- **How:** Write C or C++ code using Stata's plugin SDK. C is the simpler choice for straightforward numerical algorithms (arrays, loops, basic math). C++ is worth considering when the algorithm needs complex data structures, threading, or would benefit from `std::vector`/RAII for safety. See main SKILL.md for C patterns, `references/cpp_plugins.md` for C++.
- **Mata is not recommended** for compute-heavy algorithms — it's significantly slower than C/C++ and adds a layer of complexity without meaningful benefit for plugin-class workloads.

**Recommendation:** `.ado` for user interface + wrapped C++ or from-scratch C plugin for compute + native Stata commands for trivial methods (OLS, quantile regression). Always check for an existing C++ backend before writing from scratch.

## Wrapping an Existing C++ Backend

When the source package has a C/C++ backend, this is the recommended approach. You compile the original C++ code into a Stata plugin rather than reimplementing the algorithm. For full practical details on C++ plugins (exception safety, platform-specific build commands, the `extern "C"` pattern, and standard library usage), see `references/cpp_plugins.md`. This section covers the translation-specific workflow.

### Identifying a C++ Backend

- **R packages:** Check the `src/` directory in the package source (e.g., on GitHub or CRAN). Look for `.cpp`, `.c`, `.h` files. Many high-performance R packages use Rcpp and have their core algorithms in C++.
- **Python packages:** Look for Cython (`.pyx`), C extensions (`_module.c`), or `cffi`/`ctypes` bindings. Some packages vendor C/C++ libraries.
- **Header-only libraries:** Libraries like Eigen (linear algebra) are header-only — you just add `-I/path/to/eigen` at compile time. No separate linking needed.

### The Basic Pattern

```cpp
// stata_wrapper.cpp — thin glue between Stata SDK and the C++ library

#include "stplugin.h"
#include "library_header.h"  // the existing C++ library

extern "C" {
    STDLL stata_call(int argc, char *argv[]) {
        // 1. Parse arguments from argv[]
        // 2. Read data from Stata via SF_vdata()
        // 3. Call the C++ library's API
        // 4. Write results back via SF_vstore()
        // 5. Return 0 on success
    }
}
```

The `extern "C"` block gives `stata_call` C linkage so Stata can load it. Everything inside (and all code it calls) can be full C++: templates, classes, STL containers, Eigen matrices, etc.

### Compilation Differences from Pure C

See `references/cpp_plugins.md` for full platform-specific build commands (darwin-arm64, darwin-x86_64, linux, windows cross-compilation).

| Aspect | C Plugin | C++ Plugin |
|--------|----------|------------|
| Compiler | `gcc` | `g++` (or `gcc -lstdc++`) |
| Standard | `-std=c99` | `-std=c++11` or later |
| Entry point | `stata_call()` | `extern "C" { stata_call() }` |
| SDK files | `stplugin.c` compiled as C | `stplugin.c` compiled as C (keep separate, compile with `gcc`) |
| Header-only libs | N/A | `-I/path/to/headers` |

**Important:** Compile `stplugin.c` as C (with `gcc`), not C++. Then link the resulting object with your C++ code. This avoids name-mangling issues with the SDK symbols:

```bash
gcc -c -O3 -fPIC -DSYSTEM=APPLEMAC stplugin.c -o stplugin.o
g++ -c -O3 -fPIC -std=c++17 -DSYSTEM=APPLEMAC -I./library_headers stata_wrapper.cpp -o wrapper.o
g++ -bundle -o myplugin.darwin-arm64.plugin stplugin.o wrapper.o
```

### When to Wrap vs. Reimplement

| Scenario | Approach |
|----------|----------|
| Source has optimized C++ backend (e.g., grf, ranger) | **Wrap** — identical output, same speed, less code |
| Simple algorithm (KNN, basic trees) | Either works — C from scratch may be cleaner |
| No C/C++ backend exists (pure Python/R) | **Reimplement** in C or C++ |
| C++ backend has massive dependency tree | Evaluate case by case — may need selective extraction |
| Header-only C++ library (Eigen, nlohmann/json) | **Wrap** — just add `-I` include path, no linking needed |

### Advantages of Wrapping

1. **Near-identical output** — same code path as the original package, not a reimplementation that might diverge. Minor differences can arise from compiler flags, RNG seeding, or threading nondeterminism, but the core algorithm is the same.
2. **Same performance** — you get the original authors' optimizations for free
3. **Less code to write** — you only write the Stata SDK glue, not the algorithm
4. **Easier maintenance** — when the upstream library fixes bugs or adds features, you pull the update and recompile
5. **Easier validation** — if the code is the same, output agreement is nearly guaranteed

## Phase 3: Package Structure

```
packagename/
├── stata.toc              # net install table of contents
├── packagename.pkg        # Package manifest
├── packagename.ado        # Main command (dispatcher)
├── packagename_sub.ado    # Method-specific wrapper (one per method)
├── packagename.sthlp      # Help file (SMCL format)
├── *.plugin               # Precompiled C plugins (4 platforms each)
├── c_plugin/              # C/C++ source (not distributed)
│   ├── lib/               # Vendored C++ library source (if wrapping)
└── tests/
    ├── generate_test_data.py  # Reference outputs from source package
    ├── run_tests.do           # Correctness tests
    └── test_features.do       # Feature verification
```

**One main command, multiple methods** using a dispatcher pattern. Each method also callable directly for advanced users.

**Subprograms in the same .ado file** are NOT auto-discoverable. Only the first `program define` matching the filename is auto-found. Prefer separate .ado files.

## Phase 4: Validating Against the Reference

The most critical translation-specific phase. See `testing_strategy.md` for detailed templates.

### Core Principle

For any given input, the Stata implementation should produce the same output as the source. The acceptable tolerance depends on the algorithm's nature:

| Algorithm Nature | Expected Agreement | Example |
|-----------------|-------------------|---------|
| Deterministic | Identical (within floating-point ε) | KNN, OLS, exact matching |
| Deterministic but numerically sensitive | Nearly identical (tiny deviations) | Matrix inversions, iterative solvers |
| Fundamentally stochastic | Substantively identical | Random forests, MCMC, neural nets |

"Substantively identical" means: applied to the same problem, both implementations should perform comparably. The right metric depends on what the command produces — correlation for predictions, relative error for scalar estimates, classification agreement for labels, distributional tests for density estimates, etc.

### Reference Data Generation

Write a script in the source language that:
1. Creates synthetic data with known properties
2. Runs the original package on it
3. Saves inputs and outputs as CSV for Stata to load

Pin the exact source package version so results are reproducible.

### What to Compare

Always compare against both the **source implementation** and **known ground truth** when possible. Matching the source perfectly is necessary but not sufficient — both implementations could be wrong in the same way.

### Integration and Stress Tests

- Test every feature end-to-end (`if`/`in`, `replace`, option combinations, edge cases)
- Stress: high dimensions, large n, correlated features, near-singular data, boundary conditions

### Debugging Test Failures

| Symptom | Likely Cause |
|---------|-------------|
| Output disagrees with source | Sorting mismatch, missing data handling, merge key corruption, 0-vs-1 indexing |
| All missing output | Wrong variable count, plugin not loaded, zero obs after `keep if` |
| Platform differences | Integer sizes (`int` vs `int32_t`), thread scheduling |

## Phase 5: Documentation

Be honest about what works, what has limitations, and how it was built. Don't claim features that are silently ignored. Only document what actually works.

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
2. Check for C/C++ backend (R: check src/, Python: check for Cython/C extensions)
3. Check license compatibility
4. Map functions → Stata commands, identify compute-heavy algorithms
5. Decide: wrap C++ backend, write C/C++ from scratch, or pure Stata for each algorithm
6. Scaffold: .ado dispatcher, method wrappers, .sthlp, .pkg, .toc
7. Implement plugins — wrap existing C++ (see references/cpp_plugins.md) or write C/C++ (see main SKILL.md and references/cpp_plugins.md)
8. Write reference data generator in source language with pinned dependencies
9. Write Stata test suite comparing outputs to source implementation
10. Debug until outputs agree (identical, nearly identical, or substantively identical depending on algorithm)
11. Write honest README, package, distribute via net install
```
