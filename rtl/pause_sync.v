// Two-stage level synchronizer for pause control entering the audio clock domain.
// The source remains asserted long enough for the destination to sample it.
module exidyPauseSync (
	input  audio_clk,
	input  pause_in,
	output pause_audio
);
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED IF ASYNCHRONOUS" *) reg pause_meta = 1'b0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED IF ASYNCHRONOUS" *) reg pause_sync = 1'b0;

	always @(posedge audio_clk) begin
		pause_meta <= pause_in;
		pause_sync <= pause_meta;
	end

	assign pause_audio = pause_sync;
endmodule
