*! version 4.1.0  28feb2026
*! Cluster-level evaluation metrics for record linkage
*! Computes purity, completeness, and cluster F1 from true entity labels

program define splink_cluster_metrics, rclass
    version 14.0

    syntax, PREDicted(varname) TRUE(varname)

    preserve

    * Compute cluster purity: fraction of dominant true entity per predicted cluster
    quietly {
        tempvar max_count cluster_size
        bysort `predicted' `true': gen long _n_pair = _N
        bysort `predicted': egen long `max_count' = max(_n_pair)
        bysort `predicted': egen long `cluster_size' = count(_n_pair)
        bysort `predicted': gen byte _first = (_n == 1)
    }

    * Purity = sum(max_count for each predicted cluster) / N
    quietly {
        tempvar purity_contrib
        gen double `purity_contrib' = `max_count' / _N if _first
        summarize `purity_contrib', meanonly
        local total_purity_num = r(sum) * _N
    }
    local purity = `total_purity_num' / _N

    * Completeness: fraction of dominant predicted cluster per true entity
    quietly {
        tempvar max_count_rev true_size
        bysort `true' `predicted': gen long _n_pair_rev = _N
        bysort `true': egen long `max_count_rev' = max(_n_pair_rev)
        bysort `true': egen long `true_size' = count(_n_pair_rev)
        bysort `true': gen byte _first_true = (_n == 1)

        tempvar comp_contrib
        gen double `comp_contrib' = `max_count_rev' / _N if _first_true
        summarize `comp_contrib', meanonly
        local total_comp_num = r(sum) * _N
    }
    local completeness = `total_comp_num' / _N

    * Cluster F1
    local cluster_f1 = 0
    if `purity' + `completeness' > 0 {
        local cluster_f1 = 2 * `purity' * `completeness' / (`purity' + `completeness')
    }

    * Count clusters
    quietly {
        tempvar pred_tag true_tag
        egen `pred_tag' = tag(`predicted')
        egen `true_tag' = tag(`true')
        count if `pred_tag'
        local n_pred_clusters = r(N)
        count if `true_tag'
        local n_true_clusters = r(N)
    }

    restore

    * Display
    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Cluster Evaluation"
    display as text "{hline 50}"
    display as text "  Predicted clusters: " as result %10.0fc `n_pred_clusters'
    display as text "  True entities:      " as result %10.0fc `n_true_clusters'
    display as text "{hline 50}"
    display as text "  Purity:             " as result %10.6f `purity'
    display as text "  Completeness:       " as result %10.6f `completeness'
    display as text "  Cluster F1:         " as result %10.6f `cluster_f1'
    display as text "{hline 50}"

    * Return
    return scalar purity = `purity'
    return scalar completeness = `completeness'
    return scalar cluster_f1 = `cluster_f1'
    return scalar n_pred_clusters = `n_pred_clusters'
    return scalar n_true_clusters = `n_true_clusters'
end
