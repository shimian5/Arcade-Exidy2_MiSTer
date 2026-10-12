`timescale 1ns/1ps
module tb_mc3417_stream #(parameter integer RAMP_TICKS=13, IDLE_TICKS=6000);
    localparam integer EXPECTED_RAMP_TICKS=13;
    localparam integer EXPECTED_IDLE_TICKS=6000;
    reg clk=0, cold_reset_n=0, sample_ce=0, clock_transition=0, sample_valid=0;
    reg signed [31:0] sample_q24=0;
    wire signed [31:0] pcm_q24;
    wire idle;

    exidyMc3417Stream #(.RAMP_TICKS(RAMP_TICKS), .IDLE_TICKS(IDLE_TICKS)) dut(
        .clk(clk), .cold_reset_n(cold_reset_n), .sample_ce(sample_ce),
        .clock_transition(clock_transition), .sample_valid(sample_valid),
        .sample_q24(sample_q24), .pcm_q24(pcm_q24), .idle(idle));
    always #5 clk=~clk;

    integer checks=0;
    reg signed [31:0] held;

    task automatic tick(input reg ce, input reg transition, input reg valid,
                        input reg signed [31:0] sample);
        begin
            @(negedge clk);
            sample_ce=ce; clock_transition=transition;
            sample_valid=valid; sample_q24=sample;
            @(posedge clk); #1;
        end
    endtask

    task automatic expect_pcm(input reg signed [31:0] expected, input [255:0] label);
        begin
            if (pcm_q24 !== expected)
                $fatal(1,"%0s: pcm=%0d expected=%0d",label,pcm_q24,expected);
            checks=checks+1;
        end
    endtask

    task automatic expect_idle(input reg expected, input [255:0] label);
        begin
            if (idle !== expected)
                $fatal(1,"%0s: idle=%b expected=%b",label,idle,expected);
            checks=checks+1;
        end
    endtask

    integer i, j;
    reg signed [31:0] minval, maxval;
    reg [31:0] rng;
    reg signed [31:0] random_target;
    reg signed [63:0] model_current, model_delta, model_step, model_value;
    initial begin
        minval=32'sh80000000; maxval=32'sh7fffffff;
        // Cold reset clears all public state. A valid sample captures a target
        // but cannot change the PCM on that edge, even when CE is also high.
        repeat(2) @(posedge clk);
        #1; expect_pcm(0,"cold reset pcm"); expect_idle(0,"cold reset idle");
        @(negedge clk); cold_reset_n=1;
        tick(1,0,1,maxval); expect_pcm(0,"sample capture holds output");
        expect_idle(0,"activity clears idle");

        // Extreme signed delta, positive and negative, and truncation toward
        // zero for a negative non-integral quotient.
        for(i=1;i<=EXPECTED_RAMP_TICKS;i=i+1) begin
            tick(1,0,0,0);
            if(i<RAMP_TICKS) expect_pcm(i*165191049,"positive extreme ramp step");
        end
        expect_pcm(maxval,"positive ramp exact endpoint");
        tick(0,0,1,minval); expect_pcm(maxval,"negative target capture holds");
        for(i=1;i<=EXPECTED_RAMP_TICKS;i=i+1) begin
            tick(1,0,0,0);
            if(i<RAMP_TICKS) expect_pcm(maxval-i*330382099,"negative extreme ramp step");
        end
        expect_pcm(minval,"negative ramp exact endpoint");

        // Small negative remainder: -7/13 truncates to zero; final tick snaps.
        tick(0,0,1,minval+7); expect_pcm(minval,"small delta capture");
        repeat(EXPECTED_RAMP_TICKS-1) begin tick(1,0,0,0); expect_pcm(minval,"zero quotient holds"); end
        tick(1,0,0,0); expect_pcm(minval+7,"small delta exact endpoint");

        // Interrupt a ramp. The replacement delta is from the current output,
        // and the new sample edge itself does not advance the ramp.
        tick(0,0,1,0); expect_pcm(minval+7,"zero target capture");
        repeat(3) tick(1,0,0,0);
        held=pcm_q24; expect_pcm(held,"partial first ramp");
        tick(1,0,1,130); expect_pcm(held,"coincident capture and CE holds");
        for(i=1;i<=EXPECTED_RAMP_TICKS;i=i+1) tick(1,0,0,0);
        expect_pcm(130,"interrupted ramp reaches new exact target");

        // A transition resets idle age and clears idle, while CE can still
        // advance an in-flight ramp on that same edge.
        tick(0,0,1,260); expect_pcm(130,"transition test sample capture");
        tick(1,1,0,0); expect_pcm(140,"transition and CE advance ramp");
        expect_idle(0,"transition clears idle");
        repeat(EXPECTED_RAMP_TICKS-1) tick(1,0,0,0);
        expect_pcm(260,"transition ramp endpoint");
        tick(0,1,0,0); // Establish a known zero age for the timeout boundary.

        // Timeout is the first CE tick beyond IDLE_TICKS. Trigger holds output;
        // following ramp ticks decay to zero. IDLE_TICKS is overridden by the
        // runner's default invocation and negative control.
        for(i=0;i<EXPECTED_IDLE_TICKS;i=i+1) tick(1,0,0,0);
        expect_idle(0,"not idle at exact age threshold");
        tick(1,0,0,0); expect_idle(1,"idle on first tick beyond threshold");
        expect_pcm(260,"timeout trigger holds pcm");
        for(i=1;i<=EXPECTED_RAMP_TICKS;i=i+1) tick(1,0,0,0);
        expect_pcm(0,"idle ramp reaches zero"); expect_idle(1,"idle persists");

        // Either kind of activity exits idle. A decoded sample also starts a
        // new ramp and holds output on its capture edge.
        tick(0,0,1,19); expect_pcm(0,"post-idle sample capture holds");
        expect_idle(0,"valid sample exits idle");
        for(i=1;i<=EXPECTED_RAMP_TICKS;i=i+1) tick(1,0,0,0);
        expect_pcm(19,"post-idle sample ramp");

        // Seeded full-width target sequence. Each transition is checked at
        // every tick against a 64-bit signed division model independent of
        // the RTL reciprocal implementation.
        rng=32'h6d2b79f5;
        model_current=pcm_q24;
        for(i=0;i<200;i=i+1) begin
            rng=rng*32'd1664525+32'd1013904223;
            random_target=rng;
            model_delta=$signed({{32{random_target[31]}},random_target})-model_current;
            model_step=model_delta/13;
            tick(0,0,1,random_target);
            expect_pcm(model_current[31:0],"random target capture holds output");
            for(j=1;j<=EXPECTED_RAMP_TICKS;j=j+1) begin
                tick(1,0,0,0);
                if(j==EXPECTED_RAMP_TICKS)
                    model_value=$signed({{32{random_target[31]}},random_target});
                else
                    model_value=model_current+model_step*j;
                expect_pcm(model_value[31:0],"random ramp arithmetic");
            end
            model_current=$signed({{32{random_target[31]}},random_target});
        end

        // Cold reset during nonzero state clears PCM and idle synchronously.
        @(negedge clk); cold_reset_n=0; sample_ce=1; sample_valid=0; clock_transition=0;
        @(posedge clk); #1; expect_pcm(0,"cold reset clears pcm"); expect_idle(0,"cold reset clears idle");
        @(negedge clk); cold_reset_n=1; sample_ce=0;

        // The renderer has no warm-reset input; an externally managed warm
        // reset therefore leaves this block untouched when no events occur.
        tick(0,0,1,77); tick(1,0,0,0); held=pcm_q24;
        repeat(4) begin tick(0,0,0,0); expect_pcm(held,"no CE holds pcm"); end
        $display("PASS mc3417_stream directed fixture checks=%0d",checks);
        $finish;
    end

    initial begin
        #2s; $fatal(1,"mc3417_stream fixture watchdog");
    end
endmodule
