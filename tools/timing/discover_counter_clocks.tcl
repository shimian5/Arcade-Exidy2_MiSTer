# Read-only post-fit discovery for the five registered divider pulse clocks.
# Run only after the full project flow has completed:
#   quartus_sta -t tools/timing/discover_counter_clocks.tcl [report-dir]
# This script never evaluates the generated candidate SDC it writes.

load_package sta
if {$argc > 1} { error "Usage: quartus_sta -t tools/timing/discover_counter_clocks.tcl ?report-dir?" }
if {$argc == 1} {
    set report_dir [file normalize [lindex $argv 0]]
} else {
    set report_dir [file normalize "simulation/timing-counter-clocks"]
}
file mkdir $report_dir

project_open Arcade-Exidy2
create_timing_netlist
read_sdc Arcade-Exidy2.sdc
read_sdc sys/sys_top.sdc
update_timing_netlist

proc collection_items {collection} {
    set items [list]
    foreach_in_collection item $collection { lappend items $item }
    return $items
}

proc require_one {description collection} {
    set items [collection_items $collection]
    if {[llength $items] != 1} {
        error "$description: expected exactly one object, found [llength $items]"
    }
    return [lindex $items 0]
}

proc object_name {object type} {
    if {$type eq "register"} { return [get_register_info -name $object] }
    if {$type eq "pin"} { return [get_node_info -name $object] }
    if {$type eq "clock"} { return [get_clock_info -name $object] }
    error "unknown object type $type"
}

proc find_q_pin {keeper_name leaf} {
    # Quartus fitter names commonly expose a register output as <keeper>|q;
    # keep exact-leaf fallbacks visible because atom pin spelling varies by
    # fitter/version. Deduplicate pin names before enforcing singleton.
    set patterns [list \
        "${keeper_name}|q" \
        "${keeper_name}|Q" \
        "${keeper_name}~reg*|q" \
        "${keeper_name}~DFF*|q" \
        "*|${leaf}~reg*|q" \
        "*|${leaf}~DFF*|q" \
        "*|${leaf}|q" \
        "*|${leaf}"]
    set found_names [list]
    foreach pattern $patterns {
        set pins [get_pins -nowarn -hierarchical $pattern]
        foreach_in_collection pin $pins {
            set name [get_node_info -name $pin]
            if {[lsearch -exact $found_names $name] < 0} { lappend found_names $name }
        }
    }
    if {[llength $found_names] != 1} {
        error "Q pin for $keeper_name: expected one unique fitted pin, found [llength $found_names]; candidates={$found_names}"
    }
    return [lindex $found_names 0]
}

proc find_parent_clock {source_pin_name description} {
    # Quartus 17's local TimeQuest Tcl implementation uses
    # get_clock_info -targets (qsta_ss_constrainer.tcl) to map target nodes to
    # clocks. Avoid assuming the pin and clock object share a name or relying
    # on Synopsys-style get_clocks -of_objects syntax.
    set matches [list]
    foreach_in_collection clock [all_clocks] {
        if {[catch {set targets [get_clock_info -targets $clock]}]} { continue }
        foreach_in_collection target $targets {
            if {[get_node_info -name $target] eq $source_pin_name} {
                lappend matches $clock
                break
            }
        }
    }
    if {[llength $matches] != 1} {
        error "$description parent clock targeting $source_pin_name: expected exactly one object, found [llength $matches]"
    }
    return [lindex $matches 0]
}

set specs [list \
    [list BCLK  {*|exidy2:ex2|BCLK}  {*|pll|pll_inst|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk} {1 3 17}] \
    [list PH_1  {*|exidy2:ex2|PH_1}  {*|pll|pll_inst|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk} {63 65 191}] \
    [list PH_6  {*|exidy2:ex2|PH_6}  {*|pll|pll_inst|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk} {1 3 129}] \
    [list auPH0 {*|exidyAB:sound_board|auPH0} {*|pll|pll_inst|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} {1 3 33}] \
    [list auPH0B {*|exidyAB:sound_board|auPH0B} {*|pll|pll_inst|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk} {3 5 35}]]

set detail_file [open [file join $report_dir discovery.txt] w]
set candidate_file [open [file join $report_dir candidate-counter-clocks.sdc.txt] w]
puts $candidate_file "# Diagnostic candidates only. This file is not sourced or applied by the script."
puts $candidate_file "# Review target/source pin names, parent clocks, edge waveforms, and report_clocks before any SDC change."
report_clocks -file [file join $report_dir existing-clocks.rpt]

foreach spec $specs {
    lassign $spec clock_name reg_pattern source_pattern edges
    set keeper_collection [get_registers -nowarn -hierarchical $reg_pattern]
    set keeper [require_one "$clock_name register selector $reg_pattern" $keeper_collection]
    set keeper_name [object_name $keeper register]
    set leaf [lindex [split $keeper_name |] end]
    set q_pin_name [find_q_pin $keeper_name $leaf]
    set q_pin_collection [get_pins -nowarn -hierarchical $q_pin_name]
    set q_pin [require_one "$clock_name fitted Q pin $q_pin_name" $q_pin_collection]

    set source_collection [get_pins -nowarn -hierarchical $source_pattern]
    set source_pin [require_one "$clock_name PLL output source $source_pattern" $source_collection]
    set source_pin_name [object_name $source_pin pin]
    set parent_clock [find_parent_clock $source_pin_name $clock_name]
    set parent_name [object_name $parent_clock clock]

    puts $detail_file "clock=$clock_name"
    puts $detail_file "  register=$keeper_name"
    puts $detail_file "  q_pin=$q_pin_name"
    puts $detail_file "  source_pin=$source_pin_name"
    puts $detail_file "  parent_clock=$parent_name period_ns=[get_clock_info -period $parent_clock]"
    puts $detail_file "  edges={$edges}"
    puts $candidate_file [format {create_generated_clock -name {%s} -source [get_pins {%s}] -master_clock [get_clocks {%s}] -edges {%s} [get_pins {%s}]} \
        $clock_name $source_pin_name $parent_name $edges $q_pin_name]
    puts "DISCOVERED $clock_name: register=$keeper_name Q=$q_pin_name parent=$parent_name edges={$edges}"
}

close $detail_file
close $candidate_file
delete_timing_netlist
project_close
puts "PASS discovered five unique register/Q/source/parent collections; candidates are diagnostic only: [file join $report_dir candidate-counter-clocks.sdc.txt]"
