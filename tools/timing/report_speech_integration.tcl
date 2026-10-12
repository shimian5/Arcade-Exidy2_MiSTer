# Read-only post-fit timing/resource diagnostic for the Mouse Trap speech join.
# Run only after a completed full Quartus flow:
#   quartus_sta -t tools/timing/report_speech_integration.tcl ?report-dir?
# This reloads the normal project SDCs and adds no constraints or exceptions.

load_package sta
if {$argc > 1} {
    error "Usage: quartus_sta -t tools/timing/report_speech_integration.tcl ?report-dir?"
}
if {$argc == 1} {
    set report_dir [file normalize [lindex $argv 0]]
} else {
    set report_dir [file normalize "simulation/timing-speech-integration"]
}
file mkdir $report_dir

project_open Arcade-Exidy2
create_timing_netlist
read_sdc Arcade-Exidy2.sdc
read_sdc sys/sys_top.sdc
update_timing_netlist

proc require_count {description collection expected} {
    set actual [get_collection_size $collection]
    if {$actual != $expected} {
        error "$description: expected $expected fitted objects, found $actual"
    }
    return $collection
}

proc require_minimum {description collection minimum} {
    set actual [get_collection_size $collection]
    if {$actual < $minimum} {
        error "$description: expected at least $minimum fitted objects, found $actual"
    }
    return $collection
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

proc report_register_pair {label from_pattern to_pattern report_dir} {
    set from [require_count "$label source" [get_registers -nowarn $from_pattern] 1]
    set to [require_count "$label destination" [get_registers -nowarn $to_pattern] 1]
    report_pair $label $from $to 1 $report_dir
    return [list $from $to]
}

set summary [open [file join $report_dir summary.txt] w]
puts $summary "Read-only post-fit Mouse Trap speech integration diagnostic"
puts $summary "Project SDCs: Arcade-Exidy2.sdc, sys/sys_top.sdc"
puts $summary "No constraints or exceptions are added by this report script."
puts $summary "Existing no_clock RIOT/auPH0 treatment remains the separate documented audio-clock limitation."
puts $summary "check_timing.rpt and exceptions.rpt are required outputs; inspect their no-clock, multiple-clock, latch/loop and exception summaries."
puts $summary ""

# Clock and broad worst-path coverage. Per-clock reports prevent the global
# top-N list from hiding the audio or generated speech-enable domains.
report_clocks -file [file join $report_dir clocks.rpt]
report_timing -setup -npaths 100 -detail full_path -file [file join $report_dir global-setup.rpt]
report_timing -hold -npaths 100 -detail full_path -file [file join $report_dir global-hold.rpt]
report_timing -recovery -npaths 100 -detail full_path -file [file join $report_dir global-recovery.rpt]
report_timing -removal -npaths 100 -detail full_path -file [file join $report_dir global-removal.rpt]

set audio_clock_count 0
set audio_clock_file [open [file join $report_dir audio-clock-periods.txt] w]
foreach_in_collection clock [get_clocks *] {
    set name [get_clock_info -name $clock]
    # The Exidy core audio source is pll|general[2], about 69.604 ns.
    # pll_audio is a separate MiSTer DAC/framework clock and must not be used.
    if {[string first {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk} $name] >= 0} {
        incr audio_clock_count
        puts $audio_clock_file "$name period_ns=[get_clock_info -period $clock]"
        set safe_name [string map {"|" "_" "[" "_" "]" "_" "/" "_"} $name]
        report_timing -setup -to_clock $clock -npaths 100 -detail full_path \
            -file [file join $report_dir "$safe_name-setup.rpt"]
        report_timing -hold -to_clock $clock -npaths 100 -detail full_path \
            -file [file join $report_dir "$safe_name-hold.rpt"]
    }
}
close $audio_clock_file
if {$audio_clock_count != 1} {
    error "Expected exactly one Exidy core audio PLL clock (general[2]); found $audio_clock_count"
}

# Report all internal speech-subsystem paths in both directions, plus the
# output paths to/from its fitted state. These are diagnostic endpoint sets;
# their existence/cardinality is checked to catch synthesis disappearance.
set speech_state [require_minimum "speech subsystem fitted registers" \
    [get_registers -nowarn {*mousetrapSpeechSubsystem:speech|*}] 30]
report_timing -setup -from $speech_state -to $speech_state -npaths 100 \
    -detail full_path -file [file join $report_dir speech-internal-setup.rpt]
report_timing -hold -from $speech_state -to $speech_state -npaths 100 \
    -detail full_path -file [file join $report_dir speech-internal-hold.rpt]

# Six and only six first-stage CDC registers are excepted by the production
# SDC. Their six following-stage paths remain normally timed and are reported
# one chain at a time. This audits narrow SDC scope without adding exceptions.
set chain_specs [list \
    [list speech-enable {*|exidySpeechLoader:speech_loader|enable_meta} {*|exidySpeechLoader:speech_loader|enable_sync}] \
    [list ack {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|ack_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|ack_sync}] \
    [list generation-ack {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|generation_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|generation_sync}] \
    [list quarantine-request {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|req_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|req_sync}] \
    [list quarantine-generation {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|gen_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|gen_sync}] \
    [list cvsd-ready {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|cvsd_ready_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|cvsd_ready_sync}]]
set stage_summary [open [file join $report_dir synchronizer-stage-counts.txt] w]
set first_stage_patterns [list]
foreach spec $chain_specs {
    lassign $spec name first_pattern second_pattern
    set pair [report_register_pair "speech-sync-$name" $first_pattern $second_pattern $report_dir]
    set first [lindex $pair 0]
    lappend first_stage_patterns $first_pattern
    puts $stage_summary "$name first=1 second=1"
}
set first_stages [get_registers -nowarn $first_stage_patterns]
require_count "SDC-excepted speech first-stage registers" $first_stages 6
close $stage_summary

# The SDC intentionally exempts exactly the two reset synchronizer pairs in
# the bridge and the two enable-synchronizer flops (six CLR pins total). Resolve
# the same pin set and report names/counts; SDC itself enforces exact cardinality.
set speech_reset_pins [get_pins -compatibility_mode {*|speech_loader|bridge|main_reset|rst_meta|clrn *|speech_loader|bridge|main_reset|rst_sync|clrn *|speech_loader|bridge|cvsd_reset|rst_meta|clrn *|speech_loader|bridge|cvsd_reset|rst_sync|clrn *|speech_loader|enable_meta|clrn *|speech_loader|enable_sync|clrn}]
require_count "speech reset/enable asynchronous-clear exception pins" $speech_reset_pins 6
set reset_pin_file [open [file join $report_dir reset-exception-pins.txt] w]
foreach_in_collection pin $speech_reset_pins {
    puts $reset_pin_file [get_node_info -name $pin]
}
close $reset_pin_file

# Stage-to-stage timing is explicit above. Also report asynchronous reset
# release checks to actual local state for the main, speech/audio, and CVSD
# domains. These release paths must remain visible and timed.
set main_reset_release [require_count "main reset release stage" \
    [get_registers -nowarn {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:main_reset|rst_sync}] 1]
set cvsd_reset_release [require_count "CVSD reset release stage" \
    [get_registers -nowarn {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:cvsd_reset|rst_sync}] 1]
set audio_reset_release [require_count "audio board reset release stage" \
    [get_registers -nowarn {*|exidy2:ex2|exidyAB:sound_board|exidyResetSync:audio_reset|rst_sync}] 1]
set reset_pair_specs [list \
    [list main-reset {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:main_reset|rst_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:main_reset|rst_sync}] \
    [list cvsd-reset {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:cvsd_reset|rst_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_reset_sync:cvsd_reset|rst_sync}]]
foreach spec $reset_pair_specs {
    lassign $spec name first_pattern second_pattern
    report_register_pair "speech-reset-sync-$name" $first_pattern $second_pattern $report_dir
    foreach check [list setup hold] {
        set path [file join $report_dir "speech-reset-sync-$name-$check.rpt"]
        set check_in [open $path r]
        set check_text [read $check_in]
        close $check_in
        if {![regexp "Found 1 $check paths" $check_text]} {
            error "Expected one fitted $check path for reset stages $name; inspect $path"
        }
    }
}
set main_reset_state [require_minimum "main loader resettable state" \
    [get_registers -nowarn {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|* *|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|*}] 20]
set cvsd_reset_state [require_minimum "CVSD-domain resettable state" \
    [get_registers -nowarn {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|* *|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|cvsd_ready_*}] 4]
report_async_pair speech-main-release-to-state $main_reset_release $main_reset_state \
    [get_collection_size $main_reset_state] $report_dir
report_async_pair speech-cvsd-release-to-state $cvsd_reset_release $cvsd_reset_state \
    [get_collection_size $cvsd_reset_state] $report_dir
report_async_pair speech-audio-release-to-state $audio_reset_release $speech_state \
    [get_collection_size $speech_state] $report_dir

# The CVSD memory must be fitted as a real embedded-memory block, not logic.
# The completed full-flow fitter report is read as text only; keep all matching
# hierarchy/resource lines verbatim for review and fail if the RAM isn't named.
set fit_report [file normalize "output_files/Arcade-Exidy2.fit.rpt"]
if {![file exists $fit_report]} {
    error "Completed full-flow fitter report not found: $fit_report"
}
set fit_in [open $fit_report r]
set ram_out [open [file join $report_dir speech-ram-fit-evidence.txt] w]
set ram_hits 0
while {[gets $fit_in line] >= 0} {
    if {[regexp -nocase {cvsd_mem.*; AUTO ; Simple Dual Port ; Dual Clocks} $line]} {
        set fields [split $line ";"]
        # Quartus 17 fitter RAM table: field 19 is the per-RAM M10K count.
        # A named logical RAM row with a positive count proves real BRAM use.
        if {[llength $fields] < 23} {
            close $fit_in
            close $ram_out
            error "Malformed fitter RAM row for CVSD memory: $line"
        }
        set m10k_count [string trim [lindex $fields 19]]
        if {![string is integer -strict $m10k_count] || $m10k_count <= 0} {
            close $fit_in
            close $ram_out
            error "CVSD memory fitter row does not show positive M10K use: $line"
        }
        puts $ram_out "CVSD memory uses $m10k_count M10K block(s):"
        puts $ram_out $line
        incr ram_hits
    }
}
close $fit_in
if {$ram_hits != 1} {
    close $ram_out
    error "Expected one CVSD fitter RAM row, found $ram_hits; inspect $fit_report"
}
close $ram_out

# Required diagnostics. check_timing is the source for no-clock, multiple-
# clock, unconstrained, latch and combinational-loop findings. Exceptions are
# included so the six speech CDC/reset exception limits can be audited.
check_timing -file [file join $report_dir check-timing.rpt]
report_exceptions -file [file join $report_dir exceptions.rpt]
report_metastability -file [file join $report_dir metastability.rpt]

# Guard against QSF assignments silently being ignored by the fitter, and
# distinguish metastability recognition from physical reset-stage timing.
# Quartus may model asynchronous reset release as a one-register chain because
# the first reset stage's D input is constant; the reset flops still must exist
# and have a direct timed stage-to-stage path (checked above).
set fit_in [open $fit_report r]
set in_ignored_assignments 0
set ignored_rows_started 0
set speech_sync_assignment_rows 0
while {[gets $fit_in line] >= 0} {
    if {[string first {; Ignored Assignments} $line] >= 0} {
        set in_ignored_assignments 1
        continue
    }
    if {$in_ignored_assignments && [string first {; Name} $line] >= 0} {
        set ignored_rows_started 1
        continue
    }
    if {$in_ignored_assignments && $ignored_rows_started && [regexp {^\+[-+]+\+} $line]} {
        break
    }
    if {$in_ignored_assignments && [regexp -nocase {Synchronizer Identification} $line] &&
        [regexp -nocase {(speech_loader|exidySpeechLoader|speech subsystem)} $line]} {
        incr speech_sync_assignment_rows
    }
}
close $fit_in
if {$speech_sync_assignment_rows != 0} {
    error "Fitter ignored $speech_sync_assignment_rows speech synchronizer-identification assignment(s); inspect $fit_report"
}

set metastability_path [file join $report_dir metastability.rpt]
set meta_in [open $metastability_path r]
set metastability_text [read $meta_in]
close $meta_in
set recognized_out [open [file join $report_dir synchronizer-recognition.txt] w]
puts $recognized_out "Handshake stage recognition is checked per fitted stage in detailed metastability Synchronization Node sections. Reset pairs are validated as fitted flops with direct stage-to-stage timing; MTBF is reported separately."
set expected_sync_pairs [list \
    [list speech-enable {*|exidySpeechLoader:speech_loader|enable_meta} {*|exidySpeechLoader:speech_loader|enable_sync}] \
    [list ack {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|ack_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|ack_sync}] \
    [list generation-ack {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|generation_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_transport_adapter:transport|generation_sync}] \
    [list quarantine-request {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|req_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|req_sync}] \
    [list quarantine-generation {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|gen_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_cvsd_read_quarantine:remote|gen_sync}] \
    [list cvsd-ready {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|cvsd_ready_meta} {*|exidySpeechLoader:speech_loader|exidy_expansion_bridge_rr:bridge|exidy_expansion_loader:loader|cvsd_ready_sync}]]
set recognized_pair_count 0
foreach spec $expected_sync_pairs {
    lassign $spec name first_pattern second_pattern
    # Match report node names by their final pipe-delimited hierarchy suffix;
    # the leading wildcard in the TimeQuest selector is not report text.
    set first_name [string range $first_pattern 2 end]
    set second_name [string range $second_pattern 2 end]
    set stage_statuses [list]
    foreach stage_name [list $first_name $second_name] {
        set detail_lines [split $metastability_text "\n"]
        set stage_recognized 0
        for {set i 0} {$i < [llength $detail_lines]} {incr i} {
            set line [lindex $detail_lines $i]
            if {[string first {; Synchronization Node} $line] < 0 ||
                [string first $stage_name $line] < 0} { continue }
            set section_end [expr {min($i + 80, [llength $detail_lines] - 1)}]
            for {set j $i} {$j <= $section_end} {incr j} {
                if {$j > $i && [string first {; Synchronization Node} [lindex $detail_lines $j]] >= 0} { break }
                if {[string first {; Method of Synchronizer Identification} [lindex $detail_lines $j]] >= 0 &&
                    [string first {User Specified} [lindex $detail_lines $j]] >= 0} {
                    set stage_recognized 1
                    break
                }
            }
            if {$stage_recognized} { break }
        }
        if {!$stage_recognized} {
            close $recognized_out
            error "Fitted stage $stage_name lacks a User Specified metastability chain section ($name)"
        }
        set mtbf_status "not found in summary"
        foreach line [split $metastability_text "\n"] {
            if {[string first $stage_name $line] >= 0 && [regexp {;\s*([^;]+)\s*;\s*([^;]+)\s*;\s*(Yes|No)\s*;} $line -> worst_mtbf typical_mtbf included]} {
                set mtbf_status "worst=$worst_mtbf typical=$typical_mtbf included=$included"
                break
            }
        }
        lappend stage_statuses "[file tail $stage_name]:recognized=yes,MTBF={$mtbf_status}"
    }
    puts $recognized_out "$name first/second stages recognized=yes ([join $stage_statuses {; }])"
    incr recognized_pair_count
}
close $recognized_out
if {$recognized_pair_count != 6} {
    error "Expected 6 recognized speech handshake/enable pairs, checked $recognized_pair_count"
}
set recognized_out [open [file join $report_dir synchronizer-recognition.txt] a]
foreach spec $reset_pair_specs {
    lassign $spec name first_pattern second_pattern
    set sync_name [string range $second_pattern 2 end]
    set final_stage_recognized [expr {[string first $sync_name $metastability_text] >= 0}]
    puts $recognized_out "$name physical_two_stage_pair=yes setup_hold_paths=1+1 final_stage_in_metastability_report=$final_stage_recognized; no pair-level MTBF claimed"
}
close $recognized_out

puts $summary "Speech registers=[get_collection_size $speech_state] core_audio_clocks=$audio_clock_count speech_first_stage_chains=6 async_clear_exception_pins=6"
puts $summary "Fitter ignored speech synchronizer assignments=0; recognized handshake/enable pairs=$recognized_pair_count; reset pairs independently fitted and timed (see synchronizer-recognition.txt)."
puts $summary "Fitter CVSD RAM evidence lines=$ram_hits (see speech-ram-fit-evidence.txt)."
puts $summary "Read check-timing.rpt and exceptions.rpt for coverage, no_clock/multiclock, latch/loop, and exact exception endpoints."
puts $summary "No auPH0 clock exception was added; the existing RIOT/no_clock limitation remains unchanged."
close $summary
delete_timing_netlist
project_close
puts "Speech integration timing reports written to $report_dir"
