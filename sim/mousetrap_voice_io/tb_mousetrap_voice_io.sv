`timescale 1ns/1ps
module tb_mousetrap_voice_io;
    logic clk = 0;
    logic state_reset_n = 0;
    logic decoder_reset_n = 1;
    logic z80_global_reset = 1;
    logic [7:0] io_addr = 0, io_data_in = 0;
    logic io_wr = 0, cvsd_clock_state = 0;
    wire [7:0] io_data_out, cvsd_data;
    wire z80_reset, cvsd_decoder_reset_n, cvsd_digit, riot_pb0_in;
    logic inject_pa_commit = 0;
    logic [7:0] inject_pa_data = 0;

    logic riot_rst_n = 0, riot_cs = 0, riot_rw_n = 1;
    logic [4:0] riot_addr = 0;
    logic [7:0] riot_din = 0;
    wire [7:0] riot_dout, riot_pa_out, riot_pb_out;
    wire riot_irq_n;
    logic [7:0] riot_pa_in = 8'hFF;
    wire [7:0] riot_pb_in = {7'h7F, riot_pb0_in};
    logic riot_pa_write_pending = 0;
    logic [7:0] riot_pa_write_pending_data = 0;
    wire helper_pa_write_commit = inject_pa_commit | riot_pa_write_pending;
    wire [7:0] helper_pa_write_data = inject_pa_commit ? inject_pa_data : riot_pa_write_pending_data;

    integer checks = 0;
    reg expected_digit = 0, expected_pb0 = 0;
    reg [7:0] expected_read;
    reg [7:0] write_data_held;

    always #5 clk = ~clk;

    mousetrapVoiceIo dut (
        .clk(clk), .state_reset_n(state_reset_n), .decoder_reset_n(decoder_reset_n),
        .z80_global_reset(z80_global_reset), .io_addr(io_addr),
        .io_data_in(io_data_in), .io_wr(io_wr), .cvsd_clock_state(cvsd_clock_state),
        .io_data_out(io_data_out), .riot_pa_write_commit(helper_pa_write_commit),
        .riot_pa_write_data(helper_pa_write_data), .riot_pa_pins(riot_pa_out),
        .cvsd_data(cvsd_data), .z80_reset(z80_reset),
        .cvsd_decoder_reset_n(cvsd_decoder_reset_n), .cvsd_digit(cvsd_digit),
        .riot_pb0_in(riot_pb0_in)
    );

    R6532 riot (
        .phi2(clk), .rst_n(riot_rst_n), .cs(riot_cs), .rw_n(riot_rw_n),
        .irq_n(riot_irq_n), .add(riot_addr), .din(riot_din), .dout(riot_dout),
        .pa_in(riot_pa_in), .pa_out(riot_pa_out), .pb_in(riot_pb_in), .pb_out(riot_pb_out)
    );

    // The R6532 accepts ORA on phi2 rising, then updates resolved port pins
    // on phi2 falling. Delay the callback commit until those pins have settled.
    always @(posedge clk or negedge riot_rst_n) begin
        if (!riot_rst_n) begin
            riot_pa_write_pending <= 1'b0;
            riot_pa_write_pending_data <= 8'h00;
        end else begin
            riot_pa_write_pending <= riot_cs && !riot_rw_n &&
                (riot_addr[2] == 1'b0) && (riot_addr[1:0] == 2'b00);
            if (riot_cs && !riot_rw_n && (riot_addr[2] == 1'b0) && (riot_addr[1:0] == 2'b00))
                riot_pa_write_pending_data <= riot_din;
        end
    end

    task automatic tick;
        begin @(posedge clk); #1; end
    endtask

    task automatic pulse_status(input [7:0] value);
        begin
            @(negedge clk); inject_pa_data = value; inject_pa_commit = 1;
            tick();
            @(negedge clk); inject_pa_commit = 0;
            tick();
            if (cvsd_data !== value) $fatal(1, "PA status capture %02x became %02x", value, cvsd_data);
        end
    endtask

    task automatic riot_write(input [4:0] address, input [7:0] value);
        begin
            @(negedge clk);
            riot_addr = address; riot_din = value; riot_rw_n = 0; riot_cs = 1;
            tick();
            @(negedge clk);
            riot_cs = 0; riot_rw_n = 1;
            repeat (2) tick();
        end
    endtask

    function automatic [7:0] expected_voice_read(input [7:0] address, input [7:0] data, input bit clock_bit);
        reg [7:0] value;
        begin
            value = 8'hff;
            if (!address[7]) value[3:0] = {data[3], data[0], data[2], data[1]};
            if (!address[6]) value[7] = clock_bit;
            expected_voice_read = value;
        end
    endfunction

    initial begin
        repeat (3) tick();
        state_reset_n = 1;
        riot_rst_n = 1;
        repeat (2) tick();
        if (cvsd_data !== 8'h00 || cvsd_digit !== 1'b0 || riot_pb0_in !== 1'b0)
            $fatal(1, "candidate state reset values are wrong");

        // Exhaustive read truth table: all status bytes, all 256 aliased ports,
        // and both CVSD clock states.
        for (integer data = 0; data < 256; data++) begin
            pulse_status(data[7:0]);
            for (integer address = 0; address < 256; address++) begin
                io_addr = address[7:0];
                cvsd_clock_state = 0;
                #1;
                expected_read = expected_voice_read(address[7:0], data[7:0], 1'b0);
                if (io_data_out !== expected_read)
                    $fatal(1, "voice read mismatch addr=%02x data=%02x clk=0 got=%02x expected=%02x", address, data, io_data_out, expected_read);
                checks = checks + 1;
                cvsd_clock_state = 1;
                #1;
                expected_read = expected_voice_read(address[7:0], data[7:0], 1'b1);
                if (io_data_out !== expected_read)
                    $fatal(1, "voice read mismatch addr=%02x data=%02x clk=1 got=%02x expected=%02x", address, data, io_data_out, expected_read);
                checks = checks + 1;
            end
        end

        // Exhaust every address/data pair. io_wr stays high while D0 changes
        // after the accepted edge; a held T80 transaction must not repeat.
        for (integer address = 0; address < 256; address++) begin
            for (integer data = 0; data < 256; data++) begin
                io_addr = address[7:0]; io_data_in = data[7:0]; io_wr = 0;
                tick();
                @(negedge clk); io_wr = 1;
                tick();
                if (!address[4]) expected_digit = data[0];
                if (!address[5]) expected_pb0 = data[0];
                if (cvsd_digit !== expected_digit || riot_pb0_in !== expected_pb0)
                    $fatal(1, "voice write mismatch addr=%02x data=%02x digit=%b/%b pb0=%b/%b", address, data, cvsd_digit, expected_digit, riot_pb0_in, expected_pb0);
                write_data_held = {data[7:1], ~data[0]};
                @(negedge clk); io_data_in = write_data_held;
                tick();
                if (cvsd_digit !== expected_digit || riot_pb0_in !== expected_pb0)
                    $fatal(1, "held io_wr repeated side effect addr=%02x original=%02x changed=%02x", address, data, write_data_held);
                @(negedge clk); io_wr = 0;
                tick();
                checks = checks + 1;
            end
        end

        // RIOT callback commit is an edge transaction too: changing the
        // callback bus while its commit remains high must not rewrite status.
        @(negedge clk); inject_pa_data = 8'hA5; inject_pa_commit = 1;
        tick();
        @(negedge clk); inject_pa_data = 8'h5A;
        repeat (3) tick();
        if (cvsd_data !== 8'hA5) $fatal(1, "held RIOT PA callback repeated status write");
        @(negedge clk); inject_pa_commit = 0;
        tick();

        // The real R6532 resolves PA pins from ORA and DDRA; use its pa_out
        // as the reset pin while the callback byte remains the raw ORA data.
        z80_global_reset = 0;
        repeat (2) tick();
        if (z80_reset !== 1'b0) $fatal(1, "R6532 reset pin did not initially release Z80");
        riot_write(5'b00001, 8'h10); // DDRA: PA4 output
        if (riot_pa_out[4] !== 1'b0 || z80_reset !== 1'b1)
            $fatal(1, "DDRA output-low PA4 did not assert Z80 reset");
        riot_write(5'b00000, 8'h10); // ORA: PA4 high, callback captures byte
        if (riot_pa_out[4] !== 1'b1 || z80_reset !== 1'b0 || cvsd_data !== 8'h10)
            $fatal(1, "PA4 output-high write did not release/reset-capture correctly");
        riot_write(5'b00000, 8'h00);
        if (riot_pa_out[4] !== 1'b0 || z80_reset !== 1'b1 || cvsd_data !== 8'h00)
            $fatal(1, "PA4 output-low write did not assert/reset-capture correctly");

        // With PA4 configured as input, the physical pin follows PA_IN. The
        // callback byte remains the written ORA byte, showing the two paths.
        riot_pa_in = 8'hFF;
        riot_write(5'b00001, 8'h00); // DDRA: all inputs
        riot_write(5'b00000, 8'h00);
        if (riot_pa_out[4] !== 1'b1 || z80_reset !== 1'b0 || cvsd_data !== 8'h00)
            $fatal(1, "R6532 input PA4 pin/callback data semantics diverged from fixture contract");

        // PB0 is an input writeback unless its DDR selects output; in output
        // mode the R6532 ORB latch dominates the helper's pb_in pin value.
        io_addr = 8'h10; io_data_in = 8'h01; io_wr = 0; tick();
        @(negedge clk); io_wr = 1; tick();
        @(negedge clk); io_wr = 0; tick();
        if (riot_pb0_in !== 1'b1) $fatal(1, "voice I/O write did not set RIOT PB0 input");
        riot_write(5'b00011, 8'h01); // DDRB bit zero output
        riot_write(5'b00010, 8'h00); // ORB bit zero low
        if (riot_pb_out[0] !== 1'b0) $fatal(1, "R6532 DDRB output did not dominate PB0 input");
        riot_write(5'b00011, 8'h00); // DDRB bit zero input
        if (riot_pb_out[0] !== 1'b1) $fatal(1, "R6532 PB0 input pin did not reflect helper writeback");

        // CPU reset does not reset the decoder lifecycle or voice I/O state.
        decoder_reset_n = 1;
        z80_global_reset = 1;
        #1;
        if (z80_reset !== 1'b1 || cvsd_decoder_reset_n !== 1'b1 || cvsd_data !== 8'h00)
            $fatal(1, "Z80 reset incorrectly altered decoder reset or CVSD state");
        decoder_reset_n = 0;
        #1;
        if (cvsd_decoder_reset_n !== 1'b0 || z80_reset !== 1'b1)
            $fatal(1, "decoder reset was not independent from Z80 reset");

        $display("PASS Mouse Trap voice I/O: exhaustive reads=%0d writes=%0d R6532 DDR pins and independent reset", 256*256*2, 256*256);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "watchdog: Mouse Trap voice I/O test timed out");
    end
endmodule
