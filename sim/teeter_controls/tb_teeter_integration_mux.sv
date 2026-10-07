`timescale 1ns/1ps
// Focused integration fixture for the proposed Exidy CPU input-mux qualifier.
// It mirrors the current CPU_databus_in priority and T65's PH_1/RDY sample
// relationship without modifying or instantiating production RTL.
module tb_teeter_integration_mux;
    reg clk = 0, reset = 1, pause = 0, ph1 = 0;
    reg profile_d0 = 1, cpu_rw_n = 1;
    reg [1:0] addr_lo = 2'b01;
    // Match Exidy2's active-low selection wires: 1 means that source is not selected.
    reg RAMSEL = 1, ROMSEL = 1, SRAMSEL = 1, CHARSEL = 1, EXTVID = 1, IOSEL = 0;
    reg [7:0] ram_data = 8'hA5, rom_data = 8'h5A, generic_esr = 8'h96;
    reg [8:0] spinner = 0;
    wire [7:0] dial_position, dial_consumed, teeter_in0, cpu_mux_data;
    reg [7:0] CPU_databus_in = 0;
    reg [7:0] cpu_sampled_data = 0;
    reg teeter_read_pending = 0;
    integer errors = 0;

    always #5 clk = ~clk;

    wire [7:0] teeter_base = 8'hBB; // Teeter idle IN0, including unused bits 5 and 3 high.
    wire selected_teeter_esr = profile_d0 && cpu_rw_n && RAMSEL && ROMSEL &&
        SRAMSEL && CHARSEL && EXTVID && !IOSEL && (addr_lo == 2'b01);
    wire [7:0] selected_esr = profile_d0 ? teeter_in0 : generic_esr;

    // Exact priority among the relevant clauses in Exidy2's registered read mux.
    assign cpu_mux_data = (!RAMSEL && cpu_rw_n) ? ram_data :
                          (!ROMSEL && cpu_rw_n) ? rom_data :
                          (!SRAMSEL && cpu_rw_n) ? 8'h3C :
                          (!CHARSEL && cpu_rw_n) ? 8'hC3 :
                          (!EXTVID && cpu_rw_n) ? 8'hE7 :
                          (!IOSEL && addr_lo == 2'b01 && cpu_rw_n) ? selected_esr :
                          8'hFF;

    wire read_strobe = teeter_read_pending && ph1 && !pause;
    teeterControls controls(
        .clk_sys(clk), .reset(reset), .paused(pause), .ce_frame(1'b0),
        .dpad_position_mode(1'b0), .spinner(spinner), .analog_x(8'sd0),
        .dpad_left(1'b0), .dpad_right(1'b0),
        .cpu_read_strobe(read_strobe), .cpu_read_data(CPU_databus_in),
        .in0_other(teeter_base), .dial_position(dial_position),
        .dial_consumed(dial_consumed), .in0_value(teeter_in0)
    );

    always @(posedge clk) begin
        if (reset) begin
            CPU_databus_in <= 8'h00;
            teeter_read_pending <= 1'b0;
            cpu_sampled_data <= 8'h00;
        end else begin
            CPU_databus_in <= cpu_mux_data;
            teeter_read_pending <= selected_teeter_esr;
            if (ph1 && !pause)
                cpu_sampled_data <= CPU_databus_in;
        end
    end

    task automatic check(input bit ok, input string message);
        if (!ok) begin errors = errors + 1; $display("FAIL %s", message); end
    endtask
    task automatic tick; begin @(posedge clk); #1; end endtask
    task automatic cpu_read_edge;
        begin @(negedge clk); ph1 = 1; tick(); @(negedge clk); ph1 = 0; end
    endtask

    initial begin
        tick(); reset = 0; tick();
        check(teeter_in0 == 8'hBB, "Teeter idle byte has unused bits high");

        // One reverse spinner step creates a positive MAME dial event.
        @(negedge clk); spinner = {1'b1, 8'hFF}; tick();
        tick(); // register the current IN0 event byte and its selected qualifier
        check(teeter_in0 == 8'hFF && teeter_read_pending, "IN0 event and qualifier selected together");
        repeat (2) tick();
        check(dial_consumed == 0, "read source alone does not consume without PH_1");
        cpu_read_edge();
        check(cpu_sampled_data == 8'hFF && dial_consumed == 1,
              "PH_1 consumes the exact previous registered IN0 event byte");

        // A higher-priority RAM source wins even with IOSEL/address also matching.
        @(negedge clk); spinner = {1'b0, 8'hFF}; RAMSEL = 0; tick();
        check(CPU_databus_in == 8'hA5 && !teeter_read_pending,
              "RAM priority suppresses the Teeter read qualifier");
        cpu_read_edge();
        check(cpu_sampled_data == 8'hA5 && dial_consumed == 1,
              "RAM byte is sampled without consuming the queued dial event");

        // ROM has the next higher priority and must also suppress consumption.
        @(negedge clk); RAMSEL = 1; ROMSEL = 0; tick();
        check(CPU_databus_in == 8'h5A && !teeter_read_pending,
              "ROM priority suppresses the Teeter read qualifier");
        cpu_read_edge();
        check(cpu_sampled_data == 8'h5A && dial_consumed == 1,
              "ROM byte is sampled without consuming the queued dial event");

        @(negedge clk); ROMSEL = 1; SRAMSEL = 0; tick();
        check(CPU_databus_in == 8'h3C && !teeter_read_pending,
              "screen RAM priority suppresses the Teeter read qualifier");
        cpu_read_edge();
        check(cpu_sampled_data == 8'h3C && dial_consumed == 1,
              "screen RAM byte is sampled without consuming the event");

        @(negedge clk); SRAMSEL = 1; CHARSEL = 0; tick();
        check(CPU_databus_in == 8'hC3 && !teeter_read_pending,
              "character RAM priority suppresses the Teeter read qualifier");
        cpu_read_edge();
        check(cpu_sampled_data == 8'hC3 && dial_consumed == 1,
              "character RAM byte is sampled without consuming the event");

        @(negedge clk); CHARSEL = 1; EXTVID = 0; tick();
        check(CPU_databus_in == 8'hE7 && !teeter_read_pending,
              "extended video RAM priority suppresses the Teeter read qualifier");
        cpu_read_edge();
        check(cpu_sampled_data == 8'hE7 && dial_consumed == 1,
              "extended video RAM byte is sampled without consuming the event");

        // Restore true IN0 selection. Pause/RDY blocks both CPU sampling and consumption.
        @(negedge clk); EXTVID = 1; tick();
        check(teeter_read_pending && CPU_databus_in[6], "pending byte records a selected dial event");
        @(negedge clk); pause = 1; ph1 = 1; tick();
        check(dial_consumed == 1, "paused PH_1/RDY stall cannot consume");
        @(negedge clk); pause = 0; ph1 = 0;
        cpu_read_edge();
        check(cpu_sampled_data[6] && dial_consumed == 2,
              "resumed ready PH_1 consumes the held registered IN0 byte once");

        // Non-Teeter profile selects the generic ESR and never consumes dial state.
        @(negedge clk); profile_d0 = 0; generic_esr = 8'h96; tick();
        check(CPU_databus_in == 8'h96 && !teeter_read_pending,
              "non-Teeter profile keeps generic ESR and masks Teeter read event");
        if (errors != 0) $fatal(1, "Teeter integration mux: %0d failures", errors);
        $display("PASS Teeter integration mux"); $finish;
    end
endmodule
