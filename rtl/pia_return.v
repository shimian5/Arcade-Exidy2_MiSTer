// Register the DDR-masked audio PIA byte in its source domain, then register
// it once more in the related master domain. Both transfers remain timed.
module exidyPiaReturn (
	input        audio_clk,
	input        master_clk,
	input        audio_reset_n,
	input        master_reset_n,
	input  [7:0] audio_byte,
	output reg [7:0] main_byte
);
	reg [7:0] audio_byte_stage;

	always @(posedge audio_clk) begin
		if (!audio_reset_n)
			audio_byte_stage <= 8'h00;
		else
			audio_byte_stage <= audio_byte;
	end

	always @(posedge master_clk) begin
		if (!master_reset_n)
			main_byte <= 8'h00;
		else
			main_byte <= audio_byte_stage;
	end
endmodule
