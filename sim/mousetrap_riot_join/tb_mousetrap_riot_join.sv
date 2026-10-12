`timescale 1ns/1ps
// Reproduces exidyAB's registered auPH0 and the T65 enable relationship.
// The bus model changes only on the audio edge that consumes auPH0=1; the
// RIOT accepts the stable bus on the preceding registered auPH0 rising edge.
module tb_mousetrap_riot_join;
    reg audio_clk=0, reset_n=0;
    reg [3:0] cencnt_au=0;
    reg auPH0=0;
    reg [4:0] audio_addrbus=0;
    reg [7:0] audio_databus_out=0;
    reg audio_nWRITE=1;
    reg io08_0F=1;

    wire predicted_write = (cencnt_au==4'd0) && !auPH0 && !io08_0F && !audio_nWRITE;
    wire [7:0] riot_dout, pa_out, pb_out;
    wire riot_irq_n;
    wire command_commit;
    wire [7:0] command_data;
    wire [7:0] cvsd_data, io_data_out;
    wire z80_reset, decoder_reset_n, digit, pb0;
    reg [7:0] io_addr=0, io_data_in=0;
    reg io_wr=0;

    integer predicted_count=0, actual_count=0;
    reg [7:0] actual_data[0:31];
    reg [4:0] actual_addr[0:31];
    integer errors=0;

    always #5 audio_clk=~audio_clk;
    always @(posedge audio_clk) begin
        cencnt_au <= cencnt_au + 4'd1;
        auPH0 <= (cencnt_au == 4'd0);
        if (reset_n && predicted_write) predicted_count <= predicted_count + 1;
    end

    // The real RIOT sees auPH0 as phi2, exactly as exidyAB does.
    R6532 riot(.phi2(auPH0), .rst_n(reset_n), .cs(!io08_0F), .rw_n(audio_nWRITE),
        .irq_n(riot_irq_n), .add(audio_addrbus), .din(audio_databus_out),
        .dout(riot_dout), .pa_in(8'hff), .pa_out(pa_out),
        .pb_in({7'h7f,pb0}), .pb_out(pb_out));

    // In production the prediction is sampled by this helper on audio_clk.
    mousetrapVoiceCommand callback(.clk(audio_clk), .reset_n(reset_n),
        .accepted_write(predicted_write), .address(audio_addrbus),
        .data(audio_databus_out), .command_commit(command_commit), .command_data(command_data));
    mousetrapVoiceIo voice(.clk(audio_clk), .state_reset_n(reset_n),
        .decoder_reset_n(1'b1), .z80_global_reset(1'b0), .io_addr(io_addr),
        .io_data_in(io_data_in), .io_wr(io_wr), .cvsd_clock_state(1'b0),
        .io_data_out(io_data_out), .riot_pa_write_commit(command_commit),
        .riot_pa_write_data(command_data), .cvsd_data(cvsd_data),
        .z80_reset(z80_reset), .cvsd_decoder_reset_n(decoder_reset_n),
        .cvsd_digit(digit), .riot_pb0_in(pb0));

    // Independently observe actual R6532 clock-edge acceptance.
    always @(posedge auPH0) begin
        if (reset_n && !io08_0F && !audio_nWRITE) begin
            actual_addr[actual_count] = audio_addrbus;
            actual_data[actual_count] = audio_databus_out;
            actual_count = actual_count + 1;
        end
    end

    task automatic tick(input integer n);
        repeat(n) begin @(posedge audio_clk); #1; end
    endtask

    task automatic riot_write(input [4:0] address, input [7:0] value);
        integer old_actual;
        begin
            old_actual=actual_count;
            @(negedge audio_clk);
            io08_0F=0; audio_nWRITE=0; audio_addrbus=address; audio_databus_out=value;
            wait(actual_count==old_actual+1);
            #2;
            if (predicted_count != actual_count) $fatal(1,"predicted/actual acceptance count diverged");
            @(negedge audio_clk); io08_0F=1; audio_nWRITE=1;
            tick(2);
        end
    endtask

    task automatic non_pa_cycle(input [4:0] address, input [7:0] value, input bit is_read);
        integer old_actual, old_predicted;
        begin
            old_actual=actual_count; old_predicted=predicted_count;
            @(negedge audio_clk);
            io08_0F=0; audio_nWRITE=is_read; audio_addrbus=address; audio_databus_out=value;
            if (is_read) begin
                tick(20);
                if (actual_count!=old_actual || predicted_count!=old_predicted)
                    $fatal(1,"read counted as write address=%h",address);
            end else begin
                wait(actual_count==old_actual+1); #2;
                if (actual_count!=old_actual+1 || predicted_count!=old_predicted+1)
                    $fatal(1,"registered pulse missed RIOT write address=%h",address);
            end
            if (command_data!==8'h96) $fatal(1,"non-PA access corrupted PA callback address=%h",address);
            @(negedge audio_clk); io08_0F=1; audio_nWRITE=1;
        end
    endtask

    initial begin
        tick(3); @(negedge audio_clk); reset_n=1;
        tick(3);
        if (command_data!==8'hff || cvsd_data!==8'hff) $fatal(1,"reset callback missing");

        // All upper address aliases are ignored by RIOT PA decode.
        riot_write(5'h18,8'hf6); // mirrored ORA, DDRA inputs => callback FF
        if (command_data!==8'hff || pa_out!==8'hff) $fatal(1,"ORA input callback/pins mismatch");
        riot_write(5'h19,8'hf7); // mirrored DDRA; PA4 output, ORA4=1
        if (command_data!==8'hfe || pa_out!==8'hfe) $fatal(1,"DDRA callback formula mismatch");
        riot_write(5'h00,8'h96);
        if (command_data!==8'h9e || pa_out!==8'h9e) $fatal(1,"ORA callback formula or pins mismatch");
        riot_write(5'h09,8'hef); // consecutive PA-register write (DDRA alias)
        if (command_data!==8'h96 || pa_out!==8'h96) $fatal(1,"back-to-back DDRA callback mismatch");

        non_pa_cycle(5'h00,8'h00,1); // read ORA
        non_pa_cycle(5'h02,8'h00,0); // ORB write: RIOT accepts, callback rejects
        non_pa_cycle(5'h03,8'h00,0); // DDRB write: RIOT accepts, callback rejects
        non_pa_cycle(5'h04,8'h00,0); // timer write: RIOT accepts, callback rejects
        if (actual_count!=7 || predicted_count!=7 || command_data!==8'h96)
            $fatal(1,"reject filtering/count mismatch actual=%0d predicted=%0d",actual_count,predicted_count);

        // Speech OUT $10 drives RIOT PB0 while DDRB selects input; DDRB/ORB
        // must override the external PB0 level in output mode.
        @(negedge audio_clk); io_addr=8'h10; io_data_in=1; io_wr=1;
        tick(2); @(negedge audio_clk); io_wr=0; tick(2);
        riot_write(5'h03,8'h00);
        if (pb0!==1 || pb_out[0]!==1) $fatal(1,"PB0 input did not reach RIOT pin");
        riot_write(5'h03,8'h01); riot_write(5'h02,8'h00);
        if (pb_out[0]!==0) $fatal(1,"RIOT DDRB/ORB output did not override PB0 input");

        if (actual_count!=predicted_count) $fatal(1,"final accepted-write count mismatch");
        if (actual_addr[0]!==5'h18 || actual_addr[1]!==5'h19 ||
            actual_addr[2]!==5'h00 || actual_addr[3]!==5'h09 ||
            actual_addr[4]!==5'h02 || actual_addr[5]!==5'h03 ||
            actual_addr[6]!==5'h04)
            $fatal(1,"actual RIOT accepted-write address sequence mismatch");
        $display("PASS registered auPH0 RIOT join accepted=%0d callback=ff/fe/9e/96 non-PA filtered PB0=ok",actual_count);
        $finish;
    end

    initial begin #100us; $fatal(1,"registered auPH0 RIOT join watchdog"); end
endmodule
