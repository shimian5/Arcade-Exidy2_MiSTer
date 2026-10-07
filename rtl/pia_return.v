// One master-clock staging register for the audio-to-main PIA return byte.
// Both clocks are outputs of the core PLL; this path remains normally timed.
module exidyPiaReturn (
	input        master_clk,
	input        reset_n,
	input  [7:0] audio_byte,
	output reg [7:0] main_byte
);
	always @(posedge master_clk) begin
		if (!reset_n)
			main_byte <= 8'h00;
		else
			main_byte <= audio_byte;
	end
endmodule
