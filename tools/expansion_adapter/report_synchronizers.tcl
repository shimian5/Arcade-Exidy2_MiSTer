# Read-only reporting after a completed full project compile; not a build flow.
load_package sta
project_open expansion_probe
create_timing_netlist
read_sdc
update_timing_netlist
report_metastability -file synchronizers.rpt
delete_timing_netlist
project_close
