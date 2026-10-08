# Bundled PIA snapshots: add only after the existing project constraints.
# The FIFO publishes each write through a two-stage Gray-pointer synchronizer.
# Destination capture is at least two master periods after the source write;
# 20 ns is below that ~44.3 ns window, including reported clock skew/uncertainty.
# Quartus 17 has no -datapath_only option. These are clock-relative bounds;
# review the fitted data delays as well as their slack. No bus false path.
proc pia_fifo_nodes {pattern count} {
    set nodes [get_keepers $pattern]
    if {[get_collection_size $nodes] != $count} {
        error "PIA FIFO expected $count nodes for $pattern, found [get_collection_size $nodes]"
    }
    return $nodes
}
set pia_fifo_words [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|fifo_mem*} 36]
set pia_fifo_capture [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|main_byte_data[*] *exidyPiaReturn:pia_return_data|pending_notify_value} 9]
set_max_delay -from $pia_fifo_words -to $pia_fifo_capture 20.000
# Gray bus routing is shorter than either source period. First synchronizer
# stages may encounter metastability; stage-to-stage paths stay normally timed.
proc pia_fifo_gray_nodes {name} {
    set pattern [format {*exidyPiaReturn:pia_return_data|%s[*]} $name]
    set nodes [get_registers $pattern]
    set bits {}
    set expression [format {\|%s\[([0-2])\](~DUPLICATE[0-9]*)?$} $name]
    foreach_in_collection node $nodes {
        set full_name [get_register_info -name $node]
        if {![regexp $expression $full_name unused bit]} {
            error "Unexpected PIA FIFO Gray register: $full_name"
        }
        lappend bits $bit
    }
    if {[lsort -unique $bits] ne {0 1 2}} {
        error "PIA FIFO $name is missing logical bits: $bits"
    }
    # Include physical replicas in the bound; do not silently drop their paths.
    return $nodes
}
set pia_fifo_write [pia_fifo_gray_nodes write_gray]
set pia_fifo_read [pia_fifo_gray_nodes read_gray]
set pia_fifo_write_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|write_gray_meta[*]} 3]
set pia_fifo_read_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|read_gray_meta[*]} 3]
set_max_delay -from $pia_fifo_write -to $pia_fifo_write_meta 20.000
set_max_delay -from $pia_fifo_read -to $pia_fifo_read_meta 20.000
# Raw reset asserts both conditioner stages asynchronously. Except ONLY their
# asynchronous-clear input pins. Meta-to-release data and local release-to-state
# recovery/removal remain timed. This is the reset synchronizer input contract,
# not an exception on the synchronizer data chain or the FIFO state resets.
set pia_fifo_reset_pins [get_pins -compatibility_mode {*|pia_return_data|audio_reset_meta|clrn *|pia_return_data|audio_reset_release|clrn *|pia_return_data|master_reset_meta|clrn *|pia_return_data|master_reset_release|clrn}]
if {[get_collection_size $pia_fifo_reset_pins] != 4} {
    error "PIA FIFO expected exactly four conditioner clear pins"
}
set_false_path -through $pia_fifo_reset_pins
rename pia_fifo_nodes {}
rename pia_fifo_gray_nodes {}
