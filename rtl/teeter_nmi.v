// Source-domain 600 Hz active-low NMI generator for the Teeter profile.
// The request is held until PH_1 samples it; T65 edge-detects NMI only when
// its Enable input is high, including while RDY is low.
module exidyTeeterNmi #(
	parameter integer PERIOD_TICKS = 75260
) (
	input  wire clk,
	input  wire reset_n,
	input  wire teeter_profile,
	input  wire ph1_enable,
	output reg  nmi_n
);
	reg [31:0] period_count;

	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			period_count <= 32'd0;
			nmi_n <= 1'b1;
		end else if (!teeter_profile) begin
			period_count <= 32'd0;
			nmi_n <= 1'b1;
		end else begin
			if (period_count == PERIOD_TICKS - 1) begin
				period_count <= 32'd0;
				nmi_n <= 1'b0;
			end else begin
				period_count <= period_count + 32'd1;
				if (!nmi_n && ph1_enable)
					nmi_n <= 1'b1;
			end
		end
	end
endmodule
