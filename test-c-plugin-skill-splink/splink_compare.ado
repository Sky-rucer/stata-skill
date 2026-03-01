*! version 4.1.0  28feb2026
*! Compare two observations using a trained splink model
*! Shows per-field gamma, Bayes factor, and overall match weight

program define splink_compare, rclass
    version 14.0

    syntax anything(name=obspair), MODel(string) [Verbose]

    * Parse two observation numbers
    local obs1 : word 1 of `obspair'
    local obs2 : word 2 of `obspair'

    if "`obs1'" == "" | "`obs2'" == "" {
        display as error "usage: splink_compare obs1 obs2, model(filename)"
        exit 198
    }

    capture confirm integer number `obs1'
    if _rc {
        display as error "obs1 must be an integer"
        exit 198
    }
    capture confirm integer number `obs2'
    if _rc {
        display as error "obs2 must be an integer"
        exit 198
    }

    if `obs1' < 1 | `obs1' > _N {
        display as error "obs1 (`obs1') out of range (1 to `=_N')"
        exit 198
    }
    if `obs2' < 1 | `obs2' > _N {
        display as error "obs2 (`obs2') out of range (1 to `=_N')"
        exit 198
    }

    capture confirm file `"`model'"'
    if _rc {
        display as error "model file not found: `model'"
        exit 601
    }

    * --- Parse model JSON ---
    tempname fh
    file open `fh' using `"`model'"', read text

    local lambda = 0.0001
    local n_comp = 0
    local in_levels = 0
    local level_idx = 0
    local current_var = ""

    file read `fh' line
    while r(eof) == 0 {
        local line = strtrim(`"`line'"')

        * Extract lambda
        if strpos(`"`line'"', `""probability_two_random_records_match""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                local lambda = real("`vpart'")
            }
        }

        * Extract variable name (output_column_name or comparison_description)
        if strpos(`"`line'"', `""output_column_name""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", `"""', "", .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                * Strip gamma_ prefix if present
                if substr("`vpart'", 1, 6) == "gamma_" {
                    local vpart = substr("`vpart'", 7, .)
                }
                local current_var = "`vpart'"
            }
        }

        * Track comparison_levels
        if strpos(`"`line'"', `""comparison_levels""') > 0 {
            local in_levels = 1
            local level_idx = 0
            local n_comp = `n_comp' + 1
            local _comp_var_`n_comp' = "`current_var'"
            local _comp_nlevels_`n_comp' = 0
        }

        * Extract m_probability
        if `in_levels' & strpos(`"`line'"', `""m_probability""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                local _comp_m_`n_comp'_`level_idx' = real("`vpart'")
            }
        }

        * Extract u_probability
        if `in_levels' & strpos(`"`line'"', `""u_probability""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                local _comp_u_`n_comp'_`level_idx' = real("`vpart'")
            }
            local level_idx = `level_idx' + 1
            local _comp_nlevels_`n_comp' = `level_idx'
        }

        * Extract threshold from sql_condition if present
        if `in_levels' & strpos(`"`line'"', `""sql_condition""') > 0 {
            * Look for >= X.XX pattern
            local gepos = strpos(`"`line'"', ">= ")
            if `gepos' > 0 {
                local thstr = substr(`"`line'"', `gepos' + 3, 10)
                local thstr = subinstr("`thstr'", `"""', "", .)
                local thstr = subinstr("`thstr'", ",", "", .)
                local thstr = strtrim("`thstr'")
                local thval = real("`thstr'")
                if `thval' != . {
                    local _comp_thresh_`n_comp'_`level_idx' = `thval'
                }
            }
            else {
                * Check for = X.XX pattern (exact threshold)
                local eqpos = strpos(`"`line'"', "= ")
                if `eqpos' > 0 {
                    local thstr = substr(`"`line'"', `eqpos' + 2, 10)
                    local thstr = subinstr("`thstr'", `"""', "", .)
                    local thstr = subinstr("`thstr'", ",", "", .)
                    local thstr = strtrim("`thstr'")
                    local thval = real("`thstr'")
                    if `thval' != . {
                        local _comp_thresh_`n_comp'_`level_idx' = `thval'
                    }
                }
                * ELSE or other non-threshold patterns: no threshold set,
                * gamma assignment will use default spacing fallback
            }
        }

        * Track is_null_level
        if `in_levels' & strpos(`"`line'"', `""is_null_level": true"') > 0 {
            local _comp_null_`n_comp'_`level_idx' = 1
        }

        * End of comparison_levels array
        if `in_levels' & strpos(`"`line'"', "]") > 0 & strpos(`"`line'"', "[") == 0 {
            local in_levels = 0
        }

        file read `fh' line
    }
    file close `fh'

    if `n_comp' == 0 {
        display as error "no comparisons found in model JSON"
        exit 198
    }

    * --- Compare observations ---
    local total_log2_bf = 0
    local log2_prior = ln(`lambda' / (1 - `lambda')) / ln(2)

    display as text ""
    display as text "{hline 72}"
    display as text "  Splink Pairwise Comparison: obs `obs1' vs obs `obs2'"
    display as text "{hline 72}"
    display as text "  " _col(3) "Variable" _col(18) "Value (L)" ///
        _col(34) "Value (R)" _col(49) "Gamma" _col(56) "log2(BF)"
    display as text "  {hline 68}"

    forvalues k = 1/`n_comp' {
        local vname = "`_comp_var_`k''"
        local nl = `_comp_nlevels_`k''

        * Get values from both observations
        local val_l = ""
        local val_r = ""
        capture confirm variable `vname'
        if _rc == 0 {
            capture confirm string variable `vname'
            if _rc == 0 {
                * String variable
                local val_l = `vname'[`obs1']
                local val_r = `vname'[`obs2']
            }
            else {
                * Numeric variable
                local val_l = `vname'[`obs1']
                local val_r = `vname'[`obs2']
            }
        }
        else {
            local val_l = "(not found)"
            local val_r = "(not found)"
        }

        * Determine gamma level
        * Level 0 = else (lowest), last level = exact match (highest)
        * Null level (is_null_level=true) gets gamma = -1 (neutral)
        local gamma = 0
        local is_null = 0

        * Check for missing values (type already checked above)
        if _rc == 0 {
            * String: missing if empty
            if `"`val_l'"' == "" | `"`val_r'"' == "" {
                local is_null = 1
            }
            else if `"`val_l'"' == `"`val_r'"' {
                * Exact match -> highest non-null level
                local gamma = `=`nl' - 1'
            }
            else {
                * Fuzzy matching for string variables (ustrsimilar requires Stata 16+)
                if c(stata_version) >= 16 {
                    local sim = ustrsimilar(`"`val_l'"', `"`val_r'"') / 100
                }
                else {
                    * Stata < 16: no fuzzy matching available, treat as non-match
                    local sim = 0
                }
                local max_gamma = `=`nl' - 1'
                forvalues g = `=`max_gamma' - 1'(-1)1 {
                    local thresh_val = "`_comp_thresh_`k'_`g''"
                    if "`thresh_val'" != "" & "`thresh_val'" != "." {
                        if `sim' >= `thresh_val' {
                            local gamma = `g'
                            continue, break
                        }
                    }
                    else {
                        * No threshold parsed; use evenly-spaced default
                        local default_thresh = 1 - `g' * (1 - 0.5) / `max_gamma'
                        if `sim' >= `default_thresh' {
                            local gamma = `g'
                            continue, break
                        }
                    }
                }
            }
        }
        else {
            * Numeric: missing if .
            if `val_l' == . | `val_r' == . {
                local is_null = 1
            }
            else if `val_l' == `val_r' {
                local gamma = `=`nl' - 1'
            }
            else {
                * Fuzzy matching for numeric variables
                local diff = abs(`val_l' - `val_r')
                local max_gamma = `=`nl' - 1'
                forvalues g = `=`max_gamma' - 1'(-1)1 {
                    local thresh_val = "`_comp_thresh_`k'_`g''"
                    if "`thresh_val'" != "" & "`thresh_val'" != "." {
                        if `diff' <= `thresh_val' {
                            local gamma = `g'
                            continue, break
                        }
                    }
                }
            }
        }

        * Compute Bayes factor for this gamma level
        local log2_bf = 0
        if `is_null' {
            local gamma = -1
            * Neutral: log2(BF) = 0
        }
        else if `gamma' > 0 {
            local mk = `_comp_m_`k'_`gamma''
            local uk = `_comp_u_`k'_`gamma''
            if `uk' > 0 & `mk' > 0 {
                local log2_bf = ln(`mk' / `uk') / ln(2)
            }
        }
        else {
            * Else level (gamma=0): use level 0 m/u
            local mk = `_comp_m_`k'_0'
            local uk = `_comp_u_`k'_0'
            if "`mk'" != "" & "`uk'" != "" {
                if `uk' > 0 & `mk' > 0 {
                    local log2_bf = ln(`mk' / `uk') / ln(2)
                }
            }
        }

        local total_log2_bf = `total_log2_bf' + `log2_bf'

        * Truncate display values
        local dval_l = substr(`"`val_l'"', 1, 14)
        local dval_r = substr(`"`val_r'"', 1, 14)
        local gamma_display = "`gamma'"
        if `is_null' local gamma_display = "null"

        display as text "  " _col(3) "`vname'" ///
            _col(18) "`dval_l'" ///
            _col(34) "`dval_r'" ///
            _col(49) "`gamma_display'" ///
            _col(55) as result %8.3f `log2_bf'

        if "`verbose'" != "" & !`is_null' {
            if "`mk'" != "" & "`uk'" != "" {
                display as text "  " _col(8) "(m=`mk'  u=`uk')"
            }
        }
    }

    * Compute final match weight and probability
    local bf_prod = 2 ^ `total_log2_bf'
    local match_prob = (`lambda' * `bf_prod') / (`lambda' * `bf_prod' + (1 - `lambda'))

    display as text "  {hline 68}"
    display as text "  " _col(3) "Match weight (sum log2 BF):" ///
        _col(49) as result %12.3f `total_log2_bf'
    display as text "  " _col(3) "Prior (lambda):" ///
        _col(49) as result %12.6f `lambda'
    display as text "  " _col(3) "Match probability:" ///
        _col(49) as result %12.6f `match_prob'
    display as text "{hline 72}"

    * Return results
    return scalar match_weight = `total_log2_bf'
    return scalar match_probability = `match_prob'
    return scalar lambda = `lambda'
    return scalar n_comp = `n_comp'
end
