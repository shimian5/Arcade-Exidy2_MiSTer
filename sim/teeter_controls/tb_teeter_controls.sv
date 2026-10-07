`timescale 1ns/1ps
module tb_teeter_controls;
    reg clk_sys = 0;
    reg reset = 0;
    reg paused = 0;
    reg ce_frame = 0;
    reg dpad_position_mode = 0;
    reg [8:0] spinner = 0;
    reg signed [7:0] analog_x = 0;
    reg dpad_left = 0;
    reg dpad_right = 0;
    reg cpu_read_strobe = 0;
    reg cpu_sample_strobe = 0;
    reg [7:0] cpu_databus_in = 8'h00;
    reg [7:0] cpu_sampled_data = 8'h00;
    reg [7:0] in0_other = 8'hbb;
    wire [7:0] dial_position;
    wire [7:0] dial_consumed;
    wire [7:0] in0_value;
    integer errors = 0;

    always #5 clk_sys = ~clk_sys;

    teeterControls dut(
        .clk_sys(clk_sys), .reset(reset), .paused(paused), .ce_frame(ce_frame),
        .dpad_position_mode(dpad_position_mode), .spinner(spinner), .analog_x(analog_x),
        .dpad_left(dpad_left), .dpad_right(dpad_right),
        .cpu_read_strobe(cpu_read_strobe), .cpu_read_data(cpu_databus_in), .in0_other(in0_other),
        .dial_position(dial_position), .dial_consumed(dial_consumed), .in0_value(in0_value)
    );

    // Model Exidy2's input register and the later PH_1 CPU sample. It captures
    // the combinational byte every master edge; T65 consumes the registered
    // byte later, and the adapter commits that exact byte on the same strobe.
    always @(posedge clk_sys) begin
        cpu_databus_in <= in0_value;
        if (cpu_sample_strobe) cpu_sampled_data <= cpu_databus_in;
    end

    // Deliberately broken reference: consumes one dial count every master
    // clock while the read level remains high, instead of once per read edge.
    reg [7:0] bad_consumed = 0;
    always @(posedge clk_sys) begin
        if (reset) bad_consumed <= 0;
        else if (cpu_read_strobe && (dial_position != bad_consumed))
            bad_consumed <= bad_consumed + 1'b1;
    end

    task automatic check(input bit condition, input string message);
        begin
            if (!condition) begin errors = errors + 1; $display("FAIL %0s", message); end
        end
    endtask

    task automatic tick;
        begin @(posedge clk_sys); #1; end
    endtask

    task automatic frame_tick;
        begin
            @(negedge clk_sys); ce_frame = 1;
            @(posedge clk_sys); #1;
            @(negedge clk_sys); ce_frame = 0;
        end
    endtask

    task automatic read_pulse;
        begin
            @(negedge clk_sys); cpu_read_strobe = 1;
            @(posedge clk_sys); #1;
            @(negedge clk_sys); cpu_read_strobe = 0;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk_sys); reset = 1; paused = 0; ce_frame = 0;
            cpu_read_strobe = 0; cpu_sample_strobe = 0; spinner = 0; analog_x = 0;
            dpad_left = 0; dpad_right = 0; dpad_position_mode = 0;
            tick(); tick();
            @(negedge clk_sys); reset = 0;
            #1;
        end
    endtask

    initial begin
        reset_dut();
        check(dial_position == 0 && dial_consumed == 0 && in0_value == 8'hbb, "reset and idle byte");
        in0_other = 8'hff; #1;
        check(in0_value == 8'hbb, "adapter replaces only bits 6 and 2 of base byte");
        in0_other = 8'hbb;

        // MAME PORT_REVERSE: negative raw spinner delta becomes positive dial movement.
        @(negedge clk_sys); spinner = {1'b1, 8'hfb};
        tick();
        check(dial_position == 5, "spinner delta accumulated with reverse");
        @(negedge clk_sys); spinner = {1'b1, 8'h02};
        tick();
        check(dial_position == 5, "spinner data ignored without toggle");
        check(in0_value == 8'hff, "positive event maps to bits 6 and 2");

        // Holding the bus read level across three master cycles must consume once.
        @(negedge clk_sys); cpu_read_strobe = 1;
        tick(); tick(); tick();
        check(dial_consumed == 1, "held read strobe consumes exactly once");
        check(bad_consumed == 3, "negative control exposes repeated master-tick consumption");
        check(cpu_databus_in == 8'hff, "registered byte preserves positive event for later PH_1");
        @(negedge clk_sys); cpu_read_strobe = 0;
        repeat (4) read_pulse();
        check(dial_consumed == 5 && in0_value == 8'hbb, "queued five counts drain one per read");
        $display("PASS read-strobe negative control");

        // Move target behind the cursor: event remains set, positive bit clears.
        @(negedge clk_sys); spinner = {1'b0, 8'h03}; // reverse => -3, target 2
        tick();
        check(dial_position == 2 && in0_value == 8'hfb, "negative event maps to bit 6 only");
        tick(); // let registered CPU_databus_in capture the new byte
        read_pulse();
        check(dial_consumed == 4 && in0_value == 8'hfb, "negative cursor advances one count");
        // The input register sees the old combinational byte on the master
        // edge where the dial target changes (NBA update). At PH_1 next edge,
        // consume the registered event/direction, not the newer combinational
        // event, which now points the other way.
        read_pulse();
        check(dial_consumed == 3 && cpu_databus_in == 8'hfb, "negative event captured before target change");
        @(negedge clk_sys); spinner = {1'b1, 8'hfd}; cpu_sample_strobe = 1;
        @(posedge clk_sys); #1;
        check(dial_consumed == 3 && in0_value == 8'hff, "target change produces newer positive event");
        @(negedge clk_sys); cpu_read_strobe = 1;
        @(posedge clk_sys); #1;
        check(cpu_sampled_data == 8'hfb, "PH_1 model samples prior registered input byte");
        check(dial_consumed == 2 && in0_value == 8'hff, "PH_1 commits registered negative direction, not current positive direction");
        @(negedge clk_sys); cpu_sample_strobe = 0; cpu_read_strobe = 0;

        // Half-turn tie selects decrement; subsequent reads continue modulo-256.
        reset_dut();
        @(negedge clk_sys); spinner = {1'b1, 8'h80};
        tick();
        check(dial_position == 8'h80 && in0_value == 8'hfb, "delta 0x80 chooses decrement");
        tick();
        read_pulse();
        check(dial_consumed == 8'hff && in0_value == 8'hfb, "half-turn decrement wraps cursor");

        // Target FF from zero decrements; target zero from FF increments across wrap.
        reset_dut();
        @(negedge clk_sys); spinner = {1'b1, 8'h01};
        tick();
        check(dial_position == 8'hff && in0_value == 8'hfb, "negative one target selects decrement");
        tick();
        read_pulse();
        check(dial_consumed == 8'hff && in0_value == 8'hbb, "decrement reaches wrapped target");
        @(negedge clk_sys); spinner = {1'b0, 8'hff}; // reverse => +1, target zero
        tick();
        check(dial_position == 8'h00 && in0_value == 8'hff, "one-count move wraps target to zero");
        tick();
        read_pulse();
        check(dial_consumed == 8'h00 && in0_value == 8'hbb, "increment wraps cursor to zero");

        // Velocity ramp is frame enabled; analog has a small center deadzone.
        reset_dut();
        dpad_right = 1;
        frame_tick();
        check(dial_position == 0, "first velocity frame ramps before contributing");
        frame_tick();
        check(dial_position == 8'hf0, "second velocity frame contributes reversed 16");
        dpad_right = 0;
        frame_tick();
        check(dial_position == 8'he0, "release frame contributes then decelerates");
        frame_tick();
        check(dial_position == 8'he0, "velocity returns to zero after release");

        reset_dut();
        analog_x = 8'sd8;
        frame_tick();
        check(dial_position == 0, "analog center deadzone suppresses eight counts");
        analog_x = 8'sd16;
        frame_tick();
        check(dial_position == 8'hfe, "analog beyond deadzone contributes signed scaled amount");
        analog_x = -8'sd16;
        frame_tick();
        check(dial_position == 0, "negative analog contribution reverses consistently");

        // Position-ramp D-pad mode also updates only on frames.
        reset_dut();
        dpad_position_mode = 1;
        dpad_right = 1;
        frame_tick(); frame_tick();
        check(dial_position == 8'hfe, "position-ramp mode contributes deflection divided by eight");

        // Pause freezes frame state and consumes spinner toggles without deferred motion.
        reset_dut();
        paused = 1; dpad_right = 1; analog_x = 8'sd32;
        spinner = {1'b1, 8'hfb};
        frame_tick(); frame_tick();
        check(dial_position == 0, "paused frame and spinner updates do not move dial");
        paused = 0; dpad_right = 0; analog_x = 0;
        tick();
        check(dial_position == 0, "pause release does not replay consumed spinner delta");
        frame_tick(); frame_tick();
        check(dial_position == 0, "paused D-pad ramp state does not resume with a jump");

        if (errors == 0) $display("PASS teeter controls");
        else $fatal(1, "FAILED %0d", errors);
        $finish;
    end
endmodule
