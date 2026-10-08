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
set pia_fifo_write [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|write_gray[*]} 3]
set pia_fifo_read [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|read_gray[*]} 3]
set pia_fifo_write_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|write_gray_meta[*]} 3]
set pia_fifo_read_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|read_gray_meta[*]} 3]
set_max_delay -from $pia_fifo_write -to $pia_fifo_write_meta 20.000
set_max_delay -from $pia_fifo_read -to $pia_fifo_read_meta 20.000
# Only the first stage of each reset conditioner samples an asynchronous level.
set pia_fifo_reset_meta [pia_fifo_nodes {*exidyPiaReturn:pia_return_data|audio_reset_meta *exidyPiaReturn:pia_return_data|master_reset_meta} 2]
set_false_path -to $pia_fifo_reset_meta
rename pia_fifo_nodes {}
