// Two-flop reset conditioner for logic on a clock unrelated to the reset source.
// Both edges are delayed by two destination-clock cycles. The destination clock
// must be running. Power-up value is "in reset".
module exidyResetSync (
	input  clk,
	input  reset_n,
	output reset_n_sync
);
	reg rst_meta = 1'b0;
	reg rst_sync = 1'b0;
	always @(posedge clk) begin
		rst_meta <= reset_n;
		rst_sync <= rst_meta;
	end
	assign reset_n_sync = rst_sync;
endmodule
