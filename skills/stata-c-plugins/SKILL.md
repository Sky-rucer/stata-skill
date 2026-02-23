---
name: stata-c-plugins
description: >-
  Develop high-performance C/C++ plugins for Stata using the stplugin.h SDK.
  Use when the user asks to create a Stata plugin, write C/C++ code for Stata,
  accelerate a Stata command with C, build cross-platform Stata plugins,
  or translate/port a Python or R package into Stata. Covers the full
  lifecycle: SDK setup, data flow, memory safety, .ado wrappers with
  preserve/merge, cross-platform compilation, performance optimization
  (pthreads, pre-sorted indices, XorShift RNG), debugging, and distribution
  via net install. Also includes a translation workflow for porting Python/R
  packages to Stata — wrapping existing C++ backends when available, or
  writing C from scratch when not.
---

# Stata C/C++ Plugin Development

Build high-performance C/C++ plugins for Stata. This skill covers the full lifecycle from SDK setup through cross-platform distribution, based on real experience building production plugins (QRF, KNN, Neural Network) for the microimpute_stata project.

## When to Use

- User asks to write a C plugin for Stata
- User wants to accelerate a slow Stata command with C
- User asks about `stplugin.h`, `stata_call()`, or `SF_vdata()`/`SF_vstore()`
- User needs to compile Stata plugins for multiple platforms
- User is building a distributable Stata package with compiled code
- User asks to "translate", "port", or "reimplement" a Python/R package in Stata (see `references/translation_workflow.md`)
- User wants to wrap an existing C++ library as a Stata plugin (see `references/cpp_plugins.md`)

## When NOT to Use

- **Pure Stata is fine** for operations that use native commands (`regress`, `qreg`, `matrix`). No plugin needed if Stata already has a command that does what you want.
- **Plugins are warranted** when you need Python/C-equivalent speed: tree structures, neural nets, custom distance computations, anything with nested loops over observations. If performance matters, go straight to C/C++ — Mata is significantly slower for compute-heavy work.
- **When translating a package that has a C++ backend** (many R packages do — check their `src/` directory), **wrap the existing C++ code** rather than reimplementing in C. This gives near-identical output, same performance, and less code to maintain. See `references/translation_workflow.md`.

## The Plugin SDK

Download `stplugin.h` and `stplugin.c` from: https://www.stata.com/plugins/

These two files define the interface between your C code and Stata:

| Function/Macro | Purpose |
|---------------|---------|
| `SF_vdata(var, obs, &val)` | Read variable value (1-indexed!) |
| `SF_vstore(var, obs, val)` | Write variable value (1-indexed!) |
| `SF_nobs()` | Number of observations in current dataset |
| `SF_nvar()` | Number of variables passed to plugin |
| `SF_is_missing(val)` | Check for Stata missing value (`.`) |
| `SV_missval` | The missing value constant |
| `SF_display(msg)` | Print informational text in Stata |
| `SF_error(msg)` | Print red error text in Stata |

**Indexing is 1-based.** Both variable indices and observation indices start at 1, not 0. Off-by-one errors here are silent and catastrophic — you read the wrong variable's data with no warning.

## Memory Safety

**A crash in your plugin kills the entire Stata session.** No save prompt, no recovery. The user loses all unsaved work. This is the single most important thing to internalize.

- Check every `malloc()`/`calloc()` return for `NULL`
- Validate `argc` before accessing `argv[]`
- Build with `-fsanitize=address` during development
- Test on small data first, scale up gradually
- Pre-allocate all memory upfront in `stata_call()`, free at the end

## The stata_call() Entry Point

