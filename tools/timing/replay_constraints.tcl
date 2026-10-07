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
foreach_in_collection clock [get_clocks *] {
    set clock_name [get_clock_info -name $clock]
    if {[string first {emu|pll|} $clock_name] == 0 && [string first {general[2]} $clock_name] >= 0 && [string match {*divclk} $clock_name]} {
        report_timing -setup -to_clock $clock -npaths 8 -detail full_path -file [file join $report_dir audio-setup.rpt]
    }
}
# Report each constrained divider domain separately so global top-eight
# paths cannot hide another board clock's setup/hold behavior.
foreach name {BCLK PH_1 PH_6 auPH0 auPH0B} {
    set domain [get_clocks -nowarn $name]
    if {[get_collection_size $domain] == 1} {
        report_timing -setup -to_clock $domain -npaths 8 -detail full_path -file [file join $report_dir "$name-setup.rpt"]
        report_timing -hold -to_clock $domain -npaths 8 -detail full_path -file [file join $report_dir "$name-hold.rpt"]
    }
}
set pause_meta [get_registers -nowarn {*exidyPauseSync:audio_pause|pause_meta}]
set pause_sync [get_registers -nowarn {*exidyPauseSync:audio_pause|pause_sync}]
if {[get_collection_size $pause_meta] == 1 && [get_collection_size $pause_sync] == 1} {
    report_timing -setup -from $pause_meta -to $pause_sync -npaths 1 -detail full_path -file [file join $report_dir pause-stage-setup.rpt]
    report_timing -hold -from $pause_meta -to $pause_sync -npaths 1 -detail full_path -file [file join $report_dir pause-stage-hold.rpt]
}
report_metastability -file [file join $report_dir metastability.rpt]
delete_timing_netlist
project_close
