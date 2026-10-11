// Isolated source-equivalence candidate for the Exidy IRQ event latch.
// The extracted differential simulation passes, but Quartus 17.0.2 rejects
// this multi-event conditional and infers an irq latch. Keep it out of the
// production hierarchy; see the event coverage audit for the probe evidence.
module exidy_irq_event_sticky_candidate (
	input  wire BCLK,
	input  wire COINT,
	input  wire nEIR,
	input  wire VL1,
	input  wire cDET_sel,
	input  wire [7:0] eir_payload,
	output reg  irq,
	output reg  [7:0] eir
);
	// This is the set/clear form of the source sticky equation:
	// irq_next = (irq | VL1 | COINT | cDET_sel) & nEIR.
	// nEIR is the asynchronous read-clear; BCLK and COINT retain the legacy
	// event sensitivities so event phase is unchanged in this experiment.
	always @(negedge BCLK or negedge COINT or negedge nEIR) begin
		if (!nEIR)
			irq <= 1'b0;
		else if (VL1 || COINT || cDET_sel)
			irq <= 1'b1;
	end

	// Preserve the production snapshot edge and payload in this experiment.
	always @(posedge irq)
		eir <= eir_payload;
endmodule
