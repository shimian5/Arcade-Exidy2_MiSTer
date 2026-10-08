# Read-only post-fit timing diagnostic for the PIA snapshot FIFO.
# Run only after a completed full Quartus flow:
#   quartus_sta -t tools/timing/report_pia_fifo.tcl ?report-dir?
# No fitting, assembly, project assignment, or source mutation is performed.
# The script reloads only the project and system SDCs. It adds no timing
# exception or constraint; reports reflect exactly those loaded constraints.

load_package sta
if {$argc > 1} {
    error "Usage: quartus_sta -t tools/timing/report_pia_fifo.tcl ?report-dir?"
}
if {$argc == 1} {
    set report_dir [file normalize [lindex $argv 0]]
} else {
    set report_dir [file normalize "simulation/pia-fifo-timing"]
}
file mkdir $report_dir

project_open Arcade-Exidy2
create_timing_netlist
read_sdc Arcade-Exidy2.sdc
read_sdc sys/sys_top.sdc
update_timing_netlist

proc collection_count {collection} {
    return [get_collection_size $collection]
}

proc require_count {description collection expected} {
    set actual [collection_count $collection]
    if {$actual != $expected} {
        error "$description: expected $expected fitted objects, found $actual"
    }
    return $collection
}

proc require_range {description collection minimum maximum} {
    set actual [collection_count $collection]
    if {$actual < $minimum || $actual > $maximum} {
        error "$description: expected between $minimum and $maximum fitted objects, found $actual"
    }
    return $collection
}

proc pia_patterns {signal_pattern} {
    # The candidate and a production rename can use either module type while
    # retaining the same instance. Match either hierarchy, but cardinality
    # assertions below reject missing or duplicate modules.
    set patterns [list]
    foreach signal $signal_pattern {
        lappend patterns "*exidyPiaReturnFifo:*|$signal"
        lappend patterns "*exidyPiaReturn:*|$signal"
    }
    return $patterns
}

proc pia_registers {signal_pattern expected} {
    set collection [get_registers -nowarn [pia_patterns $signal_pattern]]
    return [require_count "PIA FIFO registers {$signal_pattern}" $collection $expected]
}

proc pia_keepers {signal_pattern expected} {
    set collection [get_keepers -nowarn [pia_patterns $signal_pattern]]
    return [require_count "PIA FIFO keepers {$signal_pattern}" $collection $expected]
}

proc report_pair {label from to npaths report_dir} {
    report_timing -setup -from $from -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-setup.rpt"]
    report_timing -hold -from $from -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-hold.rpt"]
}

proc report_async_pair {label from to npaths report_dir} {
    report_timing -recovery -from $from -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-recovery.rpt"]
    report_timing -removal -from $from -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-removal.rpt"]
}

proc report_async_to {label to npaths report_dir} {
    report_timing -recovery -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-recovery.rpt"]
    report_timing -removal -to $to -npaths $npaths -detail full_path \
        -file [file join $report_dir "$label-removal.rpt"]
}

set summary [open [file join $report_dir summary.txt] w]
puts $summary "Read-only PIA FIFO post-fit timing diagnostic"
puts $summary "Project SDCs: Arcade-Exidy2.sdc, sys/sys_top.sdc"
puts $summary "No inline timing constraints or exceptions are applied by this script."
puts $summary "If the loaded project SDC contains the FIFO's 20 ns max-delay bound, it is a bundled-data protocol bound distinct from the related PLL-edge setup/hold relationship. Confirm its presence and endpoints in exceptions.rpt."
puts $summary "FIFO data reports reflect the loaded project constraints; this script does not false-path the bundle."
puts $summary "These reports do not prove FIFO occupancy/overflow behavior, protocol correctness, or hardware metastability probability."
puts $summary ""

# Exact FIFO bundle and pointer collections. fifo_mem has four 9-bit words;
# destination captures are the 8 data bits plus the registered notification.
set fifo_mem [pia_keepers {fifo_mem*} 36]
set fifo_capture [pia_registers {main_byte_data* pending_notify_value} 9]
set write_gray [pia_registers {write_gray[*]} 3]
set write_gray_meta [pia_registers {write_gray_meta[*]} 3]
set write_gray_sync [pia_registers {write_gray_sync[*]} 3]
set read_gray [pia_registers {read_gray[*]} 3]
set read_gray_meta [pia_registers {read_gray_meta[*]} 3]
set read_gray_sync [pia_registers {read_gray_sync[*]} 3]

puts $summary "Resolved PIA FIFO collections: fifo_mem=[collection_count $fifo_mem] capture=[collection_count $fifo_capture]"
puts $summary "Gray pointer collections: write=[collection_count $write_gray] write_meta=[collection_count $write_gray_meta] write_sync=[collection_count $write_gray_sync] read=[collection_count $read_gray] read_meta=[collection_count $read_gray_meta] read_sync=[collection_count $read_gray_sync]"

# Reset conditioner selectors are reported without changing the loaded reset
# exceptions. Recovery/removal results must be read alongside exceptions.rpt.
set audio_reset_meta [pia_registers {audio_reset_meta} 1]
set audio_reset_release [pia_registers {audio_reset_release} 1]
set master_reset_meta [pia_registers {master_reset_meta} 1]
set master_reset_release [pia_registers {master_reset_release} 1]