Every plugin implements one function. **Plugins can also be written in C++** — the entry point just needs `extern "C"` linkage so Stata can find it; everything else can be full C++. The obvious case for C++ is when existing C++ code is available to wrap (e.g., an R package's `src/` directory). C++ also helps when you need complex data structures or threading via `std::thread`. For practical C++ guidance — the `extern "C"` pattern, exception safety, compilation commands, wrapping libraries — see `references/cpp_plugins.md`. The rest of this file focuses on C because it's the simpler default.

```c
#include "stplugin.h"

// For C++ plugins, wrap the entry point with extern "C":
//   extern "C" {
//     STDLL stata_call(int argc, char *argv[]) { ... }
//   }

STDLL stata_call(int argc, char *argv[]) {
    // 0. Validate arguments BEFORE accessing argv[]
    if (argc < 3) {
        SF_error("myplugin requires 3 arguments: n_train n_test seed\n");
        return 198;  // Stata's "syntax error" code
    }

    // 1. Parse arguments (all strings — use atoi/atof)
    int n_train = atoi(argv[0]);
    int n_test  = atoi(argv[1]);
    int seed    = atoi(argv[2]);

    // 2. Get dimensions
    ST_int nobs  = SF_nobs();
    ST_int nvars = SF_nvar();  // includes output variable
    int p = nvars - 2;         // subtract depvar + output var

    // 3. Allocate memory
    double *X    = calloc(nobs * p, sizeof(double));
    double *y    = calloc(nobs, sizeof(double));
    double *pred = calloc(nobs, sizeof(double));
    if (!X || !y || !pred) {
        SF_error("myplugin: out of memory\n");
        if (X) free(X); if (y) free(y); if (pred) free(pred);
        return 909;
    }

    // 4. Read data from Stata (1-indexed!)
    ST_double val;
    for (ST_int obs = 1; obs <= nobs; obs++) {
        SF_vdata(1, obs, &val);      // var 1 = depvar
        y[obs-1] = val;
        for (int j = 0; j < p; j++) {
            SF_vdata(j + 2, obs, &val);  // vars 2..nvars-1 = features
            X[(obs-1) * p + j] = val;
        }
    }

    // 5. Run your algorithm
    int rc = my_algorithm(X, y, pred, n_train, n_test, p, seed);
    if (rc != 0) {
        SF_error("myplugin: algorithm failed\n");
        free(X); free(y); free(pred);
        return 909;
    }

    // 6. Write results back to Stata
    for (ST_int obs = 1; obs <= nobs; obs++) {
        SF_vstore(nvars, obs, pred[obs-1]);  // last var = output
    }

    free(X); free(y); free(pred);
    return 0;  // 0 = success
}
```

### Return Codes

- `0` — success
- `198` — syntax error (bad arguments)
- `909` — insufficient memory
- `601` — file not found
- Any non-zero triggers a Stata error

## The .ado Wrapper Pattern

Users never call `plugin call` directly. An `.ado` file provides the Stata-native interface.

### The Preserve/Merge Pattern

This is the core pattern for plugins that operate on a subset of data:

```stata
program define mycommand, rclass
    syntax varlist(min=2) [if] [in], GENerate(name) [SEED(integer 12345) REPlace]

    gettoken depvar indepvars : varlist

    if "`replace'" != "" {
        capture drop `generate'
    }
    confirm new variable `generate'

    // Mark sample: novarlist ALLOWS missing depvar (critical for imputation)
    marksample touse, novarlist
    markout `touse' `indepvars'   // but DO exclude missing predictors

    // Stable merge key — create BEFORE any sorting or subsetting
    tempvar merge_id
    quietly gen long `merge_id' = _n

    // Count subsets
    quietly count if `touse' & !missing(`depvar')
    local n_train = r(N)
    quietly count if `touse' & missing(`depvar')
    local n_test = r(N)

    // Create output variable (all missing initially)
    quietly gen double `generate' = .

    // Preserve, subset, call plugin
    preserve
    quietly keep if `touse'

    // Sort if plugin requires it (donors first, test second)
    tempvar sort_order
    quietly gen `sort_order' = missing(`depvar')
    quietly sort `sort_order'

    // Call plugin
    plugin call myplugin `depvar' `indepvars' `generate', ///
        `n_train' `n_test' `seed'

    // Save results and restore
    tempfile results
    quietly keep `merge_id' `generate'
    quietly save `results'
    restore

    // Merge predictions back (update replaces missing with non-missing)
    quietly merge 1:1 `merge_id' using `results', nogenerate update
