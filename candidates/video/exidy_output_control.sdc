# Candidate controller only: asynchronous levels into the first metastability stages.
# Both second stages and all functional data paths remain timed.
foreach signal {native_lock_meta output_lock_meta warm_done_meta} {
 set stage [get_registers -nowarn [format {*controller|%s} $signal]]
 if {[get_collection_size $stage] != 1} {error "Expected one controller first stage $signal"}
 set_false_path -to $stage
}
# Assert asynchronously, release through two output-clock stages. Cut only CLR.
set reset_pins [get_pins -compatibility_mode {*controller|warm_reset_pipe[*]|clrn}]
if {[get_collection_size $reset_pins] != 2} {error "Expected two controller reset CLR pins"}
set_false_path -through $reset_pins
unset stage
unset reset_pins
