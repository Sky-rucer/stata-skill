# Testing Strategy for Translated Stata Packages

## Overview

Testing a Stata package translated from Python/R requires three things:
1. **Reference outputs** from the original implementation
2. **Stata tests** that compare against those references
3. **Integration tests** that verify the Stata user experience

## Layer 1: Reference Data Generation (Python/R Script)

### Purpose
Generate test datasets AND reference predictions using the original package. Save everything as CSV so Stata can load it.

### Script Template: `tests/generate_test_data.py`

```python
#!/usr/bin/env python3
"""Generate reference test data for Stata package validation."""

import numpy as np
import pandas as pd
from original_package import OriginalModel

def generate_structured_data(n_train, n_test, n_vars, seed=42):
    """Generate data with known signal for validation."""
    rng = np.random.default_rng(seed)

    n = n_train + n_test
    X = rng.standard_normal((n, n_vars))

    # Known coefficients (decaying importance)
    beta = np.array([3.0 * np.exp(-i / 10) for i in range(n_vars)])

    # Nonlinear signal + noise
    y = X @ beta + 0.3 * X[:, 0]**2 + rng.normal(0, 0.5, n)

    return (X[:n_train], y[:n_train],
            X[n_train:], y[n_train:])

def generate_validation_data():
    """Generate validation data with Python reference predictions."""
    X_train, y_train, X_test, y_test = generate_structured_data(
        n_train=1000, n_test=200, n_vars=4, seed=42
    )

    # Run original implementation
    model = OriginalModel(param1=value1, param2=value2)
    model.fit(X_train, y_train)
    pred_python = model.predict(X_test)

    # Build DataFrame for Stata
    df = pd.DataFrame(X_test, columns=[f'x{i+1}' for i in range(4)])
    df['y'] = y_test  # ground truth
    df['pred_python'] = pred_python  # reference prediction

    # Also include training data (Stata will need it)
    df_train = pd.DataFrame(X_train, columns=[f'x{i+1}' for i in range(4)])
    df_train['y'] = y_train
    df_train['pred_python'] = np.nan  # no predictions for training data

    # Combine: training rows first, then test rows
    df_all = pd.concat([df_train, df], ignore_index=True)
    df_all.to_csv('test_method_data.csv', index=False)

    print(f"Validation data: {len(df_train)} train + {len(df)} test")
    return df_all

def generate_benchmark_data():
    """Generate multiple sizes for performance benchmarking."""
    import time

    sizes = [500, 1000, 2000, 5000]
    for n in sizes:
        X_train, y_train, X_test, y_test = generate_structured_data(
            n_train=n, n_test=n//5, n_vars=4, seed=42
        )

        t0 = time.time()
        model = OriginalModel()
        model.fit(X_train, y_train)
        pred = model.predict(X_test)
        python_time = time.time() - t0

        # Save data
        df = pd.DataFrame(
            np.column_stack([
                np.concatenate([y_train, y_test]),
                np.vstack([X_train, X_test])
            ]),
            columns=['y'] + [f'x{i+1}' for i in range(4)]
        )
        # Append test predictions
        df['pred_python'] = np.nan
        df.iloc[n:, -1] = pred

        df.to_csv(f'bench_method_n{n}.csv', index=False)
        print(f"n={n}: Python time = {python_time:.3f}s")

if __name__ == '__main__':
    generate_validation_data()
    generate_benchmark_data()
```

### Key Principles

1. **Save complete datasets**, not just predictions. Stata needs X and y to run its own model.
2. **Include ground truth y** for test observations. This lets you compute correlation with truth, not just with Python.
3. **Use structured data** with known signal so you can distinguish implementation bugs from method limitations.
4. **Record Python timing** so you can compute speedup factors.
5. **Handle dependency issues gracefully.** Users may not have all Python packages installed. Use try/except and skip gracefully.

## Layer 2: Correctness Tests (Stata)

### Script Template: `tests/run_tests.do`