end
```

**Why `update` works:** The `generate` variable is all-missing before preserve. After restore, it's still all-missing. The `update` option replaces missing values with non-missing ones from the merge file. The `replace` option is handled earlier via `capture drop`, so by merge time the variable is always freshly created.

### Plugin Sorting Contract

**CRITICAL:** Some plugins expect data sorted a specific way (training rows first, test rows second). Others handle missing data internally. A sorting mismatch was the most destructive bug in the microimpute project — QRF correlation dropped from 0.99 to 0.38.

- If the plugin checks `SF_is_missing()` internally: do NOT sort in the .ado wrapper
- If the plugin expects `n_train` contiguous rows then `n_test` rows: sort by `missing(depvar)` before calling

Document which pattern your plugin uses.

### Plugin Loading (Cross-Platform)

The cascade pattern (used by gtools and other major packages):
```stata
capture program myplugin, plugin using("myplugin.darwin-arm64.plugin")
if _rc {
    capture program myplugin, plugin using("myplugin.darwin-x86_64.plugin")
    if _rc {
        capture program myplugin, plugin using("myplugin.linux-x86_64.plugin")
        if _rc {
            capture program myplugin, plugin using("myplugin.windows-x86_64.plugin")
        }
    }
}
```

For slightly faster loading, check `c(os)` first to try the most likely platform. But the cascade is simpler and proven.

**Note:** `clear all` wipes loaded plugin definitions. If a test script starts with `clear all`, all `program ... plugin` definitions are gone. Reload them.

## Cross-Platform Compilation

Build for four platforms:

| Platform | Compiler | `-D` flag | Link flag | pthreads |
|----------|----------|-----------|-----------|----------|
| darwin-arm64 | `gcc -arch arm64` | `-DSYSTEM=APPLEMAC` | `-bundle` | `-pthread` |
| darwin-x86_64 | `gcc -target x86_64-apple-macos10.12` | `-DSYSTEM=APPLEMAC` | `-bundle` | `-pthread` |
| linux-x86_64 | `gcc` | `-DSYSTEM=OPUNIX` | `-shared` | `-pthread` |
| windows-x86_64 | `x86_64-w64-mingw32-gcc` | `-DSYSTEM=STWIN32` | `-shared` | `-lwinpthread` |

All platforms: `-O3 -fPIC` for release, add `-g -fsanitize=address` for development.

**For C++ plugins:** use `g++` instead of `gcc` (or add `-lstdc++` to linker flags). Add `-std=c++11` or later. Header-only C++ libraries like Eigen can be bundled by adding their include path with `-I`.

Naming convention: `pluginname.platform.plugin` (e.g., `qrf_plugin.darwin-arm64.plugin`).

macOS note: use `-bundle`, NOT `-shared`. This is a common mistake.

See `references/build_and_compile.md` for a full build script template.

## Performance Optimization

See `references/performance_patterns.md` for detailed code examples of:

1. **Pre-sorted feature indices** — Sort feature values once, scan linearly at each tree node. O(n) per split instead of O(n log n).
2. **Precomputed distance norms** — Exploit ||a-b||^2 = ||a||^2 + ||b||^2 - 2*a'b for KNN.
3. **Quickselect** — O(n) partial sort for finding k-th nearest neighbor.
4. **Parallel ensemble training (pthreads)** — Train multiple models concurrently. Each thread gets its own data copy and RNG state. **Never call Stata SDK functions (`SF_vdata`, `SF_vstore`, `SF_display`) from worker threads** — read all data on the main thread first, dispatch computation to workers, write results back on the main thread after joining.
5. **XorShift RNG** — C plugins cannot access Stata's internal RNG (`runiform()`). XorShift128+ is fast, statistically sound, and thread-safe (each thread gets its own state). Seed from `argv[]` for reproducibility.
6. **Dense arrays for trees** — Flat node arrays instead of linked lists for cache locality.

## Debugging

Debugging is hard because you can't attach a debugger to Stata's plugin host.

### Strategies

1. **Printf via SF_display():**
   ```c
   char buf[256];
   snprintf(buf, sizeof(buf), "Debug: n=%d, p=%d\n", n, p);
   SF_display(buf);
   ```

2. **Write diagnostic files:**
   ```c
   FILE *f = fopen("plugin_debug.log", "w");
   fprintf(f, "value at [%d][%d] = %f\n", i, j, val);
   fclose(f);
   ```

3. **Test standalone first.** Write a `main()` that reads CSV and calls your algorithm. Debug with normal tools (gdb, valgrind, sanitizers). Then adapt for the plugin interface.

4. **Build with sanitizers during development:** `-g -fsanitize=address`

5. **Check SF_vdata() return values.** It returns `RC` (0=success). Non-zero means invalid obs/var index.

### Common Failure Modes

| Symptom | Likely Cause |
|---------|-------------|
| Stata crashes silently | Segfault: buffer overflow, bad argv access, NULL deref |
| Plugin returns all missing | Wrong variable count, wrong obs indexing, plugin not loaded |
| Results are garbage | Sorting mismatch, 0-vs-1 indexing error, unnormalized inputs |
| "plugin not found" | Wrong filename, `clear all` wiped definition, wrong platform |
| Works on Mac, fails on Linux | Integer size difference, use `int32_t`/`int64_t` from `<stdint.h>` |

## Packaging and Distribution

A distributable Stata package with plugins needs:

```
mypackage/
├── stata.toc              # net install table of contents
├── mypackage.pkg          # lists all files to install
├── mypackage.ado          # user-facing command (.ado wrapper)
├── mypackage.sthlp        # help file (SMCL format)
├── myplugin.darwin-arm64.plugin
├── myplugin.darwin-x86_64.plugin
├── myplugin.linux-x86_64.plugin
├── myplugin.windows-x86_64.plugin
└── c_source/              # NOT distributed, for building
    ├── build.py
    ├── stplugin.c
    ├── stplugin.h
    └── algorithm.c
