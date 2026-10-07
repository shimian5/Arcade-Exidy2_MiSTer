# Read-only fitted register/site inventory for a completed full flow.
# Usage from project root:
#   quartus_sta -t tools/timing/inventory_register_sites.tcl ?report-dir?
# Output is diagnostic only; this script does not edit constraints or fit.

load_package sta
if {$argc > 1} { error "Usage: quartus_sta -t tools/timing/inventory_register_sites.tcl ?report-dir?" }
if {$argc == 1} {
    set report_dir [file normalize [lindex $argv 0]]
} else {
    set report_dir [file normalize "simulation/timing-register-sites"]
}
file mkdir $report_dir

project_open Arcade-Exidy2
create_timing_netlist
read_sdc Arcade-Exidy2.sdc
read_sdc sys/sys_top.sdc
update_timing_netlist

set sites_file [open [file join $report_dir fitted-register-sites.tsv] w]
puts $sites_file "register_name\tlocation"
set site_failures 0
set register_count 0
set regs [get_registers *]
foreach_in_collection reg $regs {
    incr register_count
    set name [get_register_info -name $reg]
    if {[catch {set location [get_node_info -location $reg]} err]} {
        incr site_failures
        puts $sites_file "$name\tQUERY_ERROR:$err"
    } elseif {$location eq ""} {
        puts $sites_file "$name\tNO_LOCATION"
    } else {
        puts $sites_file "$name\t$location"
    }
}
close $sites_file

set pia_file [open [file join $report_dir pia-return-sites.txt] w]
foreach pattern [list \
    {*exidyPiaReturn:pia_return_data|audio_byte_stage*} \
    {*exidyPiaReturn:pia_return_data|main_byte_data*}] {
    foreach_in_collection reg [get_registers -nowarn $pattern] {
        set name [get_register_info -name $reg]
        if {[catch {set location [get_node_info -location $reg]} err]} {
            puts $pia_file "$name location_query_error={$err}"
        } else {
            puts $pia_file "$name location={$location}"
        }
    }
}
close $pia_file

delete_timing_netlist
project_close
puts "Wrote $register_count register locations to [file join $report_dir fitted-register-sites.tsv]; query_failures=$site_failures"
