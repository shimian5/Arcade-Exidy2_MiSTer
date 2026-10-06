// Mono mix of the two audio-board source groups (8253/MUSIC and 6840/TONE).
// MAME routes every sound source to one mono speaker; the baseline core sent
// each group to a separate output, so each ear missed about half the effects.
// Each input is halved before the sum, so the result cannot overflow.
// Gain calibration against a MAME capture is still pending (W08).
module exidyAudioMix (
	input  signed [15:0] src_a,
	input  signed [15:0] src_b,
	input                mute,
	output signed [15:0] mono
);
	wire signed [15:0] sum = (src_a >>> 1) + (src_b >>> 1);
	assign mono = mute ? 16'sd0 : sum;
endmodule
