*! version 4.1.0  28feb2026
*! Waterfall chart of Bayes factor contributions per comparison field
*! Shows how each field shifts the match weight from prior to final score

program define splink_waterfall
    version 14.0

    syntax using/, PAIR(integer) [SAVing(string) PRior(real 0.0001)]

    if `pair' < 1 {
        display as error "pair() must be >= 1"
        exit 198
    }
    if `prior' <= 0 | `prior' >= 1 {
        display as error "prior() must be between 0 and 1"
        exit 198
    }

    preserve
    quietly {
        import delimited `using', clear

        * Check required columns exist
        capture confirm variable match_weight
        if _rc {
            display as error "CSV must contain match_weight column (use savepairs())"
            exit 198
        }

        local N = _N
        if `pair' > `N' {
            display as error "pair(`pair') exceeds number of pairs (`N')"
            exit 198
        }

        * Identify bf_* columns and extract values in a single pass
        local bf_vars ""
        local bf_labels ""
        local n_bf = 0
        foreach v of varlist _all {
            if substr("`v'", 1, 3) == "bf_" {
                local n_bf = `n_bf' + 1
                local bf_vars "`bf_vars' `v'"
                local lbl = substr("`v'", 4, .)
                local bf_labels `"`bf_labels' "`lbl'""'
                * Extract BF value for selected pair
                local bf_val_`n_bf' = `v'[`pair']
            }
        }

        if `n_bf' == 0 {
            display as error "no bf_* columns found in CSV"
            exit 198
        }

        * Build waterfall dataset from extracted locals
        local log2_prior = ln(`prior' / (1 - `prior')) / ln(2)
        local n_bars = `n_bf' + 2

        clear
        set obs `n_bars'

        gen str32 field = ""
        gen double contribution = .
        gen double cumulative = .
        gen double bar_bottom = .
        gen double bar_top = .
        gen int order = _n

        * First bar: prior
        replace field = "Prior" in 1
        replace contribution = `log2_prior' in 1
        replace cumulative = `log2_prior' in 1
        replace bar_bottom = 0 in 1
        replace bar_top = `log2_prior' in 1

        * BF contribution bars
        local running = `log2_prior'
        forvalues i = 1/`n_bf' {
            local obs = `i' + 1
            if `bf_val_`i'' <= 0 {
                local log2_bf = -20
            }
            else {
                local log2_bf = ln(`bf_val_`i'') / ln(2)
            }
            local lbl : word `i' of `bf_labels'
            replace field = "`lbl'" in `obs'
            replace contribution = `log2_bf' in `obs'
            local prev = `running'
            local running = `running' + `log2_bf'
            replace cumulative = `running' in `obs'
            if `log2_bf' >= 0 {
                replace bar_bottom = `prev' in `obs'
                replace bar_top = `running' in `obs'
            }
            else {
                replace bar_bottom = `running' in `obs'
                replace bar_top = `prev' in `obs'
            }
        }

        * Final bar: total match weight
        replace field = "Total" in `n_bars'
        replace contribution = `running' in `n_bars'
        replace cumulative = `running' in `n_bars'
        replace bar_bottom = 0 in `n_bars'
        replace bar_top = `running' in `n_bars'

        * Generate color indicator
        gen byte color_type = cond(contribution >= 0, 1, 2)
        replace color_type = 3 in 1
        replace color_type = 3 in `n_bars'

        * Apply value labels before drawing chart
        label define _wf_fields 1 "Prior", replace
        local j = 2
        foreach lbl of local bf_labels {
            label define _wf_fields `j' "`lbl'", add
            local j = `j' + 1
        }
        label define _wf_fields `n_bars' "Total", add
        label values order _wf_fields
    }

    * Draw the waterfall chart (single draw with labels)
    twoway (rbar bar_bottom bar_top order if color_type == 1, ///
                horizontal barwidth(0.6) fcolor(navy) lcolor(navy)) ///
           (rbar bar_bottom bar_top order if color_type == 2, ///
                horizontal barwidth(0.6) fcolor(cranberry) lcolor(cranberry)) ///
           (rbar bar_bottom bar_top order if color_type == 3, ///
                horizontal barwidth(0.6) fcolor(gs8) lcolor(gs8)), ///
        ylabel(1/`n_bars', valuelabel angle(0) labsize(small)) ///
        ytitle("") xtitle("Match Weight (log2 Bayes Factor)") ///
        title("Waterfall: Match Weight Decomposition") ///
        subtitle("Pair `pair'") ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        legend(order(1 "Positive" 2 "Negative" 3 "Prior/Total") ///
            position(6) rows(1) size(small)) ///
        graphregion(color(white)) plotregion(color(white)) ///
        scheme(s2color)

    if `"`saving'"' != "" {
        graph export `"`saving'"', replace
        display as text "Chart saved to: `saving'"
    }

    * Display summary table
    display as text ""
    display as text "{hline 45}"
    display as text "  Waterfall Summary (Pair `pair')"
    display as text "{hline 45}"
    display as text "  " _col(5) "Field" _col(25) "log2(BF)" _col(37) "Cumulative"
    display as text "{hline 45}"
    forvalues r = 1/`n_bars' {
        local f = field[`r']
        local c = contribution[`r']
        local cum = cumulative[`r']
        display as text "  " _col(5) "`f'" _col(23) as result %8.3f `c' _col(35) %8.3f `cum'
    }
    display as text "{hline 45}"

    restore
end
