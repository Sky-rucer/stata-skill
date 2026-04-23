# csdid: Difference-in-Differences with Multiple Periods

## Overview

`csdid` implements the Callaway and Sant'Anna (2021) estimator for staggered-adoption DiD designs with multiple periods.

The main idea is to estimate group-time treatment effects, `ATT(g,t)`, using only valid control groups:

- never-treated units
- or not-yet-treated units

This avoids the forbidden-comparison problem that can bias traditional TWFE/event-study estimates under heterogeneous treatment effects.

Internally, `csdid` uses `drdid` to estimate all feasible `2x2` designs and then aggregates them.

---

## Installation

```stata
ssc install drdid
ssc install csdid
ssc install avar
```

Useful supporting packages:

```stata
ssc install coefplot
ssc install boottest
```

---

## Basic Syntax

```stata
csdid depvar [indepvars] [if] [in] [weight], ///
    [ivar(panel_id)] ///
    time(time_var) ///
    gvar(first_treat_var) ///
    [options]
```

Core arguments:

- `depvar`: outcome variable
- `indepvars`: controls/covariates
- `ivar(varname)`: panel identifier; omit for repeated cross-sections
- `time(varname)`: time variable
- `gvar(varname)`: first treatment period; never-treated units must be coded as `0`

---

## Data Requirements

### Treatment Coding

`gvar()` must identify the first treatment period:

- `0` = never treated
- positive value = first period treated

Example:

```stata
* Never treated
gvar = 0

* Treated first in 2015
gvar = 2015
```

Once a unit is treated, `csdid` assumes treatment is absorbing.

### Panel vs Repeated Cross-Section

- If `ivar()` is provided, `csdid` assumes panel data.
- If `ivar()` is omitted, `csdid` assumes repeated cross-sections.

### Pre-Treatment Support

For each treated cohort:

- the treatment year in `gvar()` must appear in the data
- you need at least one pre-treatment period

If a cohort is first treated before the sample starts, those observations are treated as always-treated and excluded.

### Covariates

When using panel data, even if covariates vary over time, `csdid` uses only base-period values for estimation.

For repeated cross-sections, covariates should be interpreted cautiously. Prefer:

- time-invariant controls
- or clearly pre-treatment characteristics

---

## Main Estimation Methods

Use `method()` to choose the estimator.

```stata
method(dripw)
method(drimp)
method(reg)
method(stdipw)
method(ipw)
```

### Available Methods

- `dripw`:
  Doubly robust estimator based on stabilized inverse probability weighting and OLS. This is the default when covariates are supplied.

- `drimp`:
  Improved doubly robust estimator based on inverse probability tilting and weighted least squares.

- `reg`:
  Outcome-regression estimator based on OLS. If no covariates are supplied, this effectively becomes the default.

- `stdipw`:
  Stabilized IPW estimator.

- `ipw`:
  Abadie (2005)-style IPW estimator.

- `rc1`:
  For repeated cross-sections, with `dripw` or `drimp`, requests the doubly robust but not locally efficient RC estimator.

---

## Control Group Choice

### Default

By default, `csdid` uses never-treated units as controls.

### `notyet`

```stata
csdid y x1 x2, ivar(id) time(year) gvar(first_treat) notyet
```

This uses:

- never-treated units
- plus not-yet-treated units

If there are no never-treated observations, `csdid` automatically falls back to not-yet-treated controls.

### `asinr`

This option changes pre-treatment comparisons to better match the behavior of the R `did` package.

Use it when you are trying to replicate results from the R implementation.

---

## Pre-Treatment Gap Options

### Default behavior

For pre-treatment ATTGTs, the default is to estimate short gaps:

- base period = `T-1`
- comparison period = `T`

### `long`

```stata
csdid y, ivar(id) time(year) gvar(g) long
```

Requests long-gap pre-treatment effects instead of short-gap effects.

### `long2`

```stata
csdid y, ivar(id) time(year) gvar(g) long2
```

Also requests long-gap style pre-treatment effects, but with the sign convention closest to standard event-study displays.

This is often the easier option when you want event-study-style interpretation.

---

## Standard Errors

By default, `csdid` reports robust asymptotic standard errors based on influence functions.

### Wild Bootstrap

```stata
csdid y x, ivar(id) time(year) gvar(g) wboot
```

Default wild bootstrap settings:

- `999` repetitions
- Mammen weights

### Wild Bootstrap Options

```stata
csdid y x, ivar(id) time(year) gvar(g) ///
    wboot(reps(999) wtype(mammen)) ///
    rseed(12345)
```

Options:

- `reps(#)`: number of repetitions
- `wtype(mammen|rademacher)`: bootstrap weight type
- `rseed(#)`: seed for reproducibility

### Clustering

```stata
csdid y x, ivar(id) time(year) gvar(g) cluster(county)
```

Notes:

- with panel estimators, standard errors are already clustered at the panel level
- specifying `cluster()` with panel data effectively requests two-way clustering
- when panel estimators are used, `ivar()` should be nested within the cluster variable

### Confidence Intervals

- `level(#)`: change CI level
- `pointwise`: request pointwise CIs with wild bootstrap; otherwise uniform CIs are used

