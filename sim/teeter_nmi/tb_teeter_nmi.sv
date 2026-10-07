module tb_teeter_nmi;
	localparam integer PERIOD = 75260;
	logic clk = 0;
	logic reset_n = 0;
	logic teeter_profile = 0;
	logic ph1_enable = 0;
	wire nmi_n;
	integer divider = 0;
	integer ticks = 0;
	integer event_tick;
	integer prior_event_tick;
	integer start_tick;
	integer low_ticks;

	exidyTeeterNmi #(.PERIOD_TICKS(PERIOD)) dut(.*);
	always #5 clk = ~clk;

	always @(posedge clk) begin
		if (!reset_n) begin
			divider <= 0;
			ph1_enable <= 0;
		end else if (divider == 63) begin
			divider <= 0;
			ph1_enable <= 1;
		end else begin
			divider <= divider + 1;
			ph1_enable <= 0;
		end
	end

	task automatic tick;
		begin
			@(posedge clk);
			#1;
			ticks = ticks + 1;
		end
	endtask

	task automatic wait_for_event;
		integer waited;
		begin
			waited = 0;
			while (nmi_n !== 1'b0 && waited < PERIOD + 70) begin
				tick();
				waited = waited + 1;
			end
			if (nmi_n !== 1'b0) $fatal(1, "timeout waiting for NMI event");
		end
	endtask

	initial begin
		tick();
		tick();
		if (nmi_n !== 1'b1) $fatal(1, "reset did not keep NMI inactive");
		reset_n = 1;
		repeat (100) tick();
		if (nmi_n !== 1'b1) $fatal(1, "disabled Teeter profile generated NMI");

		teeter_profile = 1;
		start_tick = ticks;
		wait_for_event();
		event_tick = ticks - start_tick;
		if (event_tick != PERIOD)
			$fatal(1, "first period off: expected %0d ticks, got %0d", PERIOD, event_tick);
		prior_event_tick = ticks;
		low_ticks = 0;
		while (nmi_n === 1'b0 && low_ticks < 70) begin
			tick();
			low_ticks = low_ticks + 1;
		end
		if (nmi_n !== 1'b1 || low_ticks > 64)
			$fatal(1, "NMI did not release on PH_1 sample (low ticks=%0d)", low_ticks);

		wait_for_event();
		event_tick = ticks;
		if (event_tick - prior_event_tick != PERIOD)
			$fatal(1, "period drift: expected %0d ticks, got %0d", PERIOD, event_tick-prior_event_tick);

		// Disabling the profile synchronously cancels the timer/output.
		teeter_profile = 0;
		tick();
		if (nmi_n !== 1'b1) $fatal(1, "disabled profile did not force inactive NMI");

		// Asynchronous reset also clears the divider independent of a clock.
		teeter_profile = 1;
		reset_n = 0;
		#1;
		if (nmi_n !== 1'b1) $fatal(1, "asynchronous reset did not clear NMI");
		reset_n = 1;
		repeat (100) tick();
		if (nmi_n !== 1'b1) $fatal(1, "reset did not restart the NMI period");
		$display("PASS Teeter NMI generator nominal period=%0d; sampled pulse width=%0d", PERIOD, low_ticks);
		$finish;
	end

	initial begin
		#2000000;
		$fatal(1, "watchdog");
	end
endmodule
