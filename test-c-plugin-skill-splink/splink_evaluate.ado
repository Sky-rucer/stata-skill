*! version 4.1.0  28feb2026
*! Evaluation metrics for probabilistic record linkage
*! Computes precision, recall, F1 at pair level from labeled data
*! Subcommands: (default) metrics, histogram, unlinkables, sweep

program define splink_evaluate, rclass
    version 14.0

    * --- Subcommand detection ---
    gettoken first rest : 0
    if "`first'" == "histogram" {
        local 0 "`rest'"
        _splink_eval_histogram `0'
        exit
    }
    if "`first'" == "unlinkables" {
        local 0 "`rest'"
        _splink_eval_unlinkables `0'
        exit
    }
    if "`first'" == "sweep" {
        local 0 "`rest'"
        _splink_eval_sweep `0'
        exit
    }

    syntax using/, TRUE(string) ///
        [THReshold(real 0.5) Detail]

    * Load pairwise output
    preserve
    quietly {
        import delimited `using', clear

        capture confirm variable match_probability
        if _rc {
            display as error "CSV must contain match_probability column"
            exit 198
        }
        capture confirm variable `true'
        if _rc {
            display as error "true label variable `true' not found in CSV"
            exit 198
        }

        * Predicted match: match_probability >= threshold
        gen byte _pred_match = match_probability >= `threshold'

        * True match from labels
        rename `true' _true_id
    }

    * Compute confusion matrix
    quietly {
        count if _pred_match == 1 & _true_id == 1
        local tp = r(N)
        count if _pred_match == 1 & _true_id == 0
        local fp = r(N)
        count if _pred_match == 0 & _true_id == 1
        local fn = r(N)
        count if _pred_match == 0 & _true_id == 0
        local tn = r(N)
    }

    * Compute metrics
    local precision = 0
    local recall = 0
    local f1 = 0
    local accuracy = 0

    if `tp' + `fp' > 0 local precision = `tp' / (`tp' + `fp')
    if `tp' + `fn' > 0 local recall = `tp' / (`tp' + `fn')
    if `precision' + `recall' > 0 {
        local f1 = 2 * `precision' * `recall' / (`precision' + `recall')
    }
    local total = `tp' + `fp' + `fn' + `tn'
    if `total' > 0 local accuracy = (`tp' + `tn') / `total'

    restore

    * Display results
    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Evaluation (threshold = " as result %5.3f `threshold' as text ")"
    display as text "{hline 50}"
    display as text "  True Positives:   " as result %10.0fc `tp'
    display as text "  False Positives:  " as result %10.0fc `fp'
    display as text "  False Negatives:  " as result %10.0fc `fn'
    display as text "  True Negatives:   " as result %10.0fc `tn'
    display as text "{hline 50}"
    display as text "  Precision:        " as result %10.6f `precision'
    display as text "  Recall:           " as result %10.6f `recall'
    display as text "  F1 Score:         " as result %10.6f `f1'
    display as text "  Accuracy:         " as result %10.6f `accuracy'
    display as text "{hline 50}"

    * Return scalars
    return scalar tp = `tp'
    return scalar fp = `fp'
    return scalar fn = `fn'
    return scalar tn = `tn'
    return scalar precision = `precision'
    return scalar recall = `recall'
    return scalar f1 = `f1'
    return scalar accuracy = `accuracy'
    return scalar threshold = `threshold'
end

* --- Histogram subcommand ---
* Plots histogram of match_weight from savepairs() output
program define _splink_eval_histogram
    syntax using/ [, THReshold(real -999) SAVing(string) BINS(integer 30)]

    preserve
    quietly {
        import delimited `using', clear

        capture confirm variable match_weight
        if _rc {
            display as error "CSV must contain match_weight column (use savepairs())"
            exit 198
        }
    }

    if `threshold' != -999 {
        histogram match_weight, frequency bin(`bins') ///
            fcolor(navy) lcolor(navy) ///
            xline(`threshold', lcolor(cranberry) lwidth(medthick) lpattern(dash)) ///
            title("Distribution of Match Weights") ///
            xtitle("Match Weight (log2 Bayes Factor)") ///
            ytitle("Frequency") ///
            note("Dashed line: threshold = `threshold'") ///
            graphregion(color(white)) scheme(s2color)
    }
    else {
        histogram match_weight, frequency bin(`bins') ///
            fcolor(navy) lcolor(navy) ///
            title("Distribution of Match Weights") ///
            xtitle("Match Weight (log2 Bayes Factor)") ///
            ytitle("Frequency") ///
            graphregion(color(white)) scheme(s2color)
    }

    if `"`saving'"' != "" {
        graph export `"`saving'"', replace
        display as text "Chart saved to: `saving'"
    }

    quietly summarize match_weight
    display as text ""
    display as text "{hline 50}"
    display as text "  Match Weight Distribution"
    display as text "{hline 50}"
    display as text "  N pairs:   " as result %12.0fc r(N)
    display as text "  Mean:      " as result %12.3f r(mean)
    display as text "  Std Dev:   " as result %12.3f r(sd)
    display as text "  Min:       " as result %12.3f r(min)
    display as text "  Max:       " as result %12.3f r(max)
    display as text "{hline 50}"

    restore
end

* --- Unlinkables subcommand ---
* Identifies records that never appear in any match above threshold
program define _splink_eval_unlinkables, rclass
    syntax using/ [, THReshold(real 0.5)]

    preserve
    quietly {
        import delimited `using', clear

        * Determine ID columns
        local id_l "unique_id_l"
        local id_r "unique_id_r"
        capture confirm variable unique_id_l
        if _rc {
            local id_l "obs_a"
            local id_r "obs_b"
        }
    }

    capture confirm variable `id_l'
    if _rc {
        display as error "CSV must contain unique_id_l/unique_id_r or obs_a/obs_b columns"
        restore
        exit 198
    }

    quietly {

        * Keep only matches above threshold
        keep if match_probability >= `threshold'
        local n_matched_pairs = _N

        if `n_matched_pairs' == 0 {
            display as text "No pairs above threshold `threshold'. All records are unlinkable."
            restore
            return scalar n_unlinkable = .
            return scalar pct_unlinkable = 100
            exit
        }

        * Collect all linked IDs
        tempfile linked_ids
        keep `id_l' `id_r'
        rename `id_l' _id
        tempfile left_ids
        save `left_ids'
        restore, preserve
        import delimited `using', clear
        keep if match_probability >= `threshold'
        keep `id_r'
        rename `id_r' _id
        append using `left_ids'
        duplicates drop _id, force
        local n_linked = _N
        save `linked_ids'

        * Get full range of IDs from the original dataset
        restore, preserve
        import delimited `using', clear
        keep `id_l'
        rename `id_l' _id
        tempfile all_left
        save `all_left'
        restore, preserve
        import delimited `using', clear
        keep `id_r'
        rename `id_r' _id
        append using `all_left'
        duplicates drop _id, force
        local n_total = _N

        * Find unlinkable: in all IDs but not in linked IDs
        merge 1:1 _id using `linked_ids', keep(master) nogenerate
        local n_unlinkable = _N
    }

    local pct_unlinkable = 100 * `n_unlinkable' / `n_total'

    restore

    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Unlinkables Analysis"
    display as text "  (threshold = " as result %5.3f `threshold' as text ")"
    display as text "{hline 50}"
    display as text "  Total unique IDs:   " as result %10.0fc `n_total'
    display as text "  Linked IDs:         " as result %10.0fc `n_linked'
    display as text "  Unlinkable IDs:     " as result %10.0fc `n_unlinkable'
    display as text "  Pct unlinkable:     " as result %9.1f `pct_unlinkable' "%"
    display as text "{hline 50}"

    return scalar n_total = `n_total'
    return scalar n_linked = `n_linked'
    return scalar n_unlinkable = `n_unlinkable'
    return scalar pct_unlinkable = `pct_unlinkable'
end

* --- Sweep subcommand ---
* Threshold sweep computing precision/recall/F1 at multiple thresholds
program define _splink_eval_sweep, rclass
    syntax using/, TRUE(string) [STeps(integer 50) SAVing(string)]

    preserve
    quietly {
        import delimited `using', clear

        capture confirm variable `true'
        if _rc {
            display as error "true label variable `true' not found in CSV"
            exit 198
        }

        capture confirm variable match_probability
        if _rc {
            display as error "CSV must contain match_probability column"
            exit 198
        }

        * Store data in a tempfile for repeated access
        tempfile sweep_data
        save `sweep_data'
    }

    * Compute metrics at each threshold
    local best_f1 = 0
    local best_thresh = 0
    if `steps' < 2 {
        display as error "steps() must be >= 2 for sweep"
        restore
        exit 198
    }
    local step_size = 1 / (`steps' - 1)

    forvalues s = 1/`steps' {
        local thresh = (`s' - 1) * `step_size'
        quietly {
            use `sweep_data', clear
            count if match_probability >= `thresh' & `true' == 1
            local tp = r(N)
            count if match_probability >= `thresh' & `true' == 0
            local fp = r(N)
            count if match_probability < `thresh' & `true' == 1
            local fn = r(N)
            count if match_probability < `thresh' & `true' == 0
            local tn = r(N)
        }

        local prec = 0
        local rec = 0
        local f = 0
        if `tp' + `fp' > 0 local prec = `tp' / (`tp' + `fp')
        if `tp' + `fn' > 0 local rec = `tp' / (`tp' + `fn')
        if `prec' + `rec' > 0 local f = 2 * `prec' * `rec' / (`prec' + `rec')

        if `f' > `best_f1' {
            local best_f1 = `f'
            local best_thresh = `thresh'
        }

        local _thresh_`s' = `thresh'
        local _prec_`s' = `prec'
        local _rec_`s' = `rec'
        local _f1_`s' = `f'
    }

    * Build results dataset and plot
    quietly {
        clear
        set obs `steps'
        gen double threshold = .
        gen double precision = .
        gen double recall = .
        gen double f1 = .

        forvalues s = 1/`steps' {
            replace threshold = `_thresh_`s'' in `s'
            replace precision = `_prec_`s'' in `s'
            replace recall = `_rec_`s'' in `s'
            replace f1 = `_f1_`s'' in `s'
        }
    }

    * Plot precision-recall-F1 curves
    twoway (connected precision threshold, lcolor(navy) mcolor(navy) msymbol(none)) ///
           (connected recall threshold, lcolor(cranberry) mcolor(cranberry) msymbol(none)) ///
           (connected f1 threshold, lcolor(forest_green) mcolor(forest_green) msymbol(none)), ///
        legend(order(1 "Precision" 2 "Recall" 3 "F1") rows(1) position(6)) ///
        xtitle("Match Probability Threshold") ytitle("Score") ///
        title("Precision / Recall / F1 vs Threshold") ///
        ylabel(0(0.1)1) xlabel(0(0.1)1) ///
        xline(`best_thresh', lcolor(gs10) lpattern(dash)) ///
        note("Best F1 = `:display %5.3f `best_f1'' at threshold = `:display %5.3f `best_thresh''") ///
        graphregion(color(white)) scheme(s2color)

    if `"`saving'"' != "" {
        graph export `"`saving'"', replace
        display as text "Chart saved to: `saving'"
    }

    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Threshold Sweep"
    display as text "{hline 50}"
    display as text "  Steps:            " as result %10.0f `steps'
    display as text "  Best F1:          " as result %10.6f `best_f1'
    display as text "  Best threshold:   " as result %10.4f `best_thresh'
    display as text "{hline 50}"

    restore

    return scalar best_f1 = `best_f1'
    return scalar best_threshold = `best_thresh'
    return scalar steps = `steps'
end
