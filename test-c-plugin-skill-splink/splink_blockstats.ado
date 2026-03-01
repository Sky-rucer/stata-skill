*! version 4.1.0  28feb2026
*! Blocking rule statistics for probabilistic record linkage
*! Reports pair counts per blocking rule from savepairs() output

program define splink_blockstats, rclass
    version 14.0

    syntax using/ [, DIAGnostics(string) NTop(integer 10) Cumulative SAVing(string)]

    * Primary source: pairs CSV with match_key column
    preserve
    quietly {
        import delimited `using', clear

        if _N == 0 {
            display as error "CSV file contains no data rows"
            restore
            exit 198
        }

        capture confirm variable match_key
        if _rc {
            display as error "CSV must contain match_key column (use savepairs())"
            display as error "  match_key records which blocking rule generated each pair"
            exit 198
        }

        * Count pairs per blocking rule
        local total = _N
        quietly summarize match_key
        local max_rule = r(max)
        local min_rule = r(min)
        local n_rules = `max_rule' - `min_rule' + 1
    }

    * Collect per-rule counts
    local cumul_total = 0
    forvalues r = `min_rule'/`max_rule' {
        quietly count if match_key == `r'
        local count_`r' = r(N)
        local cumul_total = `cumul_total' + `count_`r''
    }

    * Read diagnostics file for variable names if provided
    local has_diag = 0
    if `"`diagnostics'"' != "" {
        capture confirm file `"`diagnostics'"'
        if _rc == 0 {
            local has_diag = 1
            tempname fh
            file open `fh' using `"`diagnostics'"', read text
            file read `fh' line
            while r(eof) == 0 {
                local eqpos = strpos("`line'", "=")
                if `eqpos' > 0 {
                    local key = substr("`line'", 1, `eqpos' - 1)
                    local val = substr("`line'", `eqpos' + 1, .)
                    local _d_`key' = "`val'"
                }
                file read `fh' line
            }
            file close `fh'
        }
    }

    restore

    * Display results
    display as text ""
    display as text "{hline 60}"
    display as text "  Splink Blocking Rule Statistics"
    display as text "{hline 60}"
    display as text ""
    display as text "  " _col(5) "Rule" _col(15) "Pairs" _col(30) "Pct" _col(42) "Cumulative"
    display as text "  {hline 52}"

    local cumul_display = 0
    forvalues r = `min_rule'/`max_rule' {
        local pct = 100 * `count_`r'' / `total'
        local cumul_display = `cumul_display' + `count_`r''
        local cumul_pct = 100 * `cumul_display' / `total'

        * Try to get comparison variable names from diagnostics
        local rule_label = "Rule `r'"
        if `has_diag' {
            local rule_label = "Rule `r'"
        }

        display as text "  " _col(5) "`rule_label'" ///
            _col(15) as result %10.0fc `count_`r'' ///
            _col(28) as result %6.1f `pct' "%" ///
            _col(40) as result %10.0fc `cumul_display' ///
            as text " (" as result %5.1f `cumul_pct' "%" as text ")"
    }

    display as text ""
    display as text "  {hline 52}"
    display as text "  " _col(5) "Total" _col(15) as result %10.0fc `total'
    display as text "  " _col(5) "Blocking rules:" _col(25) as result `n_rules'
    display as text "{hline 60}"

    * Additional diagnostics info if available
    if `has_diag' {
        display as text ""
        display as text "  From diagnostics:"
        if "`_d_n_pairs'" != "" {
            display as text "    Total pairs (diag): " as result %10.0fc real("`_d_n_pairs'")
        }
        if "`_d_lambda'" != "" {
            display as text "    Lambda:             " as result %10.6f real("`_d_lambda'")
        }
        if "`_d_em_iterations'" != "" {
            display as text "    EM iterations:      " as result %10.0f real("`_d_em_iterations'")
        }
        if "`_d_n_comp'" != "" {
            display as text "    Comparison fields:  " as result %10.0f real("`_d_n_comp'")
            local nc = real("`_d_n_comp'")
            forvalues k = 0/`=`nc'-1' {
                if "`_d_comp_`k'_var_name'" != "" {
                    display as text "      comp_`k': `_d_comp_`k'_var_name'"
                }
            }
        }
        display as text "{hline 60}"
    }

    * --- N Largest Blocks (Feature 1) ---
    if `ntop' > 0 {
        preserve
        quietly {
            import delimited `using', clear

            * Compute block sizes: group by match_key and all blocking-related columns
            * Since we don't know exact block key columns, use match_key as block indicator
            * Each unique combination of (match_key, blocking_key_values) = one block
            * Approximate: count pairs per unique block key pattern
            * For the n_largest_blocks feature, we count rows per blocking key combination

            * Check if we have ID columns to identify blocks within rules
            local has_ids = 0
            capture confirm variable unique_id_l
            if _rc == 0 {
                local has_ids = 1
                local id_l "unique_id_l"
                local id_r "unique_id_r"
            }
            else {
                capture confirm variable obs_a
                if _rc == 0 {
                    local has_ids = 1
                    local id_l "obs_a"
                    local id_r "obs_b"
                }
            }

            * Count pairs per match_key value (each blocking rule)
            * This gives rule-level block counts
            bysort match_key: gen long _block_size = _N
            bysort match_key: gen byte _first = (_n == 1)
            gsort -_block_size match_key
            keep if _first
            keep match_key _block_size
        }

        local n_display = min(`ntop', _N)
        display as text ""
        display as text "{hline 60}"
        display as text "  `n_display' Largest Blocks (by pair count)"
        display as text "{hline 60}"
        display as text "  " _col(5) "Rule" _col(20) "Pairs in Block"
        display as text "  {hline 40}"
        forvalues i = 1/`n_display' {
            local rule = match_key[`i']
            local bsize = _block_size[`i']
            display as text "  " _col(5) "Rule `rule'" _col(20) as result %10.0fc `bsize'
        }
        display as text "{hline 60}"

        restore
    }

    * --- Cumulative Comparisons Chart (Feature 2) ---
    if "`cumulative'" != "" {
        preserve
        quietly {
            clear
            local n_bars = `max_rule' - `min_rule' + 1
            set obs `n_bars'
            gen int rule_number = .
            gen long pair_count = .
            gen long cumulative_count = .

            local cumul = 0
            local obs = 0
            forvalues r = `min_rule'/`max_rule' {
                local obs = `obs' + 1
                local cumul = `cumul' + `count_`r''
                replace rule_number = `r' in `obs'
                replace pair_count = `count_`r'' in `obs'
                replace cumulative_count = `cumul' in `obs'
            }
        }

        twoway (connected cumulative_count rule_number, ///
                lcolor(navy) mcolor(navy) msymbol(circle)), ///
            xtitle("Blocking Rule") ytitle("Cumulative Pairs") ///
            title("Cumulative Comparisons by Blocking Rule") ///
            xlabel(`min_rule'(1)`max_rule') ///
            graphregion(color(white)) scheme(s2color)

        if `"`saving'"' != "" {
            graph export `"`saving'"', replace
            display as text "Cumulative chart saved to: `saving'"
        }

        restore
    }

    * Return results
    return scalar total_pairs = `total'
    return scalar n_rules = `n_rules'
    forvalues r = `min_rule'/`max_rule' {
        return scalar pairs_rule_`r' = `count_`r''
    }
end
