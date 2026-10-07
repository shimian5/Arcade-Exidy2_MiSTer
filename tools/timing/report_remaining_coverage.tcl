# Read-only post-fit clock/event and PIA-path diagnostic.
# Usage, from project root after a completed full Quartus flow:
#   quartus_sta -t tools/timing/report_remaining_coverage.tcl ?report-dir?
# This script does not alter SDC, apply exceptions, or fit/assemble the design.

load_package sta
if {$argc > 1} { error "Usage: quartus_sta -t tools/timing/report_remaining_coverage.tcl ?report-dir?" }
if {$argc == 1} {
    set report_dir [file normalize [lindex $argv 0]]
} else {
    set report_dir [file normalize "simulation/timing-remaining-coverage"]
}
file mkdir $report_dir

project_open Arcade-Exidy2
create_timing_netlist
read_sdc Arcade-Exidy2.sdc
read_sdc sys/sys_top.sdc
update_timing_netlist

proc object_name {object type} {
    if {$type eq "register"} { return [get_register_info -name $object] }
    if {$type eq "pin"} { return [get_node_info -name $object] }
    if {$type eq "clock"} { return [get_clock_info -name $object] }
    error "unknown object type $type"
}

set summary [open [file join $report_dir coverage-summary.txt] w]
puts $summary "Read-only post-fit coverage diagnostic"
puts $summary "Project SDCs: Arcade-Exidy2.sdc, sys/sys_top.sdc"
puts $summary ""

# A clock declaration does not prove every sequential pin has a clock or that
# exceptions are safe. This inventory records only resolved clock objects.
report_clocks -file [file join $report_dir clocks.rpt]
puts $summary "Resolved clocks:"
foreach_in_collection clock [all_clocks] {
    puts $summary "  [get_clock_info -name $clock] period_ns=[get_clock_info -period $clock]"
}

# Source-derived endpoint inventory. These selectors are diagnostic only; they
# do not declare generated clocks or timing exceptions.
set endpoint_specs [list \
    [list cpu_write_events {*|exidy2:ex2|rM1H* *|exidy2:ex2|rM1V* *|exidy2:ex2|rM2H* *|exidy2:ex2|rM2V* *|exidy2:ex2|M1R* *|exidy2:ex2|M2R* *|exidy2:ex2|CPL* *|exidy2:ex2|ADSEL*}] \
    [list raster_events {*|exidy2:ex2|M1V* *|exidy2:ex2|M2V* *|exidy2:ex2|col_cap*}] \
    [list sprite_shift_state {*|exidy2:ex2|U13D_M1VA|shift_register* *|exidy2:ex2|U12D_M1VA|shift_register* *|exidy2:ex2|U15D_M1VA|shift_register* *|exidy2:ex2|U14D_M1VA|shift_register*}] \
    [list irq_event_state {*|exidy2:ex2|rCPU_IRQ* *|exidy2:ex2|EIR*}] \
    [list audio_event_state {*|exidyAB:sound_board|WODD_LATCH* *|exidyAB:sound_board|WEVEN_LATCH* *|exidyAB:sound_board|U2A_counter* *|exidyAB:sound_board|U3AB_counter* *|exidyAB:sound_board|TONE_out*}] \
    [list pia_data_valid {*|exidyPiaReturn:pia_return_data|audio_byte_stage* *|exidyPiaReturn:pia_return_data|main_byte_data* *|exidyPiaReturn:pia_return_data|main_byte_valid}]]

puts $summary ""
puts $summary "Sequential endpoint matches (counts are diagnostic, not assertions):"
set inventory_file [open [file join $report_dir sequential-endpoints.txt] w]
foreach spec $endpoint_specs {
    lassign $spec label patterns
    set unique_names [list]
    foreach pattern $patterns {
        foreach_in_collection reg [get_registers -nowarn $pattern] {
            set name [object_name $reg register]
            if {[lsearch -exact $unique_names $name] < 0} { lappend unique_names $name }
        }
    }
    puts $summary "  $label count=[llength $unique_names]"
    puts $inventory_file "$label count=[llength $unique_names]"
    foreach name $unique_names {
        puts $inventory_file "  $name"
    }
}

close $inventory_file