```stata
*! run_tests.do - Correctness validation against Python reference

clear all
set more off

local total_tests 0
local passed_tests 0
local failed_tests 0

// ============================================================
// TEST: Method correctness
// ============================================================

import delimited using "test_method_data.csv", clear

// Identify training/test split
gen byte is_test = !missing(pred_python)

// Count
quietly count if !is_test
local n_train = r(N)
quietly count if is_test
local n_test = r(N)

di "Training: `n_train', Test: `n_test'"

// Set test y to missing (simulating imputation scenario)
replace y = . if is_test

// Run Stata implementation
packagename y x1 x2 x3 x4, gen(pred_stata) method(method1)

// Compare: correlation between Stata and Python
quietly correlate pred_stata pred_python if is_test
local corr_sp = r(rho)

// Compare: correlation between Stata and truth
// (need to reload y for truth)
import delimited y using "test_method_data.csv", clear case(preserve)
// ... or store truth before replacing

local total_tests = `total_tests' + 1
if `corr_sp' > 0.98 {
    di as res "PASS: Method1 correlation = `corr_sp'"
    local passed_tests = `passed_tests' + 1
}
else {
    di as err "FAIL: Method1 correlation = `corr_sp' (expected > 0.98)"
    local failed_tests = `failed_tests' + 1
}

// ============================================================
// Summary
// ============================================================
di _n "Tests: `total_tests', Passed: `passed_tests', Failed: `failed_tests'"
```

### Correlation Thresholds by Algorithm Type

| Type | Example | Stata vs Python | Rationale |
|------|---------|-----------------|-----------|
| Deterministic, exact | KNN with same distance | r = 1.000 | Should match exactly |
| Deterministic, numerical | OLS, quantile regression | r > 0.999 | Floating point diffs only |
| Stochastic, same algorithm | QRF (both tree-based) | r > 0.95 | Random splits differ |
| Stochastic, different impl | NN (C vs sklearn) | r > 0.90 | Training path diverges |

**Important:** Also check correlation with GROUND TRUTH (not just with Python). A method might match Python perfectly but both be wrong. Correlation with truth validates that the algorithm actually works.

### What to Measure

1. **Correlation** (`correlate pred_stata pred_python`): Overall agreement
2. **Mean Absolute Deviation** (`gen ad = abs(pred_stata - pred_python)`, `summarize ad`): Scale of disagreement
3. **Max Absolute Deviation**: Worst-case disagreement
4. **Exact matches** (for deterministic algorithms): Count where `abs(diff) < 1e-10`

## Layer 3: Integration Tests (Stata)

### Script Template: `tests/test_features.do`

