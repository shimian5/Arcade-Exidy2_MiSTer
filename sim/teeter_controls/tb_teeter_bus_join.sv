`timescale 1ns/1ps
// The bus module is generated from production rtl/Exidy2.v. This fixture joins
// that extracted path to the selected VHDL T65 and the real teeterControls RTL.
module tb_teeter_bus_join;
    logic clk = 0, reset_n = 0, pause = 0;
    logic [5:0] phase_count = 0;
    logic ph1 = 0;
    logic [7:0] pcb = 8'hD0;
    logic [8:0] spinner = 0;
    logic [7:0] memory [0:65535];
    logic [2:0] priority_mode = 0;
    wire rw_n, sync, ef, mf, xf, ml_n, vp_n, vda, vpa, ph3;
    wire [23:0] address;
    wire [7:0] do_bus;
    wire [63:0] regs;
    wire nmi_ack;
    wire [7:0] CPU_RAM_out = (address[15:0] == 16'h5101) ? 8'hA5 : memory[address[15:0]];
    wire [7:0] CPU_PROM_out = (address[15:0] == 16'h5101) ? 8'h5A : memory[address[15:0]];
    wire [7:0] dial_position, dial_consumed;
    wire [7:0] vram_cpu = 8'h3C, vram_char = 8'hC3, vram_ext = 8'hE7;
    wire [7:0] eir_data = 8'hE1, audio_data = 8'hA2, in2_data = 8'h12;
    wire [7:0] dipsw = 8'hD0;
    wire [7:0] bus_di;
    logic RAMSEL, ROMSEL, SRAMSEL, CHARSEL, EXTVID, IOSEL;
    integer ticks = 0;
    integer writes_0200 = 0;
    integer consumed_events = 0;
    reg [7:0] stored_values [0:31];
    reg [7:0] expected_last = 0;
    reg prior_strobe = 0;
    reg [7:0] sampled_byte;
    reg [7:0] generic_byte = 8'h97;

    always #5 clk = ~clk;

    always_comb begin
        // Current Exidy address-map selections for normal CPU operation.
        RAMSEL = (address[15:10] == 6'b000000) ? 1'b0 : 1'b1;
        ROMSEL = (address[15:13] == 3'b100 || address[15:13] == 3'b101 ||
                  address[15:13] == 3'b110 || address[15:13] == 3'b111) ? 1'b0 : 1'b1;
        SRAMSEL = (address[15:10] == 6'b010000) ? 1'b0 : 1'b1;
        CHARSEL = (pcb[5] ? (address[15:11] == 5'b01100) :
                            (address[15:11] == 5'b01001)) ? 1'b0 : 1'b1;
        EXTVID = (address[15:11] == 5'b01101) ? 1'b0 : 1'b1;
        IOSEL = (address[15:8] == 8'h51) ? 1'b0 : 1'b1;

        // Force each exact production priority branch only while T65 is reading IN0.
        if (address[15:0] == 16'h5101) begin
            case (priority_mode)
                3'd1: RAMSEL = 1'b0;
                3'd2: ROMSEL = 1'b0;
                3'd3: SRAMSEL = 1'b0;
                3'd4: CHARSEL = 1'b0;
                3'd5: EXTVID = 1'b0;
                default: begin end
            endcase
        end
    end

    teeterProductionBus bus (
        .master_clock(clk), .RESET_n(reset_n), .PH_1(ph1), .pause(pause),
        .ce_frame(1'b0), .dpad_pos_mode(1'b0), .spinner(spinner),
        .analog_x(8'sd0),
        .m_right(1'b1), .m_left(1'b0), .m_down(1'b0), .m_up(1'b0),
        .m_fire(1'b1), .m_start1p(1'b1), .m_start2p(1'b1),
        .m_coina(1'b1), .m_coinb(1'b1), .pcb(pcb), .DIP1(dipsw),
        .CPU_addrbus(address), .CPU_RWn(rw_n), .CPU_databus_out(do_bus),
        .RAMSEL(RAMSEL), .ROMSEL(ROMSEL), .SRAMSEL(SRAMSEL),
        .CHARSEL(CHARSEL), .EXTVID(EXTVID), .IOSEL(IOSEL),
        .CPU_RAM_out(CPU_RAM_out), .CPU_PROM_out(CPU_PROM_out),
        .VRAM_CPU_out(vram_cpu), .VRAM_out_CSCG1_CPU(vram_char),
        .VRAM_out_CSCG2_CPU(vram_ext), .EIR(eir_data),
        .audio_data_out(audio_data), .IN2(in2_data), .CPU_databus_in(bus_di),
        .dial_position(dial_position), .dial_consumed(dial_consumed)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            phase_count <= 0;
            ph1 <= 0;
        end else begin
            ph1 <= (phase_count == 31);
            phase_count <= (phase_count == 63) ? 0 : phase_count + 1'b1;
        end
    end

    T65 cpu (
        .Mode(2'b00), .BCD_en(1'b1), .Res_n(reset_n), .Enable(ph1),
        .Clk(clk), .Rdy(!pause), .Abort_n(1'b1), .IRQ_n(1'b1), .NMI_n(1'b1),
        .SO_n(1'b1), .R_W_n(rw_n), .Sync(sync), .EF(ef), .MF(mf), .XF(xf),
        .ML_n(ml_n), .VP_n(vp_n), .VDA(vda), .VPA(vpa), .PH3(ph3),
        .A(address), .DI(bus_di), .DO(do_bus), .Regs(regs), .DEBUG(), .NMI_ack(nmi_ack)
    );

    always @(posedge clk) begin
        ticks <= ticks + 1;
        if (reset_n && !rw_n && ph1 && address[15:0] == 16'h0200) begin
            if (writes_0200 < 32) stored_values[writes_0200] <= do_bus;
            writes_0200 <= writes_0200 + 1;
        end
    end

    // Independent scoreboard uses the extracted registered byte and qualifier
    // at the actual PH_1/RDY edge shared with T65.
    always @(posedge clk) begin
        if (!reset_n) begin
            expected_last = 0;
            prior_strobe = 0;
            consumed_events = 0;
        end else begin
            prior_strobe = bus.teeter_read_strobe;
            if (bus.teeter_read_strobe && !bus.TEETER_CONTROLS.cpu_read_strobe_d) begin
                sampled_byte = bus.CPU_databus_in;
                if (sampled_byte[6]) begin
                    expected_last = sampled_byte[2] ? expected_last + 1'b1 : expected_last - 1'b1;
                    consumed_events = consumed_events + 1;
                end
                #1;
                if (dial_consumed !== expected_last)
                    $fatal(1, "consume mismatch: sampled=%02x expected=%02x got=%02x", sampled_byte, expected_last, dial_consumed);
            end
        end
    end

    task automatic wait_for_input_read;
        integer limit;
        begin
            limit = 0;
            while (!(address[15:0] == 16'h5101 && rw_n) && limit < 20000) begin
                @(negedge clk);
                limit = limit + 1;
            end
            if (limit == 20000) $fatal(1, "CPU never reached $5101 read");
        end
    endtask

    task automatic pause_on_input_read;
        begin
            wait_for_input_read();
            @(negedge clk);
            pause = 1;
            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    task automatic release_and_advance;
        begin
            @(negedge clk);
            pause = 0;
            repeat (130) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        for (integer i = 0; i < 65536; i++) memory[i] = 8'hEA;
        // LDA $5101; STA $0200; JMP $8000.
        memory[16'h8000] = 8'hAD; memory[16'h8001] = 8'h01; memory[16'h8002] = 8'h51;
        memory[16'h8003] = 8'h8D; memory[16'h8004] = 8'h00; memory[16'h8005] = 8'h02;
        memory[16'h8006] = 8'h4C; memory[16'h8007] = 8'h00; memory[16'h8008] = 8'h80;
        memory[16'hFFFC] = 8'h00; memory[16'hFFFD] = 8'h80;
        memory[16'hFFFA] = 8'h00; memory[16'hFFFB] = 8'h90;
        memory[16'hFFFE] = 8'h00; memory[16'hFFFF] = 8'h90;

        repeat (4) @(posedge clk);
        #1;
        reset_n = 1;
        @(negedge clk);
        spinner = {1'b1, 8'hFD}; // PORT_REVERSE maps -3 to a +3 dial target.

        // Three consecutive IN0 reads should each consume exactly one count.
        wait_for_input_read();
        while (writes_0200 < 5 && ticks < 30000) @(negedge clk);
        #1;
        if (writes_0200 < 5) $fatal(1, "CPU did not complete five IN0 reads");
        if (stored_values[0] !== 8'hFF || stored_values[1] !== 8'hFF ||
            stored_values[2] !== 8'hFF || stored_values[3] !== 8'hBB)
            $fatal(1, "unexpected actual T65 IN0 samples: %02x %02x %02x %02x", stored_values[0], stored_values[1], stored_values[2], stored_values[3]);
        if (dial_consumed !== 8'd3 || dial_position !== 8'd3)
            $fatal(1, "three IN0 reads should consume three of three counts: position=%02x consumed=%02x", dial_position, dial_consumed);

        // Queue another three counts. For each competing source, hold the CPU
        // on its actual IN0 read, force that production mux priority, and prove
        // the registered selected byte wins while no dial count is consumed.
        @(negedge clk);
        spinner = {1'b0, 8'hFD};
        for (integer mode = 1; mode <= 5; mode++) begin
            pause_on_input_read();
            priority_mode = mode[2:0];
            repeat (2) @(posedge clk);
            #1;
            if (bus.teeter_read_pending !== 1'b0)
                $fatal(1, "priority mode %0d failed to suppress pending Teeter read", mode);
            case (mode)
                1: if (bus_di !== 8'hA5) $fatal(1, "RAM priority byte mismatch: %02x", bus_di);
                2: if (bus_di !== 8'h5A) $fatal(1, "ROM priority byte mismatch: %02x", bus_di);
                3: if (bus_di !== 8'h3C) $fatal(1, "screen RAM priority byte mismatch: %02x", bus_di);
                4: if (bus_di !== 8'hC3) $fatal(1, "character RAM priority byte mismatch: %02x", bus_di);
                5: if (bus_di !== 8'hE7) $fatal(1, "extended video priority byte mismatch: %02x", bus_di);
            endcase
            release_and_advance();
            priority_mode = 0;
            if (dial_consumed !== 8'd3)
                $fatal(1, "priority mode %0d consumed dial state", mode);
        end

        // Non-Teeter profile must return the exact generic ESR byte and keep
        // the Teeter pending qualifier inactive.
        pause_on_input_read();
        pcb = 8'h00;
        repeat (2) @(posedge clk);
        #1;
        if (bus.teeter_read_pending !== 1'b0 || bus_di !== generic_byte)
            $fatal(1, "generic profile mismatch: pending=%b byte=%02x", bus.teeter_read_pending, bus_di);
        release_and_advance();
        if (dial_consumed !== 8'd3) $fatal(1, "generic profile consumed Teeter dial");

        // Restore Teeter and pause on a pending input read for multiple PH_1s.
        pcb = 8'hD0;
        pause_on_input_read();
        repeat (150) @(posedge clk);
        #1;
        if (bus.teeter_read_pending !== 1'b1 || dial_consumed !== 8'd3)
            $fatal(1, "pause failed to preserve pending unconsumed dial event");
        release_and_advance();
        while (dial_consumed != 8'd6 && ticks < 60000) @(negedge clk);
        #1;
        if (dial_consumed !== 8'd6) $fatal(1, "resumed Teeter reads did not consume queued counts");
        $display("PASS source-extracted production Teeter bus + actual T65: first_samples=%02x,%02x,%02x,%02x qualified_consumptions=%0d priority_suppressions=5 generic=%02x pause=held", stored_values[0], stored_values[1], stored_values[2], stored_values[3], consumed_events, generic_byte);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "watchdog: Teeter bus/T65 join timed out");
    end
endmodule