```

Users install with:
```stata
net install mypackage, from("https://raw.githubusercontent.com/user/repo/main") replace
```

See `references/packaging_and_help.md` for `.toc`, `.pkg`, `.sthlp` templates and SMCL formatting.

## Common Pitfalls

1. **Sorting destroys merge keys.** If you sort inside `preserve`/`restore`, the merge_id linkage breaks. Always create merge_id BEFORE preserve.

2. **1-indexed everything.** `SF_vdata(var, obs, &val)` — both var and obs start at 1. Off-by-one errors are silent.

3. **`marksample` excludes missing by default.** For imputation (where missing depvar IS the point), use `marksample touse, novarlist`.

4. **macOS reports as "Unix" in `c(os)`.** Platform detection needs: `if "`c(os)'" == "MacOSX" | "`c(os)'" == "Unix"`.

5. **argv[] has no bounds checking.** Accessing `argv[3]` when `argc == 2` is a segfault. Always check `argc` first.

6. **`clear all` wipes plugins.** Reload plugin definitions after `clear all` in test scripts.

7. **Only the first `program define` in a .ado file is auto-discovered.** Subprograms need their own .ado files or explicit `run` to load.

8. **Normalize inputs for neural net plugins.** Scale to mean=0, sd=1 in the .ado wrapper, denormalize predictions after. The plugin shouldn't handle this.

9. **pthreads on Windows needs `-lwinpthread`.** Use conditional linker flags.

10. **Memory errors crash Stata with no recovery.** Pre-allocate everything, check every allocation, build with sanitizers during development.

## Naming Conventions

- Use `method()` not `model()` for method selection options
- Use `generate()` (abbreviation `gen()`) for output variable naming
- Use `replace` as a flag option, not `replace()`
- Plugin files: `algorithm_plugin.platform.plugin`
- .ado files: lowercase, underscores for multi-word
- Stata option convention: options lowercase, abbreviations capitalized (`GENerate`, `MAXDepth`)
- Target Stata 14.0+ (`version 14.0`) for plugin support
