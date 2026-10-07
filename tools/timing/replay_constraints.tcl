# Read-only diagnosis of an already completed full-flow build.
# Usage: quartus_sta -t tools/timing/replay_constraints.tcl <root-sdc> <report-dir>
# This does not fit or assemble a design and is not build acceptance.
load_package sta
if {$argc != 2} { error "Expected root SDC path and report directory" }
set candidate_sdc [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
project_open Arcade-Exidy2
create_timing_netlist
read_sdc $candidate_sdc
read_sdc sys/sys_top.sdc
update_timing_netlist
set clock_file [open [file join $report_dir clocks.txt] w]
foreach_in_collection clock [get_clocks *] {
    puts $clock_file "[get_clock_info -name $clock] : [get_clock_info -period $clock] ns"
}
close $clock_file
report_timing -setup -npaths 8 -detail full_path -file [file join $report_dir setup.rpt]
report_timing -hold -npaths 8 -detail full_path -file [file join $report_dir hold.rpt]
delete_timing_netlist
project_close
