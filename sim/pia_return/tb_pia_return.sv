module tb_pia_return;
	logic master_clk = 0;
	logic reset_n = 0;
	logic [7:0] audio_byte = 0;
	wire [7:0] main_byte;

	exidyPiaReturn dut(.*);
	always #5 master_clk = ~master_clk;

	task automatic tick;
		@(posedge master_clk);
		#1;
	endtask

	initial begin
		tick();
		if (main_byte !== 8'h00) $fatal(1, "reset did not clear return register");
		reset_n = 1;
		audio_byte = 8'hA5;
		#1;
		if (main_byte !== 8'h00) $fatal(1, "input bypassed one-cycle register");
		tick();
		if (main_byte !== 8'hA5) $fatal(1, "whole-byte capture failed");
		audio_byte = 8'h5A;
		#1;
		if (main_byte !== 8'hA5) $fatal(1, "new byte was not staged");
		tick();
		if (main_byte !== 8'h5A) $fatal(1, "second whole-byte capture failed");
		reset_n = 0;
		tick();
		if (main_byte !== 8'h00) $fatal(1, "reset did not clear staged byte");
		$display("PASS production exidyPiaReturn one-cycle/reset test");
		$finish;
	end
endmodule