# Resolve the wildcard group patterns from the SDC against post-fit clock
# objects. This reports collection membership only; it does not test all path
# reach or prove the functional correctness of exclusive/asynchronous groups.
set group_file [open [file join $report_dir clock-group-members.txt] w]
set group_specs [list \
    [list root_plls {*|pll|pll_inst|altera_pll_i|*[*].*|divclk}] \
    [list hdmi_pll {pll_hdmi|pll_hdmi_inst|altera_pll_i|*[0].*|divclk}] \
    [list audio_pll {pll_audio|pll_audio_inst|altera_pll_i|*[0].*|divclk}] \
    [list spi {spi_sck}] \
    [list hdmi {hdmi_sck}] \
    [list h2f {*|h2f_user0_clk}] \
    [list fpga1 {FPGA_CLK1_50}] \
    [list fpga2 {FPGA_CLK2_50}] \
    [list fpga3 {FPGA_CLK3_50}]]
foreach spec $group_specs {
    lassign $spec label pattern
    set matches [get_clocks -nowarn $pattern]
    set names [list]
    foreach_in_collection clock $matches {
        lappend names [get_clock_info -name $clock]
    }
    puts $group_file "$label pattern={$pattern} count=[llength $names] members={$names}"
}
close $group_file

# Keep the complete byte path timed. Report the source-to-destination data
# transfer plus the master-domain validity mask/read path and reset recovery.
set pia_audio [get_registers -nowarn {*exidyPiaReturn:pia_return_data|audio_byte_stage*}]
set pia_main [get_registers -nowarn {*exidyPiaReturn:pia_return_data|main_byte_data*}]
set pia_valid [get_registers -nowarn {*exidyPiaReturn:pia_return_data|main_byte_valid}]
set cpu_input [get_registers -nowarn {*exidy2:ex2|CPU_databus_in*}]
puts $summary ""
puts $summary "PIA register collection sizes: audio_byte_stage=[get_collection_size $pia_audio] main_byte_data=[get_collection_size $pia_main] main_byte_valid=[get_collection_size $pia_valid] CPU_databus_in=[get_collection_size $cpu_input]"
if {[get_collection_size $pia_audio] == 8 && [get_collection_size $pia_main] == 8} {
    report_timing -setup -from $pia_audio -to $pia_main -npaths 8 -detail full_path -file [file join $report_dir pia-data-setup.rpt]
    report_timing -hold -from $pia_audio -to $pia_main -npaths 8 -detail full_path -file [file join $report_dir pia-data-hold.rpt]
} else {
    puts $summary "  PIA data reports skipped: expected eight source and eight destination registers."
}
if {[get_collection_size $pia_valid] == 1} {
    report_timing -recovery -to $pia_valid -npaths 1 -detail full_path -file [file join $report_dir pia-valid-recovery.rpt]
    report_timing -removal -to $pia_valid -npaths 1 -detail full_path -file [file join $report_dir pia-valid-removal.rpt]
    if {[get_collection_size $cpu_input] == 8} {
        report_timing -setup -from $pia_valid -to $cpu_input -npaths 8 -detail full_path -file [file join $report_dir pia-valid-read-setup.rpt]
        report_timing -hold -from $pia_valid -to $cpu_input -npaths 8 -detail full_path -file [file join $report_dir pia-valid-read-hold.rpt]
    }
} else {
    puts $summary "  PIA validity reports skipped: expected one valid register."
}

# Optional commands differ by Quartus release. Availability and execution
# failures are recorded explicitly; neither is treated as a clean result.
foreach pair [list \
    [list check_timing [list -file [file join $report_dir check-timing.rpt]]] \
    [list report_exceptions [list -file [file join $report_dir exceptions.rpt]]] \
    [list report_sdc [list -file [file join $report_dir applied-sdc.rpt]]]] {
    lassign $pair command args
    if {[llength [info commands $command]] == 0} {
        puts $summary "Optional report unavailable: command $command not present."
    } elseif {[catch {$command {*}$args} err]} {
        puts $summary "Optional report failed: command $command: $err"
    } else {
        puts $summary "Optional report generated: $command"
    }
}

close $summary
delete_timing_netlist
project_close
puts "Coverage diagnostics written to $report_dir"
