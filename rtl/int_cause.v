// Interrupt-condition collision bits ($5103 bits 4:2) per hardware profile.
// MAME wires each game's collision lines through a mask and an inversion
// (exidy_video_config): the latched bit is (collision ^ invert) & mask, and an
// IRQ is raised only for collisions that pass the mask.
//   profile 0: legacy fixed wiring (mask 14, invert 00) - unchanged baseline
//   profile 1: Venture, FAX/FAX 2 (mask 04, invert 04)
//   profile 2: Pepper II, Hard Hat (mask 14, invert 04)
//   profile 3: Teeter Torture      (mask 0c, invert 0c)
// Collision bits: [4] sprite1/sprite2, [3] sprite2/background, [2] sprite1/background.
module exidyIntCause (
	input  [1:0] profile,
	input        m1m2,
	input        m2char,
	input        m1char,
	output [4:2] cause,
	output       irq
);
	wire [4:2] coll = {m1m2, m2char, m1char};
	reg  [4:2] mask, inv;
	always @(*) begin
		case (profile)
			2'd1:    begin mask = 3'b001; inv = 3'b001; end
			2'd2:    begin mask = 3'b101; inv = 3'b001; end
			2'd3:    begin mask = 3'b011; inv = 3'b011; end
			default: begin mask = 3'b101; inv = 3'b000; end
		endcase
	end
	assign cause = (coll ^ inv) & mask;
	assign irq   = |(coll & mask);
endmodule
