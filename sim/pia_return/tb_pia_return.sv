module tb_pia_return;
	logic master_clk = 0;
	logic audio_clk = 0;
	logic master_reset_n = 0;
	logic audio_reset_n = 0;
	logic [7:0] audio_byte = 0;
	wire [7:0] main_byte;

	exidyPiaReturnLegacy dut(.*);

	task automatic tick_master;
		master_clk = 1;
		#1;
		if (main_byte === 8'hxx) $fatal(1, "unknown main output");
		master_clk = 0;
		#1;
	endtask

	task automatic tick_audio;
		audio_clk = 1;
		#1;
		audio_clk = 0;
		#1;
	endtask

	initial begin
		tick_audio();
		tick_master();
		if (main_byte !== 8'h00) $fatal(1, "reset did not clear return register");
		audio_reset_n = 1;
		master_reset_n = 1;
		audio_byte = 8'hA5;
		tick_audio();
		if (main_byte !== 8'h00) $fatal(1, "source stage bypassed destination register");
		tick_master();
		if (main_byte !== 8'hA5) $fatal(1, "two-stage whole-byte capture failed");
		// Master edges before an audio capture cannot expose a half-updated byte.
		audio_byte = 8'h5A;
		tick_master();
		if (main_byte !== 8'hA5) $fatal(1, "master stage saw data before source capture");
		tick_audio();
		if (main_byte !== 8'hA5) $fatal(1, "source capture bypassed master register");
		tick_master();
		if (main_byte !== 8'h5A) $fatal(1, "second whole-byte capture failed");

		// Source-domain reset is independent and propagates through the master stage.
		audio_reset_n = 0;
		tick_audio();
		tick_master();
		if (main_byte !== 8'h00) $fatal(1, "source reset did not clear/propagate zero");
		audio_reset_n = 1;

		// Destination validity masks retained data asynchronously; the data FF
		// itself remains normally clocked and is hidden until the first edge.
		audio_byte = 8'hE7;
		tick_audio();
		tick_master();
		if (main_byte !== 8'hE7) $fatal(1, "destination data capture failed before reset-mask test");
		master_reset_n = 0;
		#1;
		if (main_byte !== 8'h00) $fatal(1, "destination valid reset did not mask output");
		if (dut.main_byte_data !== 8'hE7) $fatal(1, "destination data register unexpectedly reset");
		master_reset_n = 1;
		#1;
		if (main_byte !== 8'h00) $fatal(1, "destination reset release exposed retained data without a clock");
		tick_master();
		if (main_byte !== 8'hE7) $fatal(1, "destination valid did not expose data after first master edge");
		master_reset_n = 0;
		tick_master();
		audio_reset_n = 0;
		tick_audio();
		if (main_byte !== 8'h00) $fatal(1, "final reset did not clear both stages");
		$display("PASS production exidyPiaReturn dual-clock stages/independent reset test");
		$finish;
	end
endmodule
