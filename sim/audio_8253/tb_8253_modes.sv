`timescale 1ns/1ps

module tb_8253_modes;
    logic reset = 1'b1;
    logic clk_sys = 1'b0;
    logic [1:0] addr = '0;
    logic [7:0] din = '0;
    logic wr = 1'b0;
    logic rd = 1'b0;
    logic [2:0] clk_timer = '0;
    logic [2:0] gate = 3'b111;
    wire [7:0] dout;
    wire [2:0] out;
    wire [2:0] sound_active;

    always #5 clk_sys = ~clk_sys;

    k580vi53 dut(.*);

    task automatic bus_write(input logic [1:0] a, input logic [7:0] d);
        @(negedge clk_sys); addr = a; din = d; wr = 1;
        repeat (3) @(negedge clk_sys);
        wr = 0;
        repeat (3) @(negedge clk_sys);
    endtask

    task automatic timer_tick;
        @(negedge clk_sys); clk_timer = 3'b111;
        repeat (2) @(negedge clk_sys);
        clk_timer = 3'b000;
        repeat (2) @(negedge clk_sys);
    endtask

    task automatic ticks(input integer n);
        repeat (n) timer_tick();
    endtask

    task automatic reset_dut;
        reset = 1;
        repeat (4) @(negedge clk_sys);
        reset = 0;
        repeat (5) @(negedge clk_sys);
    endtask

    task automatic write_mode0(input logic [1:0] channel, input logic [15:0] count);
        bus_write(3, {channel, 2'b11, 3'b000, 1'b0});
        bus_write(channel, count[7:0]);
        bus_write(channel, count[15:8]);
    endtask

    task automatic write_mode3(input logic [1:0] channel, input logic [2:0] mode, input logic [15:0] count);
        bus_write(3, {channel, 2'b11, mode, 1'b0});
        bus_write(channel, count[7:0]);
        bus_write(channel, count[15:8]);
    endtask

    task automatic require(input logic condition, input string label);
        if (!condition) begin
            $display("FAIL %s at time=%0t out0=%b", label, $time, out[0]);
            failures = failures + 1;
        end else begin
            $display("PASS %s at time=%0t out0=%b", label, $time, out[0]);
        end
    endtask

    integer i;
    integer high_ticks, low_ticks;
    integer failures = 0;

    initial begin
        reset_dut();
        // Fresh counters use independent channels because reset does not clear CE state.
        write_mode0(2'd0, 16'd5);
        write_mode3(2'd1, 3'd3, 16'd6);
        // Separate invocations exercise both the captured raw-7 word and canonical mode 3.
        write_mode3(2'd2, $test$plusargs("MODE7") ? 3'd7 : 3'd3, 16'd5);

        // Mode 0 low until count reaches terminal; output then remains high.
        ticks(5);
        require(out[0] == 0, "mode0 count5 remains low through five timer ticks");
        timer_tick();
        require(out[0] == 1, "mode0 count5 asserts on sixth timer tick");
        if ($test$plusargs("NEGATIVE"))
            require(out[0] == 0, "negative control deliberately expects wrong mode0 output");
        ticks(12);
        require(out[0] == 1, "mode0 terminal output holds high through counter wrap");

        // LSB then MSB is effective only after the MSB bus write edge.
        bus_write(3, 8'h30);
        bus_write(0, 8'd4);
        ticks(8);
        require(out[0] == 0, "mode0 control word and LSB-only stage remain stopped");
        bus_write(0, 8'd0);
        timer_tick();
        ticks(5);
        require(out[0] == 1, "mode0 count4 terminal after complete LSB/MSB load and reload edge");

        // A binary zero is 65536 input clocks; it must not terminate early.
        bus_write(0, 8'd0);
        bus_write(0, 8'd0);
        timer_tick();
        require(out[0] == 0, "mode0 binary zero reload starts low");
        ticks(65535);
        require(out[0] == 0, "mode0 binary zero remains low through tick65535");
        timer_tick();
        require(out[0] == 1, "mode0 binary zero terminal at 65536 count clocks after reload edge");
        ticks(8);
        require(out[0] == 1, "mode0 zero terminal stays asserted");

        // Mode 3 even and raw mode 7 odd use separate fresh counters.
        for (i = 1; i < 3; i = i + 1) begin
            // Synchronize to a high phase, then measure complete high and low intervals.
            for (integer j = 0; j < 20 && out[i] != 1; j = j + 1)
                timer_tick();
            require(out[i] == 1, i == 1 ? "mode3 even reaches high phase" : "mode3-equivalent odd reaches high phase");
            for (integer phase = 0; phase < 4; phase = phase + 1) begin
                high_ticks = 0;
                for (integer j = 0; j < 20 && out[i] == 1; j = j + 1) begin
                    timer_tick();
                    high_ticks = high_ticks + 1;
                    if (out[i] == 0) begin
                        if (i == 1) $display("EDGE channel=1 phase=%0d OUT=0 count=%04x reload=%04x", phase, dut.t1.counter, dut.t1.ld_count);
                        else $display("EDGE channel=2 phase=%0d OUT=0 count=%04x reload=%04x", phase, dut.t2.counter, dut.t2.ld_count);
                    end
                end
                require(out[i] == 0, i == 1 ? "mode3 even exits high phase" : "mode3-equivalent odd exits high phase");
                low_ticks = 0;
                for (integer j = 0; j < 20 && out[i] == 0; j = j + 1) begin
                    timer_tick();
                    low_ticks = low_ticks + 1;
                    if (out[i] == 1) begin
                        if (i == 1) $display("EDGE channel=1 phase=%0d OUT=1 count=%04x reload=%04x", phase, dut.t1.counter, dut.t1.ld_count);
                        else $display("EDGE channel=2 phase=%0d OUT=1 count=%04x reload=%04x", phase, dut.t2.counter, dut.t2.ld_count);
                    end
                end
                require(out[i] == 1, i == 1 ? "mode3 even exits low phase" : "mode3-equivalent odd exits low phase");
                $display("MEASURE channel=%0d control=%02x interval=%0d high_ticks=%0d low_ticks=%0d", i, i == 1 ? 8'h76 : ($test$plusargs("MODE7") ? 8'hbe : 8'hb6), phase, high_ticks, low_ticks);
                if (i == 1) begin
                    require(high_ticks == 3 && low_ticks == 3, "mode3 even count6 has 3/3 tick phases");
                end else begin
                    require(high_ticks == 3 && low_ticks == 2, "odd count5 has reference 3/2 tick phases");
                end
            end
        end

        if (failures != 0) $fatal(1, "%0d test assertions failed", failures);
        $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
