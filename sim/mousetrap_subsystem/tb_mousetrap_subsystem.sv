`timescale 1ns/1ps
module tb_mousetrap_subsystem;
    reg clk=0, state_reset_n=0, decoder_reset_n=0;
    reg global_reset=0, pause=0, speech_enable=0, image_ready=0;
    reg command_commit=0;
    reg [7:0] command_data=8'h11;
    reg rom_ready=0;
    reg [7:0] rom_data=0;
    reg signed [15:0] audio_base=16'sd1234;
    wire rom_read;
    wire [13:0] rom_addr;
    wire signed [15:0] mono;
    wire busyPB0, overflow;
    reg [7:0] rom [0:16383];
    reg pending=0;
    reg [13:0] pending_addr=0;
    integer pending_delay=0;
    integer rom_reads=0, rom_responses=0, io_writes=0;
    integer decoder_events=0, sample_ticks=0, filter_outputs=0;
    integer nonzero_filter_outputs=0, nonzero_mono=0, cpu_enables=0;
    integer rc_toggles=0, render_enables=0;
    reg prev_io_wr=0;
    reg [255:0] first_digits;
    integer digit_count=0;
    integer cpu_start, rc_start, sample_start;
    string rom_path;
    wire cpu_reset = dut.cpu_reset;

    always #34.802816 clk=~clk; // CLK_HZ = 14,366,883 Hz

    mousetrapSpeechSubsystem #(.CLK_HZ(14366883)) dut (
        .clk(clk), .state_reset_n(state_reset_n),
        .decoder_reset_n(decoder_reset_n), .global_reset(global_reset),
        .pause(pause), .speech_enable(speech_enable), .image_ready(image_ready),
        .command_commit(command_commit), .command_data(command_data),
        .rom_read(rom_read), .rom_addr(rom_addr), .rom_ready(rom_ready),
        .rom_data(rom_data), .audio_base(audio_base), .mono(mono),
        .busyPB0(busyPB0), .overflow(overflow)
    );

    // One outstanding read, deterministic variable response delay (3..11
    // audio clocks), and ordered synchronous data capture from staged ROM.
    always @(posedge clk) begin
        rom_ready <= 1'b0;
        if (rom_read) begin
            if (pending) $fatal(1,"overlapping ROM request while response pending");
            pending <= 1'b1;
            pending_addr <= rom_addr;
            pending_delay <= 3 + (rom_reads % 9);
            rom_reads <= rom_reads + 1;
        end else if (pending) begin
            if (pending_delay==0) begin
                rom_data <= rom[pending_addr];
                rom_ready <= 1'b1;
                pending <= 1'b0;
                rom_responses <= rom_responses + 1;
            end else pending_delay <= pending_delay - 1;
        end
    end

    always @(posedge clk) begin
        if (state_reset_n) begin
            if (dut.cpu_ce) cpu_enables <= cpu_enables + 1;
            if (dut.rc_toggle) rc_toggles <= rc_toggles + 1;
            if (dut.sample_ce) render_enables <= render_enables + 1;
            if (dut.decoder_event_d) decoder_events <= decoder_events + 1;
            if (dut.sample_ce_d) sample_ticks <= sample_ticks + 1;
            if ($isunknown({dut.cvsd_digit,dut.decoder_sample_q24,
                            dut.decoder_history,dut.stream_q24,
                            dut.speech_pcm,mono,busyPB0}))
                $fatal(1,"unknown value in digit/decoder/renderer/filter path");
            if (dut.pcm_valid) begin
                filter_outputs <= filter_outputs + 1;
                if (dut.speech_pcm != 0) nonzero_filter_outputs <= nonzero_filter_outputs + 1;
            end
            if (mono != 0 && mono != audio_base) nonzero_mono <= nonzero_mono + 1;
            if (overflow) $fatal(1,"filter overrun or clipping flagged");
            if (dut.cpu_io_wr && !prev_io_wr && !cpu_reset) begin
                if ($isunknown({dut.cpu_addr[7:0],dut.cpu_data_out[0]}))
                    $fatal(1,"unknown firmware I/O write/digit");
                io_writes <= io_writes + 1;
                if (!dut.cpu_addr[4]) begin
                    if (digit_count < 32) first_digits[digit_count] <= dut.cpu_data_out[0];
                    digit_count <= digit_count + 1;
                end
            end
        end
        prev_io_wr <= dut.cpu_io_wr;
    end

    task assert_base_audio;
        begin
            repeat (4) begin
                @(negedge clk);
                if (mono !== audio_base) $fatal(1,"disabled/unready speech changed base audio: %0d",mono);
            end
        end
    endtask

    initial begin
        first_digits='0;
        if (!$value$plusargs("ROM=%s",rom_path)) $fatal(1,"ROM path required");
        $readmemh(rom_path,rom);
        repeat (6) @(negedge clk);
        state_reset_n=1;
        decoder_reset_n=1;
        assert_base_audio();
        if (!cpu_reset || rom_reads!=0) $fatal(1,"CPU was not held reset before enable/image readiness");

        image_ready=1;
        speech_enable=1;
        @(negedge clk); command_commit=1;
        @(negedge clk); command_commit=0;
        if (cpu_reset) $fatal(1,"PA4 command callback failed to release speech CPU");

        // Check derived enable rates over a 10 ms window at the production
        // master rate, then prove pause freezes all three generators.
        repeat (4) @(negedge clk);
        cpu_start=cpu_enables; rc_start=rc_toggles; sample_start=render_enables;
        #10ms;
        if ((cpu_enables-cpu_start)<17896 || (cpu_enables-cpu_start)>17899)
            $fatal(1,"CPU enable frequency out of range: %0d / 10ms",cpu_enables-cpu_start);
        if ((rc_toggles-rc_start)<308 || (rc_toggles-rc_start)>311)
            $fatal(1,"RC toggle frequency out of range: %0d / 10ms",rc_toggles-rc_start);
        if ((render_enables-sample_start)<1919 || (render_enables-sample_start)>1921)
            $fatal(1,"sample enable frequency out of range: %0d / 10ms",render_enables-sample_start);
        begin : pause_check
            reg [31:0] cpu_phase_before;
            reg [63:0] rc_phase_before;
            reg [23:0] sample_phase_before;
            integer en_before, rc_before, sample_before;
            pause=1;
            cpu_phase_before=dut.cpu_phase;
            rc_phase_before=dut.rc_phase;
            sample_phase_before=dut.sample_phase;
            en_before=cpu_enables; rc_before=rc_toggles; sample_before=render_enables;
            repeat (20) begin
                @(negedge clk);
                if (mono!==16'sd0 || dut.cpu_ce || dut.rc_toggle || dut.sample_ce)
                    $fatal(1,"pause failed to mute/hold generated enables");
                if (dut.cpu_phase!==cpu_phase_before || dut.rc_phase!==rc_phase_before ||
                    dut.sample_phase!==sample_phase_before)
                    $fatal(1,"phase accumulator moved during pause");
            end
            if (cpu_enables!=en_before || rc_toggles!=rc_before || render_enables!=sample_before)
                $fatal(1,"enable count advanced during pause");
            global_reset=1;
            begin : decoder_hold
                reg [2:0] h;
                reg [31:0] st;
                reg signed [31:0] integ;
                h=dut.decoder_history; st=dut.decoder_step_q24;
                integ=dut.decoder_integrator_q24;
                repeat (5) @(negedge clk);
                if (dut.decoder_history!==h || dut.decoder_step_q24!==st ||
                    dut.decoder_integrator_q24!==integ)
                    $fatal(1,"global CPU reset cleared MC3417 state");
            end
            global_reset=0;
            pause=0;
        end

        #190ms;
        #1;
        if (pending || rom_reads!=rom_responses)
            $fatal(1,"ROM backend did not drain: reads=%0d responses=%0d pending=%0d",rom_reads,rom_responses,pending);
        if (io_writes<1000 || digit_count<1000 || rom_reads<10000 || rom_responses<10000)
            $fatal(1,"firmware coverage too low reads=%0d responses=%0d OUT=%0d",rom_reads,rom_responses,io_writes);
        if (first_digits[31:0] !== 32'b10101010101010101010101101101010)
            $fatal(1,"ordered firmware digit prefix mismatch: %b",first_digits[31:0]);
        if (decoder_events<1000 || sample_ticks<30000 || filter_outputs<30000 ||
            nonzero_filter_outputs<100 || nonzero_mono<100)
            $fatal(1,"audio path activity too low events=%0d ticks=%0d filter=%0d nonzero=%0d mono=%0d",
                decoder_events,sample_ticks,filter_outputs,nonzero_filter_outputs,nonzero_mono);

        // Once disabled, output must return the base channel exactly even
        // with a nonzero filter history and a possibly outstanding ROM read.
        speech_enable=0;
        assert_base_audio();
        if (!cpu_reset) $fatal(1,"speech disable did not hold CPU reset");
        image_ready=0;
        assert_base_audio();
        if (!cpu_reset) $fatal(1,"image-not-ready did not hold CPU reset");

        $display("PASS ordered digits=01010110110101010101010101010101");
        $display("PASS wrapper firmware ROM=%0d responses=%0d OUT=%0d digits=%0d decoder=%0d sampleCE=%0d filter=%0d nonzeroFilter=%0d nonzeroMono=%0d",
            rom_reads,rom_responses,io_writes,digit_count,decoder_events,sample_ticks,
            filter_outputs,nonzero_filter_outputs,nonzero_mono);
        $display("PASS phase clocks pause/global-reset hold and disable/image base-audio gating");
        $finish;
    end

    initial begin #260ms; $fatal(1,"subsystem watchdog"); end
endmodule
