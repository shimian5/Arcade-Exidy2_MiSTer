`timescale 1ns/1ps
module tb_pia_return_negedge;
    logic master_clk = 0;
    logic audio_clk = 0;
    logic master_reset_n = 0;
    logic audio_reset_n_source = 0;
    logic [7:0] audio_byte = 0;
    logic pause_in = 0;
    wire audio_reset_n;
    wire pause_audio;
    wire [7:0] main_byte;
    wire [7:0] data_only_byte;

    logic a_cs=0, a_rw=1;
    logic [1:0] a_addr=0;
    logic [7:0] a_din=0;
    wire [7:0] a_dout;
    wire a_irq_a, a_irq_b;
    wire [7:0] a_pa_o, a_pa_oe, a_pb_o, a_pb_oe;
    logic [7:0] a_pa_i=0, a_pb_i=0;
    wire a_ca2_o, a_ca2_oe, a_cb2_o, a_cb2_oe;
    wire a_ca1, a_cb1;

    logic m_cs=0, m_rw=1;
    logic [1:0] m_addr=0;
    logic [7:0] m_din=0;
    wire [7:0] m_dout;
    wire m_irq_a, m_irq_b;
    wire [7:0] m_pa_o, m_pa_oe, m_pb_o, m_pb_oe;
    logic [7:0] m_pb_i=0;
    wire [7:0] m_pa_i = main_byte;
    wire m_ca2_o, m_ca2_oe, m_cb2_o, m_cb2_oe;
    wire m_ca1, m_cb1;

    logic [7:0] cpu_databus=0, cpu_sample=0;
    logic [5:0] cpu_count=0;
    logic cpu_enable=0;
    integer phase_ns=0;
    integer transaction_count=0;

    exidyResetSync source_reset(.clk(audio_clk), .reset_n(audio_reset_n_source), .reset_n_sync(audio_reset_n));
    exidyPauseSync audio_pause(.audio_clk(audio_clk), .pause_in(pause_in), .pause_audio(pause_audio));
    exidyPiaReturnNegedgeCandidate dut(
        .audio_clk(audio_clk), .master_clk(master_clk),
        .audio_reset_n(audio_reset_n), .master_reset_n(master_reset_n),
        .audio_byte(a_pb_o), .main_byte(main_byte));
    exidyPiaReturnNegedgeDataOnlyControl data_only(
        .audio_clk(audio_clk), .master_clk(master_clk),
        .audio_reset_n(audio_reset_n), .master_reset_n(master_reset_n),
        .audio_byte(a_pb_o), .main_byte(data_only_byte));

    pia6821 audio_pia(
        .clk(audio_clk), .rst(!audio_reset_n), .cs(a_cs), .rw(a_rw), .addr(a_addr), .data_in(a_din), .data_out(a_dout),
        .irqa(a_irq_a), .irqb(a_irq_b), .pa_i(a_pa_i), .pa_o(a_pa_o), .pa_oe(a_pa_oe), .pa_ddr_ovrd(8'h00),
        .ca1(m_cb2_o), .ca2_i(1'b0), .ca2_o(a_ca2_o), .ca2_oe(a_ca2_oe), .pb_i(a_pb_i), .pb_o(a_pb_o), .pb_oe(a_pb_oe),
        .cb1(m_ca2_o), .cb2_i(1'b0), .cb2_o(a_cb2_o), .cb2_oe(a_cb2_oe));
    pia6821 main_pia(
        .clk(master_clk), .rst(!master_reset_n), .cs(m_cs), .rw(m_rw), .addr(m_addr), .data_in(m_din), .data_out(m_dout),
        .irqa(m_irq_a), .irqb(m_irq_b), .pa_i(m_pa_i), .pa_o(m_pa_o), .pa_oe(m_pa_oe), .pa_ddr_ovrd(8'h00),
        .ca1(a_cb2_o), .ca2_i(1'b0), .ca2_o(m_ca2_o), .ca2_oe(m_ca2_oe), .pb_i(m_pb_i), .pb_o(m_pb_o), .pb_oe(m_pb_oe),
        .cb1(a_ca2_o), .cb2_i(1'b0), .cb2_o(m_cb2_o), .cb2_oe(m_cb2_oe));

    // Same related periods as the existing PLL-phase sweep: master 7 ns,
    // audio 22 ns. Phase zero has coincident positive edges at t=0.
    initial begin
        master_clk = 1'b1;
        forever #3.5 master_clk = ~master_clk;
    end
    initial begin
        if (!$value$plusargs("PHASE_NS=%d", phase_ns)) phase_ns = 0;
        #(phase_ns);
        audio_clk = 1'b1;
        forever #11 audio_clk = ~audio_clk;
    end

    // audio_board's main CPU bus register samples PIA data every master edge.
    // T65 uses the prior registered bus at its PH_1 enable, one pulse per 64 ticks.
    always @(posedge master_clk) begin
        cpu_databus <= master_reset_n ? m_dout : 8'h00;
        cpu_enable <= (cpu_count == 6'd31);
        cpu_count <= cpu_count + 1'b1;
        if (!master_reset_n) begin
            cpu_databus <= 8'h00;
            cpu_sample <= 8'h00;
        end else if (cpu_enable && !pause_in) begin
            cpu_sample <= cpu_databus;
        end
    end

    task automatic write_audio(input logic [1:0] addr, input logic [7:0] value);
        @(negedge audio_clk); a_addr=addr; a_din=value; a_rw=0; a_cs=1;
        @(posedge audio_clk); #1; a_cs=0; a_rw=1;
    endtask
    task automatic write_main(input logic [1:0] addr, input logic [7:0] value);
        @(negedge master_clk); m_addr=addr; m_din=value; m_rw=0; m_cs=1;
        @(posedge master_clk); #1; m_cs=0; m_rw=1;
    endtask
    task automatic wait_cpu_ph1;
        do @(posedge master_clk); while (!cpu_enable);
        #1;
    endtask
    task automatic read_response(input logic [7:0] expected);
        wait (m_irq_a === 1'b1);
        #1;
        m_addr=0; m_rw=1; m_cs=0;
        #1;
        if (m_dout !== expected)
            $fatal(1, "stale PIA9 PA at CA1 IRQ phase=%0d got=%02x expected=%02x", phase_ns, m_dout, expected);
        // First PH1 is the modeled earliest CPU bus-read boundary; assert CS
        // immediately afterward and keep the read through the next PH1 sample.
        wait_cpu_ph1(); m_cs=1;
        wait_cpu_ph1();
        if (cpu_sample !== expected)
            $fatal(1, "prior registered CPU bus stale at earliest PH1 phase=%0d got=%02x expected=%02x", phase_ns, cpu_sample, expected);
        @(negedge master_clk); #1; m_cs=0;
        wait (a_cb2_o === 1'b1);
        #1;
        if (m_dout !== expected)
            $fatal(1, "PIA9 response changed before CA2 acknowledgement phase=%0d", phase_ns);
        transaction_count++;
    endtask
    task automatic send_and_check(input logic [7:0] value, input logic [7:0] expected);
        write_audio(2, value);
        read_response(expected);
    endtask

    initial begin
        #100000 $fatal(1, "watchdog stalled phase=%0d progress=%0d", phase_ns, transaction_count);
    end

    initial begin
        // Independent reset assertion and synchronous source reset release.
        repeat (3) @(posedge audio_clk);
        repeat (3) @(posedge master_clk);
        master_reset_n=1; audio_reset_n_source=1;
        repeat (3) @(posedge audio_clk);
        repeat (2) @(negedge master_clk);
        if (main_byte !== 8'h00) $fatal(1, "initial reset did not mask return byte");

        write_main(0, 8'h00); // PIA9 PA DDR inputs
        write_main(1, 8'h25); // CA1 falling edge IRQ, PA-read CA2 handshake
        write_audio(2, 8'hFF); // PIA8 PB DDR outputs
        write_audio(3, 8'h3C); // CB2 set high
        wait (a_cb2_o === 1'b1);
        write_audio(3, 8'h25); // PB write clears CB2; CB1 edge restores it
        write_audio(3, 8'h25);

        send_and_check(8'h00, 8'h00);
        send_and_check(8'hFF, 8'hFF);
        send_and_check(8'hA5, 8'hA5);
        send_and_check(8'h5A, 8'h5A);

        // Partial DDR: undriven PIA inputs are low in the production wiring.
        write_audio(3, 8'h21); write_audio(2, 8'h0F); write_audio(3, 8'h25);
        send_and_check(8'hA5, 8'h05);
        write_audio(3, 8'h21); write_audio(2, 8'hFF); write_audio(3, 8'h25);

        // Pause the CPUs after PB write but before the CA1 notice is consumed.
        write_audio(2, 8'hC3);
        pause_in=1;
        wait (pause_audio === 1'b1);
        wait (m_irq_a === 1'b1);
        #2;
        if (main_byte !== 8'hC3) $fatal(1, "return data did not settle while CPUs paused");
        if (cpu_sample !== 8'h05) $fatal(1, "paused T65 sample advanced unexpectedly");
        pause_in=0;
        wait (pause_audio === 1'b0);
        read_response(8'hC3);

        // Reset while a new reply is pending. Audio source reset is synchronized;
        // PIA9 reset and candidate valid mask assert asynchronously.
        write_audio(2, 8'h96);
        wait (m_irq_a === 1'b1);
        audio_reset_n_source=0;
        repeat (3) @(posedge audio_clk);
        #0.1; // sample after the final source-domain nonblocking updates
        if (dut.audio_byte_stage !== 8'h00) $fatal(1, "source stage did not clear after synchronized reset");
        master_reset_n=0; #0.1;
        if (main_byte !== 8'h00) $fatal(1, "destination reset did not immediately mask retained byte");
        master_reset_n=1;
        #0.1;
        if (main_byte !== 8'h00) $fatal(1, "reset release exposed retained byte before negative edge capture");
        @(negedge master_clk); #0.1;
        if (main_byte !== 8'h00) $fatal(1, "source reset zero failed to propagate on negative edge");
        audio_reset_n_source=1;
        repeat (3) @(posedge audio_clk);

        // Reconfigure after reset; a fresh transaction must still complete.
        write_main(0, 8'h00); write_main(1, 8'h25);
        write_audio(2, 8'hFF); write_audio(3, 8'h3C); wait (a_cb2_o === 1'b1);
        write_audio(3, 8'h25); write_audio(3, 8'h25);
        send_and_check(8'h96, 8'h96);

        // Held data remains hidden across async reset and appears only on the
        // first negative-edge capture after release.
        master_reset_n=0; #0.1;
        if (main_byte !== 8'h00) $fatal(1, "async reset did not mask retained complete byte");
        if (data_only_byte !== 8'h00) $fatal(1, "data-only negative control did not mask during reset");
        master_reset_n=1; #0.1;
        if (main_byte !== 8'h00) $fatal(1, "release exposed stale data without candidate capture edge");
        if (data_only_byte !== 8'h00) $fatal(1, "data-only control exposed byte before valid rising edge");
        @(posedge master_clk); #0.1;
        if (data_only_byte !== 8'h96)
            $fatal(1, "data-only negative control failed to expose retained byte at first rising edge");
        if (main_byte !== 8'h00)
            $fatal(1, "candidate exposed byte before opposite-edge capture");
        @(negedge master_clk); #0.1;
        if (main_byte !== 8'h96) $fatal(1, "valid mask failed to expose captured byte on first negative edge");

        $display("PASS isolated negative-edge PIA return phase=%0d transactions=%0d", phase_ns, transaction_count);
        $finish;
    end
endmodule