```stata
*! test_features.do - Feature verification

clear all
set more off
local n_tests 0
local n_pass 0
local n_fail 0

// TEST: Missing data handling (core use case)
sysuse auto, clear
replace price = . in 1/10
packagename price mpg weight, gen(price_filled)
quietly count if missing(price) & !missing(price_filled) in 1/10
local filled = r(N)
local n_tests = `n_tests' + 1
if `filled' == 10 {
    di as res "PASS: Missing data filled"
    local n_pass = `n_pass' + 1
}
else {
    di as err "FAIL: Only `filled'/10 missing values filled"
    local n_fail = `n_fail' + 1
}

// TEST: Each method works
foreach m in method1 method2 method3 {
    sysuse auto, clear
    replace price = . in 1/5
    capture noisily packagename price mpg weight, gen(p_`m') method(`m')
    local n_tests = `n_tests' + 1
    if _rc == 0 {
        di as res "PASS: method(`m') works"
        local n_pass = `n_pass' + 1
    }
    else {
        di as err "FAIL: method(`m') returned error `=_rc'"
        local n_fail = `n_fail' + 1
    }
}

// TEST: replace option
sysuse auto, clear
packagename price mpg weight, gen(test_var) method(ols)
capture noisily packagename price mpg weight, gen(test_var) method(ols) replace
local n_tests = `n_tests' + 1
if _rc == 0 {
    di as res "PASS: replace option works"
    local n_pass = `n_pass' + 1
}
else {
    di as err "FAIL: replace option error `=_rc'"
    local n_fail = `n_fail' + 1
}

// TEST: if/in conditions
sysuse auto, clear
packagename price mpg weight if foreign == 1, gen(p_foreign) method(ols)
quietly count if !missing(p_foreign) & foreign == 1
local n_foreign = r(N)
quietly count if foreign == 1
local total_foreign = r(N)
local n_tests = `n_tests' + 1
if `n_foreign' == `total_foreign' {
    di as res "PASS: if condition works"
    local n_pass = `n_pass' + 1
}
else {
    di as err "FAIL: if condition - got `n_foreign'/`total_foreign'"
    local n_fail = `n_fail' + 1
}

// Summary
di _n "Total: `n_tests', Passed: `n_pass', Failed: `n_fail'"
```

### What to Test

1. **Missing data handling** — the core use case. Create missing values, impute, verify all filled.
2. **Every method** — each `method()` option produces output without errors.
3. **replace option** — calling twice with `replace` doesn't error.
4. **if/in conditions** — subsetting works correctly.
5. **Multiple quantiles** — if supported, verify variables are created with correct naming.
6. **Edge cases** — all missing, no missing, single predictor, many predictors.
7. **Stored results** — `r()` values are populated correctly after command.

## Layer 4: Stress Tests

### What to Stress

1. **High dimensionality** (p = 50, 100, 500): Does the method degrade gracefully?
2. **Large n** (n = 10,000+): Does it complete in reasonable time?
3. **Memory** (n * p large): Does it crash or hang?
4. **Correlated features**: AR(1) structure tests numerical stability.
5. **Near-singular data**: Multicollinearity stress test.

### Stress Test Data Generation

```python
from scipy.stats import multivariate_normal

# AR(1) correlation structure
rho = 0.5
cov = np.array([[rho ** abs(i-j) for j in range(p)] for i in range(p)])
X = multivariate_normal(np.zeros(p), cov).rvs(size=n)

# Exponentially decaying coefficients
beta = np.array([3.0 * np.exp(-i / 10) for i in range(p)])
y = X @ beta + 0.3 * X[:, 0]**2 + np.random.normal(0, 0.5, n)
```

### Expected Results by Method Type

- **Tree-based (QRF):** Scales well to high dimensions (automatic feature selection)
- **Distance-based (KNN):** Degrades severely at p > 50 (curse of dimensionality)
- **Neural network:** Scales well if hidden layer is sized appropriately
- **Linear (OLS, quantreg):** Scales well but assumes linearity

## Running Tests

### Batch Mode

```bash
# From the package root directory
stata-mp -b do tests/run_tests.do
stata-mp -b do tests/test_features.do
```

Stata writes output to `run_tests.log` and `test_features.log` in the current directory.

### Checking Results

```bash
grep -E "PASS|FAIL|Total" run_tests.log
grep -E "PASS|FAIL|Total" test_features.log
```

### Platform Detection

macOS reports as "Unix" in Stata's `c(os)`. Handle this:
```stata
if "`c(os)'" == "MacOSX" | ("`c(os)'" == "Unix" & "`c(machine_type)'" == "Mac (Apple Silicon)") {
    local platform "darwin-arm64"
}
```

### Log File Management

Add `*.log` to `.gitignore` early. Log files are large and should not be committed.

## Debugging Test Failures

### Correlation Much Lower Than Expected

1. **Check data sorting.** Is the plugin receiving data in the order it expects?
2. **Check missing value handling.** Is `marksample` using `novarlist`?
3. **Check merge logic.** Does `merge_id` survive preserve/restore?
4. **Check normalization.** Is the NN plugin receiving scaled data?
5. **Run the plugin on known simple data** (e.g., y = 2*x + 1) and verify by hand.

### Plugin Returns All Missing

1. **Check plugin loading.** Is the correct platform plugin found?
2. **Check variable count.** Does `SF_nvar()` match what the plugin expects?
3. **Check argument parsing.** Are `argv[]` values correct?
4. **Check observation count.** Did `keep if \`touse'` leave zero observations?

### Tests Pass Locally But Fail on Another Platform

1. **Integer sizes differ.** Use `int32_t`/`int64_t` from `<stdint.h>`, not `int`/`long`.
2. **Floating point order differs.** Stochastic algorithms may produce different results.
3. **pthreads behavior differs.** Thread scheduling varies by OS.
4. **Endianness** (rare, but check if sharing binary data).
