*! version 4.1.0  28feb2026
*! Interactive cluster visualization via HTML/D3.js
*! Opens a force-directed graph of a single cluster in the system browser

program define splink_cluster_studio
    version 14.0

    syntax using/, CLuster(string) CLUSTERVar(string) [THReshold(real 0.5) ///
        OUTFile(string)]

    preserve
    quietly import delimited `using', clear

    capture confirm variable match_probability
    if _rc {
        display as error "CSV must contain match_probability column"
        restore
        exit 198
    }
    capture confirm variable match_weight
    if _rc {
        quietly gen double match_weight = ln(match_probability / (1 - match_probability)) / ln(2)
    }

    capture confirm variable `clustervar'
    if _rc {
        display as error "cluster variable `clustervar' not found in CSV"
        restore
        exit 198
    }

    quietly {

        * Determine ID columns
        local id_l "unique_id_l"
        local id_r "unique_id_r"
        capture confirm variable unique_id_l
        if _rc {
            local id_l "obs_a"
            local id_r "obs_b"
        }

        * Filter to target cluster and threshold
        capture confirm string variable `clustervar'
        if _rc == 0 {
            keep if `clustervar' == "`cluster'"
        }
        else {
            keep if `clustervar' == real("`cluster'")
        }
        keep if match_probability >= `threshold'

        local n_edges = _N
        if `n_edges' == 0 {
            display as error "no pairs found for cluster `cluster' above threshold `threshold'"
            restore
            exit 198
        }

        * Build JSON data for D3
        * Collect unique nodes
        * Note: O(N²) dedup via nested loop; functional but slow for large clusters.
        * Could optimize with levelsof on stacked id_l/id_r column.
        local nodes ""
        local n_nodes = 0

        forvalues i = 1/`n_edges' {
            local left = `id_l'[`i']
            local right = `id_r'[`i']

            * Check if left node already seen
            local found = 0
            forvalues j = 1/`n_nodes' {
                if "`_node_`j''" == "`left'" {
                    local found = 1
                }
            }
            if !`found' {
                local n_nodes = `n_nodes' + 1
                local _node_`n_nodes' = "`left'"
            }

            * Check if right node already seen
            local found = 0
            forvalues j = 1/`n_nodes' {
                if "`_node_`j''" == "`right'" {
                    local found = 1
                }
            }
            if !`found' {
                local n_nodes = `n_nodes' + 1
                local _node_`n_nodes' = "`right'"
            }
        }

        * Build edges JSON
        local edges_json ""
        forvalues i = 1/`n_edges' {
            local left = `id_l'[`i']
            local right = `id_r'[`i']
            local prob = match_probability[`i']
            local wt = match_weight[`i']

            * Find source/target indices
            local src = 0
            local tgt = 0
            forvalues j = 1/`n_nodes' {
                if "`_node_`j''" == "`left'" local src = `j' - 1
                if "`_node_`j''" == "`right'" local tgt = `j' - 1
            }

            if `i' > 1 local edges_json `"`edges_json',"'
            local edges_json `"`edges_json'{"source":`src',"target":`tgt',"prob":`:display %6.4f `prob'',"weight":`:display %6.2f `wt''}"'
        }

        * Build nodes JSON
        local nodes_json ""
        forvalues j = 1/`n_nodes' {
            if `j' > 1 local nodes_json `"`nodes_json',"'
            local nodes_json `"`nodes_json'{"id":"`_node_`j''","label":"`_node_`j''"}"'
        }
    }

    * Determine output file
    if `"`outfile'"' == "" {
        tempfile htmlfile
        local outfile = "`htmlfile'.html"
    }

    * Write HTML file
    tempname fh
    file open `fh' using `"`outfile'"', write text replace

    file write `fh' `"<!DOCTYPE html>"' _n
    file write `fh' `"<html><head><meta charset="utf-8">"' _n
    file write `fh' `"<title>Splink Cluster Studio - Cluster `cluster'</title>"' _n
    file write `fh' `"<style>"' _n
    file write `fh' `"body { font-family: -apple-system, sans-serif; margin: 0; background: #f8f9fa; }"' _n
    file write `fh' `"h2 { text-align: center; color: #333; padding: 16px; margin: 0; }"' _n
    file write `fh' `".info { text-align: center; color: #666; font-size: 14px; }"' _n
    file write `fh' `"svg { display: block; margin: 0 auto; background: white; border: 1px solid #ddd; }"' _n
    file write `fh' `".node circle { stroke: #fff; stroke-width: 2px; cursor: pointer; }"' _n
    file write `fh' `".node text { font-size: 11px; fill: #333; pointer-events: none; }"' _n
    file write `fh' `".link { stroke-opacity: 0.6; }"' _n
    file write `fh' `".tooltip { position: absolute; background: rgba(0,0,0,0.8); color: white; "' _n
    file write `fh' `"  padding: 8px 12px; border-radius: 4px; font-size: 12px; pointer-events: none; }"' _n
    file write `fh' `"</style>"' _n
    file write `fh' `"<script src="https://d3js.org/d3.v7.min.js"></script>"' _n
    file write `fh' `"</head><body>"' _n
    file write `fh' `"<h2>Cluster `cluster'</h2>"' _n
    file write `fh' `"<p class="info">`n_nodes' nodes, `n_edges' edges (threshold >= `threshold')</p>"' _n
    file write `fh' `"<div id="chart"></div>"' _n
    file write `fh' `"<div class="tooltip" id="tooltip" style="display:none"></div>"' _n
    file write `fh' `"<script>"' _n
    file write `fh' `"const data = {"' _n
    file write `fh' `"  nodes: [`nodes_json'],"' _n
    file write `fh' `"  links: [`edges_json']"' _n
    file write `fh' `"};"' _n
    file write `fh' `"const w = 800, h = 600;"' _n
    file write `fh' `"const svg = d3.select('#chart').append('svg').attr('width',w).attr('height',h);"' _n
    file write `fh' `"const color = d3.scaleSequential(d3.interpolateRdYlGn).domain([0,1]);"' _n
    file write `fh' `"const sim = d3.forceSimulation(data.nodes)"' _n
    file write `fh' `"  .force('link', d3.forceLink(data.links).id((d,i)=>i).distance(80))"' _n
    file write `fh' `"  .force('charge', d3.forceManyBody().strength(-200))"' _n
    file write `fh' `"  .force('center', d3.forceCenter(w/2, h/2));"' _n
    file write `fh' `"const link = svg.selectAll('.link').data(data.links).join('line')"' _n
    file write `fh' `"  .attr('class','link').style('stroke',d=>color(d.prob))"' _n
    file write `fh' `"  .style('stroke-width',d=>Math.max(1,d.prob*5));"' _n
    file write `fh' `"const node = svg.selectAll('.node').data(data.nodes).join('g')"' _n
    file write `fh' `"  .attr('class','node').call(d3.drag()"' _n
    file write `fh' `"  .on('start',ds).on('drag',dd).on('end',de));"' _n
    file write `fh' `"node.append('circle').attr('r',10).style('fill','#4a90d9');"' _n
    file write `fh' `"node.append('text').attr('dx',14).attr('dy',4).text(d=>d.label);"' _n
    file write `fh' `"const tip = d3.select('#tooltip');"' _n
    file write `fh' `"link.on('mouseover',(e,d)=>{ tip.style('display','block')"' _n
    file write `fh' `"  .html('Prob: '+d.prob+'<br>Weight: '+d.weight)"' _n
    file write `fh' `"  .style('left',(e.pageX+10)+'px').style('top',(e.pageY-10)+'px');})"' _n
    file write `fh' `"  .on('mouseout',()=>tip.style('display','none'));"' _n
    file write `fh' `"sim.on('tick',()=>{"' _n
    file write `fh' `"  link.attr('x1',d=>d.source.x).attr('y1',d=>d.source.y)"' _n
    file write `fh' `"      .attr('x2',d=>d.target.x).attr('y2',d=>d.target.y);"' _n
    file write `fh' `"  node.attr('transform',d=>'translate('+d.x+','+d.y+')');"' _n
    file write `fh' `"});"' _n
    file write `fh' `"function ds(e,d){if(!e.active)sim.alphaTarget(.3).restart();d.fx=d.x;d.fy=d.y;}"' _n
    file write `fh' `"function dd(e,d){d.fx=e.x;d.fy=e.y;}"' _n
    file write `fh' `"function de(e,d){if(!e.active)sim.alphaTarget(0);d.fx=null;d.fy=null;}"' _n
    file write `fh' `"</script></body></html>"' _n

    file close `fh'

    restore

    * Open in browser
    if "`c(os)'" == "MacOSX" {
        shell open `"`outfile'"'
    }
    else if "`c(os)'" == "Windows" {
        winexec cmd /c start "" `"`outfile'"'
    }
    else {
        shell xdg-open `"`outfile'"'
    }

    display as text ""
    display as text "Cluster studio opened in browser."
    display as text "  Cluster:    `cluster'"
    display as text "  Nodes:      `n_nodes'"
    display as text "  Edges:      `n_edges'"
    display as text "  Threshold:  `threshold'"
    display as text "  File:       `outfile'"
end
