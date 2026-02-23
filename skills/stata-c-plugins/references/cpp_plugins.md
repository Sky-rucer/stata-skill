# C++ Plugins for Stata

Practical guidance for building Stata plugins in C++ instead of C. The main SKILL.md covers the C approach, which is the simpler default. This file covers the cases where C++ is the better choice and the specific patterns you need.

## When C++ Is the Right Choice

- **An existing C++ implementation exists.** This is the obvious case. If you're translating an R package that has a C++ backend in `src/`, wrap it rather than reimplementing in C. You get near-identical output (same core code path — minor differences from compiler flags or RNG seeding are possible), same performance, less code.
- **Complex data structures.** Trees, graphs, hash maps, priority queues — `std::map`, `std::unordered_map`, `std::priority_queue` are battle-tested. Writing your own in C is error-prone and slow to develop.
- **Threading with `std::thread`/`std::async`.** Simpler than raw pthreads for many use cases, especially when each thread needs its own state.
- **You want a C++ library.** Eigen for linear algebra, nlohmann/json for config parsing, etc. Header-only libraries are especially easy — just add `-I`.

## When C Is Still Fine

- Simple algorithms (a few hundred lines of logic)
- Just arrays and loops, no complex data structures needed
- No existing C++ code to leverage
- The from-scratch C approach in the main SKILL.md covers everything you need

Don't reach for C++ just because you can. C plugins are simpler to compile, produce smaller binaries, and have fewer cross-compilation issues.

## The `extern "C"` Pattern

Stata loads plugins by looking for a function named `stata_call` with C linkage. C++ name-mangles all functions by default, so Stata can't find them. The fix is `extern "C"`.

```cpp
// wrapper.cpp
#include "stplugin.h"
#include <vector>
#include <stdexcept>
#include "my_algorithm.h"  // your C++ code or vendored library

extern "C" {

STDLL stata_call(int argc, char *argv[]) {
    try {
        if (argc < 2) {
            SF_error("myplugin requires 2 arguments\n");
            return 198;
        }

        int n = atoi(argv[0]);
        int seed = atoi(argv[1]);
        ST_int nobs = SF_nobs();
        ST_int nvars = SF_nvar();

        // Use C++ containers instead of malloc
        std::vector<double> X(nobs * (nvars - 1));
        std::vector<double> results(nobs);

        // Read from Stata (1-indexed)
        ST_double val;
        for (ST_int obs = 1; obs <= nobs; obs++) {
            for (int j = 0; j < nvars - 1; j++) {
                SF_vdata(j + 1, obs, &val);
                X[(obs - 1) * (nvars - 1) + j] = val;
            }
        }

        // Call C++ library
        MyAlgorithm algo(n, seed);
        algo.fit(X.data(), nobs, nvars - 1);
        algo.predict(X.data(), results.data(), nobs);

        // Write back to Stata
        for (ST_int obs = 1; obs <= nobs; obs++) {
            SF_vstore(nvars, obs, results[obs - 1]);
        }

        return 0;

    } catch (const std::exception &e) {
        char buf[512];
        snprintf(buf, sizeof(buf), "myplugin error: %s\n", e.what());
        SF_error(buf);
        return 909;
    } catch (...) {
        SF_error("myplugin: unknown error\n");
        return 909;
    }
}

}  // extern "C"
```

