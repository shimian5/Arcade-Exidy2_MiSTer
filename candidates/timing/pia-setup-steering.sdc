# Isolated fitter-steering experiment only. Do not add to production SDC/QSF.
# This places an artificially tighter 2.850 ns maximum delay on the complete
# registered 8-bit audio-to-master data transfer to encourage local routing.
set pia_steer_from [get_registers -nowarn {*exidyPiaReturn:pia_return_data|audio_byte_stage*}]
set pia_steer_to   [get_registers -nowarn {*exidyPiaReturn:pia_return_data|main_byte_data*}]
if {[get_collection_size $pia_steer_from] != 8} {
    error "PIA steering source collection must resolve to 8 audio_byte_stage registers"
}
if {[get_collection_size $pia_steer_to] != 8} {
    error "PIA steering destination collection must resolve to 8 main_byte_data registers"
}
set_max_delay -from $pia_steer_from -to $pia_steer_to 2.850
