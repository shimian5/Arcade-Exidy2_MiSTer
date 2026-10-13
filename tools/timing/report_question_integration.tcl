# Read-only actual question-memory to CPU timing diagnostic, after a full flow.
# No constraints or exceptions are added.
project_open Arcade-Exidy2
create_timing_netlist
read_sdc
update_timing_netlist
if {$argc > 1} {error "Usage: report_question_integration.tcl ?report-dir?"}
set report_dir simulation/timing-question-integration
if {$argc == 1} {set report_dir [file normalize [lindex $argv 0]]}
file mkdir $report_dir
set banks [get_registers -nowarn {*|FAX_QUESTIONS|question_bank[*]}]
if {[get_collection_size $banks] != 5} {error "Expected five fitted FAX bank bits"}
set cpu [get_registers -nowarn {*|ex2|CPU_databus_in[*]}]
if {[get_collection_size $cpu] != 8} {error "Expected eight fitted CPU read-mux bits"}
set question [get_keepers -nowarn {*question_mem*}]
if {[get_collection_size $question] == 0} {error "No fitted question-memory endpoints"}
report_timing -setup -from $question -to $cpu -npaths 16 -detail full_path -file [file join $report_dir question-to-cpu-setup.rpt]
report_timing -hold -from $question -to $cpu -npaths 16 -detail full_path -file [file join $report_dir question-to-cpu-hold.rpt]
report_timing -setup -from $banks -to $question -npaths 16 -detail full_path -file [file join $report_dir bank-to-question-setup.rpt]
report_timing -hold -from $banks -to $question -npaths 16 -detail full_path -file [file join $report_dir bank-to-question-hold.rpt]
puts "QUESTION_GUARDS bank_bits=[get_collection_size $banks] cpu_mux_bits=[get_collection_size $cpu] memory_endpoints=[get_collection_size $question]"
project_close
