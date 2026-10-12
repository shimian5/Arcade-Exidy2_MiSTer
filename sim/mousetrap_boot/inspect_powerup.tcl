# Read-only Quartus CDB audit of the mapped T80 register-bank FF power-up flags.
# Run from the project root with:
# quartus_cdb -t sim/mousetrap_boot/inspect_powerup.tcl Arcade-Exidy2
project_open -revision Arcade-Exidy2 Arcade-Exidy2
load_package atoms
read_atom_netlist -type map

set count 0
set powers_up 0
set dont_care 0
puts "name,powers_up,power_up_dont_care"
foreach_in_collection atom [get_atom_nodes -type FF] {
    set name [get_atom_node_info -node $atom -key NAME]
    if {[string match *mousetrapSpeechSubsystem* $name] &&
        ([string match *RegsH* $name] || [string match *RegsL* $name])} {
        set powers [get_atom_node_info -node $atom -key BOOL_POWERS_UP]
        set unspecified [get_atom_node_info -node $atom -key BOOL_POWER_UP_DONT_CARE]
        puts "$name,$powers,$unspecified"
        incr count
        if {$powers} { incr powers_up }
        if {$unspecified} { incr dont_care }
    }
}
puts "SUMMARY count=$count powers_up=$powers_up power_up_dont_care=$dont_care"
if {$count != 128 || $powers_up != 0 || $dont_care != 128} {
    error "Unexpected T80 mapped register-bank power-up flags"
}
project_close
