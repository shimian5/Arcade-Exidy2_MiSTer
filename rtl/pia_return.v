// Register the DDR-masked audio PIA byte in its source domain, then register
// it once more in the related master domain. Both byte transfers remain timed.
module exidyPiaReturn (
	input        audio_clk,
	input        master_clk,
	input        audio_reset_n,
	input        master_reset_n,
	input  [7:0] audio_byte,
	output wire [7:0] main_byte
);
	reg [7:0] audio_byte_stage;
	reg [7:0] main_byte_data;
	reg main_byte_valid;

	always @(posedge audio_clk) begin
		if (!audio_reset_n)
			audio_byte_stage <= 8'h00;
		else
			audio_byte_stage <= audio_byte;
	end

	// Keep the whole-byte path reset-free and normally timed.
	always @(posedge master_clk) begin
		main_byte_data <= audio_byte_stage;
	end

	// PIA_9B resets asynchronously. Mask retained data immediately on reset;
	// validity returns only on a master edge after reset has been released.
	always @(posedge master_clk or negedge master_reset_n) begin
		if (!master_reset_n)
			main_byte_valid <= 1'b0;
		else
			main_byte_valid <= 1'b1;
	end

	assign main_byte = main_byte_valid ? main_byte_data : 8'h00;
endmodule