# Global reports reflect only the project and system SDCs loaded above.
report_clocks -file [file join $report_dir clocks.rpt]
report_timing -setup -npaths 30 -detail full_path -file [file join $report_dir global-setup.rpt]
report_timing -hold -npaths 30 -detail full_path -file [file join $report_dir global-hold.rpt]
report_timing -recovery -npaths 30 -detail full_path -file [file join $report_dir global-recovery.rpt]
report_timing -removal -npaths 30 -detail full_path -file [file join $report_dir global-removal.rpt]

report_pair pia-fifo-bundle $fifo_mem $fifo_capture 324 $report_dir
puts $summary "Bundle hold report is the fitted minimum-delay check. A 20 ns set_max_delay, if present in the loaded project SDC, constrains setup only; it is not a hold allowance."
report_pair pia-write-gray-to-meta $write_gray $write_gray_meta 9 $report_dir
report_pair pia-read-gray-to-meta $read_gray $read_gray_meta 9 $report_dir
report_pair pia-write-gray-sync-stages $write_gray_meta $write_gray_sync 9 $report_dir
report_pair pia-read-gray-sync-stages $read_gray_meta $read_gray_sync 9 $report_dir

# Reset conditioner data stages are normally timed; only the asynchronous
# reset input to each first stage is excepted.
report_pair pia-audio-reset-meta-to-release $audio_reset_meta $audio_reset_release 1 $report_dir
report_pair pia-master-reset-meta-to-release $master_reset_meta $master_reset_release 1 $report_dir
set reset_conditioners [pia_registers {audio_reset_meta audio_reset_release master_reset_meta master_reset_release} 4]
report_async_to pia-conditioner-reset $reset_conditioners 8 $report_dir

# All resettable state groups are enumerated and cardinality-checked so local
# reset recovery/removal paths cannot silently disappear after hierarchy change.
set audio_state_core [require_range "PIA FIFO audio resettable state" \
    [get_registers -nowarn [pia_patterns {read_gray_meta[*] read_gray_sync[*] write_binary[*] write_gray[*] previous_snapshot[*]}]] 20 21]
set audio_overflow [get_registers -nowarn [pia_patterns {overflow_sticky}]]
if {[collection_count $audio_overflow] > 1} {
    error "PIA FIFO overflow state: expected zero or one fitted register, found [collection_count $audio_overflow]"
}
set master_state [require_range "PIA FIFO master resettable state" \
    [get_registers -nowarn [pia_patterns {write_gray_meta[*] write_gray_sync[*] read_binary[*] read_gray[*] main_byte_data[*] main_notify_data pending_notify pending_notify_value pop_cooldown}]] 23 24]
puts $summary "Resettable state counts: audio_core=[collection_count $audio_state_core] overflow=[collection_count $audio_overflow] master=[collection_count $master_state]"
report_async_pair pia-audio-release-to-state $audio_reset_release $audio_state_core 21 $report_dir
if {[collection_count $audio_overflow] == 1} {
    report_async_pair pia-audio-release-to-overflow $audio_reset_release $audio_overflow 1 $report_dir
}
report_async_pair pia-master-release-to-state $master_reset_release $master_state 24 $report_dir

# Destination FIFO output and its reset mask feed the main CPU's registered bus
# mux. This is ordinary same-master-domain setup/hold timing, separate from the
# source-array 20 ns bundled-data protocol bound, if present in the loaded SDC.
set main_byte_data [pia_registers {main_byte_data[*]} 8]
set cpu_input [require_count "main CPU input bus" \
    [get_registers -nowarn {*exidy2:ex2|CPU_databus_in[*]}] 8]
report_pair pia-fifo-output-to-cpu-input $main_byte_data $cpu_input 64 $report_dir
report_pair pia-reset-mask-to-cpu-input $master_reset_release $cpu_input 8 $report_dir

# Per-generated-counter domains prevent the global top-N report hiding a
# failure within any one counter-generated clock.
set clock_file [open [file join $report_dir counter-clock-periods.txt] w]
foreach name {BCLK PH_1 PH_6 auPH0 auPH0B} {
    set clock [get_clocks -nowarn $name]
    require_count "counter clock $name" $clock 1
    set period [get_clock_info -period $clock]
    puts $clock_file "$name period_ns=$period"
    report_timing -setup -to_clock $clock -npaths 20 -detail full_path \
        -file [file join $report_dir "$name-setup.rpt"]
    report_timing -hold -to_clock $clock -npaths 20 -detail full_path \
        -file [file join $report_dir "$name-hold.rpt"]
}
close $clock_file

# Required diagnostic reports. Command failures are fatal here: a missing
# report is not evidence of complete timing coverage.
report_metastability -file [file join $report_dir metastability.rpt]
check_timing -file [file join $report_dir check-timing.rpt]
report_exceptions -file [file join $report_dir exceptions.rpt]

puts $summary "PASS: all required FIFO/reset/counter collections matched expected cardinality."
close $summary
delete_timing_netlist
project_close
puts "PIA FIFO reports written to $report_dir"
