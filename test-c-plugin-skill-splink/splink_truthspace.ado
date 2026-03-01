*! version 4.1.0  28feb2026
*! Threshold sweep for probabilistic record linkage
*! Computes precision/recall at multiple thresholds for curve generation

program define splink_truthspace, rclass
    version 14.0

    syntax using/, TRUE(string) ///
        [STeps(integer 20) MINThreshold(real 0.0) MAXThreshold(real 1.0) ///
         SAVEResults(string)]

    if `steps' < 1 {
        display as error "steps() must be >= 1"
        exit 198
    }

    preserve
    quietly import delimited `using', clear

    capture confirm variable match_probability
    if _rc {
        display as error "CSV must contain match_probability column"
        restore
        exit 198
    }
    capture confirm variable `true'
    if _rc {
        display as error "true label variable `true' not found in CSV"
        restore
        exit 198
    }

    local step_size = (`maxthreshold' - `minthreshold') / `steps'

    * Run sweep, accumulate results in locals
    local best_f1 = 0
    local best_thresh = 0

    forvalues s = 1/`steps' {
        local thresh = `minthreshold' + (`s' - 0.5) * `step_size'

        quietly {
            count if match_probability >= `thresh' & `true' == 1
            local tp = r(N)
            count if match_probability >= `thresh' & `true' == 0
            local fp = r(N)
            count if match_probability < `thresh' & `true' == 1
            local fn = r(N)
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

        * Store results in locals for later
        local _thresh_`s' = `thresh'
        local _prec_`s' = `prec'
        local _rec_`s' = `rec'
        local _f1_`s' = `f'
        local _tp_`s' = `tp'
        local _fp_`s' = `fp'
        local _fn_`s' = `fn'
    }

    restore

    * Display summary
    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Threshold Sweep"
    display as text "{hline 50}"
    display as text "  Steps:            " as result %10.0f `steps'
    display as text "  Range:            " as result %5.2f `minthreshold' as text " - " as result %5.2f `maxthreshold'
    display as text "  Best F1:          " as result %10.6f `best_f1'
    display as text "  Best threshold:   " as result %10.4f `best_thresh'
    display as text "{hline 50}"

    if `"`saveresults'"' != "" {
        preserve
        quietly {
            clear
            set obs `steps'
            gen double threshold = .
            gen double precision = .
            gen double recall = .
            gen double f1 = .
            gen long tp = .
            gen long fp = .
            gen long fn = .
            forvalues s = 1/`steps' {
                replace threshold = `_thresh_`s'' in `s'
                replace precision = `_prec_`s'' in `s'
                replace recall = `_rec_`s'' in `s'
                replace f1 = `_f1_`s'' in `s'
                replace tp = `_tp_`s'' in `s'
                replace fp = `_fp_`s'' in `s'
                replace fn = `_fn_`s'' in `s'
            }
            save `"`saveresults'"', replace
        }
        restore
        display as text "  Results saved to: `saveresults'"
    }

    * Return
    return scalar best_f1 = `best_f1'
    return scalar best_threshold = `best_thresh'
    return scalar steps = `steps'
end