---

## Aggregation Options

By default, `csdid` reports `attgt`, the treatment effect for a given cohort and time.

You can change output using `agg()`.

### `agg(attgt)` (default)

Group-time ATT estimates.

### `agg(simple)`

Overall ATT across all groups and periods.

### `agg(group)`

Average ATT by treatment cohort.

### `agg(calendar)`

Average ATT by calendar period.

### `agg(event)`

Dynamic/event-time ATT estimates relative to first treatment.

Example:

```stata
csdid lemp lpop, ///
    ivar(countyreal) time(year) gvar(first_treat) ///
    method(dripw) agg(event)
```

---

## Saving RIFs

You can save recentered influence functions for later aggregation or post-estimation:

```stata
csdid y x1 x2, ///
    ivar(id) time(year) gvar(g) ///
    saverif(myrifs.dta) replace
```

This is useful when:

- you want alternative aggregations later
- you want to use `csdid_stats`
- you want to combine with wild-bootstrap workflows

---

## Postestimation

Key postestimation tools:

- `csdid_estat`
- `csdid_stats`
- `csdid_plot`
- `csdid_rif`

Examples:

```stata
* Estimate ATT(g,t)
csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) method(dripw)

* Event-study aggregation
estat event

* Group aggregation
estat group

* Calendar aggregation
estat calendar

* Plot results
csdid_plot
```

See also:

- `help csdid_postestimation`
- `help csdid_estat`
- `help csdid_stats`
- `help csdid_plot`
- `help drdid`

---

## Example Workflows

### Panel Data

```stata
csdid lemp lpop, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw)
```

### Panel Data with Wild Bootstrap

```stata
csdid lemp lpop, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw) ///
    wboot rseed(1)
```

### Repeated Cross-Section

```stata
csdid lemp lpop, ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw) ///
    wboot rseed(1)
```

### Event-Study Aggregation

```stata
csdid lemp lpop, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw) ///
    wboot rseed(1) ///
    agg(event)
```

### Event-Study with Not-Yet-Treated Controls

```stata
csdid lemp lpop, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw) ///
    wboot rseed(1) ///
    agg(event) ///
    notyet
```

### Unbalanced Panel, Panel Estimator

```stata
set seed 1
gen sample = runiform() < .9

csdid lemp lpop if sample == 1, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw)
```

### Unbalanced Panel, Repeated Cross-Section Style with Clustering

```stata
csdid lemp lpop if sample == 1, ///
    cluster(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw)
```

---

## Practical Interpretation Notes

### What `csdid` is doing

`csdid` estimates treatment effects separately by:

- treatment cohort `g`
- calendar time `t`

and only afterward aggregates them.

This is why it is safer than TWFE under staggered adoption and heterogeneous effects.

### Why it can be slow

For many periods and many treated cohorts, `csdid` must estimate a large number of `2x2` designs. In repeated cross-section settings with long panels, this can become memory intensive.

If the problem is too large:

- reduce the number of periods
- collapse or refine treatment cohorts
- focus on substantively important windows

### Unbalanced Panels

`csdid` does not require a strongly balanced panel.

However, each `ATT(g,t)` uses only units balanced within the specific `2x2` comparison behind that estimate.

---

## Common Pitfalls

### 1. Wrong treatment coding

Never-treated units should be coded as `0` in `gvar()`, not with arbitrary years or changing values.

### 2. No pre-treatment observations

Each treated cohort needs at least one period before treatment, otherwise ATTGTs cannot be identified.

### 3. Units changing cohort over time

In panel data, a unit cannot switch its first-treatment cohort across periods.

### 4. Misinterpreting `notyet`, `long`, and `long2`

These options affect control-group construction or pre-treatment gap construction. They are not cosmetic changes; they can materially change estimates.

### 5. Treating time-varying controls casually

In panel settings, only base-period covariates are used. Interpret control inclusion accordingly.

---

## Minimal Replication Template

```stata
* 1. Basic checks
tab first_treat
summ year
isid countyreal year

* 2. Estimate ATT(g,t)
csdid lemp lpop, ///
    ivar(countyreal) ///
    time(year) ///
    gvar(first_treat) ///
    method(dripw)

* 3. Aggregate dynamically
estat event

* 4. Plot
csdid_plot
```

---

## References

- Abadie, Alberto. 2005. "Semiparametric Difference-in-Differences Estimators." *Review of Economic Studies* 72(1): 1-19.
- Callaway, Brantly, and Pedro H. C. Sant'Anna. 2021. "Difference-in-Differences with Multiple Time Periods." *Journal of Econometrics* 225(2): 200-230.
- Sant'Anna, Pedro H. C., and Jun Zhao. 2020. "Doubly Robust Difference-in-Differences Estimators." *Journal of Econometrics* 219(1): 101-122.
- Rios-Avila, Fernando, Pedro H. C. Sant'Anna, and Brantly Callaway. `csdid`: Difference-in-Differences with Multiple Periods.

---

## Related Files

- `packages/did.md`
- `packages/event-study.md`
- `references/difference-in-differences.md`
