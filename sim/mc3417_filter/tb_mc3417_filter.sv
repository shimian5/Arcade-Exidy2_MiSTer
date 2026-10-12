`timescale 1ns/1ps
module tb_mc3417_filter;
    localparam integer TOL_Q24 = 256;
    reg clk = 0;
    reg cold_reset_n = 0;
    reg sample_ce = 0;
    reg signed [31:0] sample_q24 = 0;
    reg signed [15:0] audio_base = 0;
    reg mute = 0;
    wire signed [31:0] filtered_q24;
    wire signed [15:0] pcm;
    wire pcm_valid, overrun;
    wire signed [15:0] mono;
    wire clipped;
    reg signed [15:0] mix_speech = 0;
    wire signed [15:0] mix_mono;
    wire mix_clipped;

    exidyMc3417Filter dut (
        .clk(clk), .cold_reset_n(cold_reset_n), .sample_ce(sample_ce),
        .sample_q24(sample_q24), .audio_base(audio_base), .mute(mute),
        .filtered_q24(filtered_q24), .pcm(pcm), .pcm_valid(pcm_valid),
        .overrun(overrun), .mono(mono), .clipped(clipped)
    );
    exidySpeechMix mix_fixture (
        .base(audio_base), .speech(mix_speech), .mute(mute),
        .mono(mix_mono), .clipped(mix_clipped)
    );
    always #5 clk = ~clk;

    integer checks = 0;
    integer fd, rc, sample_no, case_count, sample_count, delta, max_error;
    integer pcm_expected;
    integer stimulus, expected;
    reg [255:0] case_name, previous_case;
    reg signed [31:0] held_filter;

    task automatic reset_filter;
        begin
            @(negedge clk); cold_reset_n = 0; sample_ce = 0; sample_q24 = 0;
            repeat (3) @(posedge clk);
            @(negedge clk); cold_reset_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_vector(input integer x, input integer want,
                              input [255:0] label, input integer index);
        integer n;
        begin
            @(negedge clk); sample_q24 = x; sample_ce = 1;
            @(negedge clk); sample_ce = 0;
            n = 0;
            while ((pcm_valid !== 1'b1) && (n < 20)) begin
                @(posedge clk); #1; n = n + 1;
            end
            if (pcm_valid !== 1'b1)
                $fatal(1, "filter output timeout case=%0s sample=%0d", label, index);
            delta = $signed(filtered_q24) - want;
            if (delta < 0) delta = -delta;
            if (delta > TOL_Q24)
                $fatal(1, "oracle mismatch case=%0s sample=%0d input=%0d got=%0d expected=%0d error=%0d",
                       label, index, x, filtered_q24, want, delta);
            if (delta > max_error) max_error = delta;
            if (overrun !== 1'b0)
                $fatal(1, "unexpected overrun at valid output case=%0s sample=%0d", label, index);
            pcm_expected = $signed(filtered_q24) >>> 9;
            if (pcm_expected > 32767) pcm_expected = 32767;
            if (pcm_expected < -32768) pcm_expected = -32768;
            if ($signed(pcm) !== pcm_expected[15:0])
                $fatal(1, "PCM conversion mismatch case=%0s sample=%0d filtered=%0d pcm=%0d expected=%0d",
                       label, index, filtered_q24, pcm, pcm_expected);
            checks = checks + 1;
            // The 192 kHz cadence is 75 master clocks. Let the pipeline settle
            // to the next input slot and ensure output state remains stable.
            held_filter = filtered_q24;
            repeat (74-n) @(posedge clk);
            #1;
            if (filtered_q24 !== held_filter)
                $fatal(1, "filter changed without sample_ce case=%0s sample=%0d", label, index);
        end
    endtask

    task automatic check_mix(input integer base, input integer speech,
                             input bit is_muted, input integer wanted,
                             input bit did_clip, input [255:0] label);
        begin
            audio_base = base; mute = is_muted;
            mix_speech = speech;
            #1;
            if ($signed(mix_mono) !== wanted || mix_clipped !== did_clip)
                $fatal(1, "mixer %0s base=%0d speech=%0d mute=%0d got=%0d clip=%0d expected=%0d clip=%0d",
                       label, base, speech, is_muted, mix_mono, mix_clipped, wanted, did_clip);
            checks = checks + 1;
        end
    endtask

    initial begin
        previous_case = "";
        case_count = 0; sample_count = 0; max_error = 0;
        reset_filter();
        fd = $fopen("vectors.tsv", "r");
        if (fd == 0) $fatal(1, "cannot open vectors.tsv in run directory");
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%s %d %d %d\n", case_name, sample_no, stimulus, expected);
            if (rc == 4) begin
                if (case_name != previous_case) begin
                    reset_filter();
                    previous_case = case_name;
                    case_count = case_count + 1;
                end
                run_vector(stimulus, expected, case_name, sample_no);
                sample_count = sample_count + 1;
            end
        end
        $fclose(fd);
        if (case_count < 8 || sample_count < 10000)
            $fatal(1, "reference vectors incomplete: cases=%0d samples=%0d", case_count, sample_count);

        // Repeated CE before the filter pipeline can accept another sample
        // must set the sticky overrun indication.
        reset_filter();
        @(negedge clk); sample_ce = 1; sample_q24 = 32'sh10000000;
        repeat (2) @(negedge clk);
        sample_ce = 0;
        repeat (24) @(posedge clk);
        #1;
        if (overrun !== 1'b1) $fatal(1, "back-to-back CE did not set overrun");
        checks = checks + 1;

        check_mix(0, 0, 0, 0, 0, "zero rails");
        check_mix(16000, 12000, 0, 28000, 0, "positive mix");
        check_mix(-16000, -12000, 0, -28000, 0, "negative mix");
        check_mix(32767, 1000, 0, 32767, 1, "positive saturation");
        check_mix(-32768, -1000, 0, -32768, 1, "negative saturation");
        check_mix(1200, -2400, 1, 0, 0, "mute");

        $display("PASS mc3417_filter oracle fixture: %0d checks, %0d cases, %0d vectors, max Q24 error %0d",
                 checks, case_count, sample_count, max_error);
        $finish;
    end
endmodule