Key points:
- Only `stata_call` needs `extern "C"`. All other functions can be normal C++.
- The `extern "C"` block can wrap just the one function, or you can use `extern "C" STDLL stata_call(...)` on the declaration directly.
- Everything inside `stata_call` can use C++ freely: templates, classes, STL, exceptions (as long as they're caught).

## Handling `stplugin.c`

`stplugin.c` is C code. You have two options:

**Option 1 (recommended): Compile separately.**
```bash
gcc -c -O3 -fPIC -DSYSTEM=APPLEMAC stplugin.c -o stplugin.o
g++ -O3 -std=c++14 -fPIC -DSYSTEM=APPLEMAC -bundle -o plugin.plugin wrapper.cpp stplugin.o
```

**Option 2: Include with `extern "C"` trick.**
```cpp
// At the top of wrapper.cpp, before any C++ headers
extern "C" {
#include "stplugin.c"
}
```

Option 1 is cleaner and avoids any issues with C constructs that aren't valid C++. Option 2 works but can break if `stplugin.c` uses anything C++-incompatible.

## Exception Safety

**Uncaught exceptions escaping `stata_call` crash Stata instantly.** No error message, no recovery, the user loses all unsaved work. This is the single most important rule for C++ plugins.

Always wrap the entire body of `stata_call` in try/catch:

```cpp
extern "C" {
STDLL stata_call(int argc, char *argv[]) {
    try {
        // ALL your code here
        return 0;
    } catch (const std::bad_alloc &e) {
        SF_error("myplugin: out of memory\n");
        return 909;
    } catch (const std::exception &e) {
        char buf[512];
        snprintf(buf, sizeof(buf), "myplugin: %s\n", e.what());
        SF_error(buf);
        return 909;
    } catch (...) {
        SF_error("myplugin: unknown internal error\n");
        return 909;
    }
}
}
```

Catch `std::bad_alloc` separately so you can return Stata's memory error code (909). Catch `std::exception` for anything with a message. Catch `...` as a last resort for non-standard exceptions.

## Compilation

Use `g++` instead of `gcc` for the C++ files. `stplugin.c` must be compiled as C.

### darwin-arm64 (Apple Silicon Mac)

```bash
gcc -c -O3 -fPIC -DSYSTEM=APPLEMAC -arch arm64 stplugin.c -o stplugin.o
g++ -O3 -std=c++14 -fPIC -DSYSTEM=APPLEMAC -arch arm64 -bundle \
    -o myplugin.darwin-arm64.plugin wrapper.cpp stplugin.o -lm
```

### darwin-x86_64 (Intel Mac)

```bash
gcc -c -O3 -fPIC -DSYSTEM=APPLEMAC -target x86_64-apple-macos10.12 stplugin.c -o stplugin.o
g++ -O3 -std=c++14 -fPIC -DSYSTEM=APPLEMAC -target x86_64-apple-macos10.12 -bundle \
    -o myplugin.darwin-x86_64.plugin wrapper.cpp stplugin.o -lm
```

### linux-x86_64

```bash
gcc -c -O3 -fPIC -DSYSTEM=OPUNIX stplugin.c -o stplugin.o
g++ -O3 -std=c++14 -fPIC -DSYSTEM=OPUNIX -shared \
    -o myplugin.linux-x86_64.plugin wrapper.cpp stplugin.o -lm
```

### windows-x86_64 (cross-compile from Mac/Linux)

```bash
x86_64-w64-mingw32-gcc -c -O3 -DSYSTEM=STWIN32 stplugin.c -o stplugin.o
x86_64-w64-mingw32-g++ -O3 -std=c++14 -DSYSTEM=STWIN32 -shared \
    -static-libstdc++ -static-libgcc \
    -o myplugin.windows-x86_64.plugin wrapper.cpp stplugin.o -lm
```

Note the Windows flags: `-static-libstdc++ -static-libgcc` statically links the C++ runtime so users don't need to install anything extra.

### With header-only libraries (e.g., Eigen)

Just add the include path:

```bash
g++ -O3 -std=c++14 -fPIC -DSYSTEM=APPLEMAC -arch arm64 -bundle \
    -I./eigen -o myplugin.darwin-arm64.plugin wrapper.cpp stplugin.o -lm
```

No linking step needed for header-only libraries.

## Shipping

No difference from C plugins. The output is a single `.plugin` binary per platform, same naming convention (`pluginname.platform.plugin`), same `.ado` wrapper, same `.pkg` distribution.

- Header-only C++ libraries (Eigen, etc.) are compiled into the binary. No runtime dependency.
- On Windows, use `-static-libstdc++ -static-libgcc` to avoid requiring C++ runtime DLLs.
- Users cannot tell whether a plugin was written in C or C++. The `.plugin` file is opaque.
- Same cascade loading pattern, same `net install` distribution.

## Wrapping an Existing C++ Library

This is the main use case for C++ plugins. You have existing C++ code (from an R package's `src/` directory, a standalone library, etc.) and want to call it from Stata.

### Finding C++ Backends

- **R packages:** Check `src/` on GitHub or in the CRAN source tarball. Many R packages use Rcpp and have their algorithms in `.cpp` files. Examples: `grf`, `ranger`, `xgboost`.
- **Python packages:** Look for Cython (`.pyx` files), C extensions, or vendored C/C++ code. Check `setup.py` or `pyproject.toml` for compiled extension definitions.
- **Standalone C++ libraries:** Some algorithms have reference implementations as standalone C++ projects.

### Steps

1. **Clone or vendor the source** into your project (e.g., `c_plugin/lib/`).
2. **Identify the library's API.** Find the main classes/functions: typically a constructor, a `fit()`/`train()` method, and a `predict()` method.
3. **Write a thin `stata_call` wrapper** that:
   - Reads data from Stata with `SF_vdata()`
   - Converts to whatever format the library expects (arrays, Eigen matrices, custom structs)
   - Calls the library's training/prediction functions
   - Writes results back with `SF_vstore()`
4. **The `.ado` wrapper handles all Stata syntax.** The C++ just does computation. Users interact with Stata syntax, not the plugin directly.

### Example: Wrapping a library that uses Eigen

```cpp
// wrapper.cpp
#include "stplugin.h"
#include <Eigen/Dense>
#include "library_api.h"

extern "C" {
STDLL stata_call(int argc, char *argv[]) {
    try {
        ST_int nobs = SF_nobs();
        int p = SF_nvar() - 1;  // last var is output

        // Read into Eigen matrix
        Eigen::MatrixXd X(nobs, p);
        ST_double val;
        for (ST_int i = 0; i < nobs; i++) {
            for (int j = 0; j < p; j++) {
                SF_vdata(j + 1, i + 1, &val);  // 1-indexed!
                X(i, j) = val;
            }
        }

        // Call library
        Eigen::VectorXd result = library_compute(X);

        // Write back
        int out_var = SF_nvar();
        for (ST_int i = 0; i < nobs; i++) {
            SF_vstore(out_var, i + 1, result(i));
        }

        return 0;
    } catch (const std::exception &e) {
        char buf[512];
        snprintf(buf, sizeof(buf), "plugin error: %s\n", e.what());
        SF_error(buf);
        return 909;
    } catch (...) {
        SF_error("plugin: unknown error\n");
        return 909;
    }
}
}
```

## Using C++ Standard Library Features

When writing a plugin from scratch in C++ (rather than wrapping a library), the standard library gives you safer, simpler code than C equivalents:

- **`std::vector<double>`** instead of `malloc`/`free` -- automatic cleanup even on exceptions, bounds checking with `.at()`, no manual size tracking.
- **`std::sort`** instead of `qsort` -- type-safe, usually faster (inlines the comparator).
- **`std::thread`/`std::async`** for parallelism -- simpler than pthreads for independent work units. **Important:** never call Stata SDK functions (`SF_vdata`, `SF_vstore`, `SF_display`, etc.) from worker threads. Read all data on the main thread, dispatch computation to workers, then write results back on the main thread. Join all threads before returning from `stata_call`.
- **`std::unordered_map`** for hash tables -- no need to write your own.
- **`std::string`** for string handling -- no buffer overflow risk from `sprintf`.

But keep it simple. This is a Stata plugin, not a framework. Use the standard library where it makes code safer or shorter, not for the sake of being "modern C++."

## Caveats

- **C++ is a much larger language than C.** More features means more ways to make mistakes. If you don't need C++ features, stick with C.
- **Template errors produce unreadable compiler output.** This is especially painful when using Eigen or other template-heavy libraries.
- **Larger binaries** than equivalent C code, though rarely a practical concern for Stata plugins.
- **Cross-compilation can be trickier.** The C++ standard library must be available for the target platform. `-static-libstdc++` on Windows handles this. On Linux/macOS it's usually fine.
- **Debugging is the same challenge as C plugins.** You still can't attach a debugger to Stata's plugin host. Use `SF_display()`, log files, and standalone test harnesses (see Debugging section in main SKILL.md).
- **ABI compatibility matters.** If you compile the library with one compiler version and the wrapper with another, you can get silent corruption. Use the same compiler for everything.
