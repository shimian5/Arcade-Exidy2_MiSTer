`timescale 1ns/1ps
// Stopped-clock and skew adversaries for per-domain reset release.
// Two domains: clk (20 ns) and cvsd_clk (100 ns), each with a gate.
module tb_reset_release;
    logic reset_n = 1;
    logic clk = 0, cvsd_clk = 0;
    logic clk_run = 1, cvsd_run = 1;
    wire  rn_main, rn_cvsd;
    int errors = 0;
    always #10 if (clk_run) clk = ~clk;
    always #50 if (cvsd_run) cvsd_clk = ~cvsd_clk;

`ifdef UNSAFE
    exidy_reset_sync_unsafe m(.clk(clk),.reset_n(reset_n),.reset_n_sync(rn_main));
    exidy_reset_sync_unsafe c(.clk(cvsd_clk),.reset_n(reset_n),.reset_n_sync(rn_cvsd));
`else
    exidy_reset_sync m(.clk(clk),.reset_n(reset_n),.reset_n_sync(rn_main));
    exidy_reset_sync c(.clk(cvsd_clk),.reset_n(reset_n),.reset_n_sync(rn_cvsd));
`endif

    task automatic check(input bit cond, input string msg);
        if (!cond) begin errors++; $display("FAIL: %s @%0t", msg, $time); end
    endtask

    // Release may only be observed at a rising edge of its own clock.
    time last_main = 0, last_cvsd = 0;
    always @(posedge clk) last_main = $time;
    always @(posedge cvsd_clk) last_cvsd = $time;
    always @(posedge rn_main) check($time == last_main, "main release not on clock edge");
    always @(posedge rn_cvsd) check($time == last_cvsd, "cvsd release not on clock edge");

    int edges;
    initial begin
        // 0. Power-up with source released and clocks running: flushed by edges.
        reset_n = 0; #1; check(rn_main===0 && rn_cvsd===0, "reset not asserted at start");
        #200;

        // 1. Release with both clocks running: exactly 2 edges of latency per domain.
        @(negedge clk); reset_n = 1; // mid-cycle release
        edges = 0;
        #1; check(rn_cvsd===0, "cvsd released with no clock edge");
        repeat (4) begin @(posedge clk); #1; edges++; if (edges==1) check(rn_main===0, "main released after 1 edge"); end
        check(rn_main===1, "main not released after 4 edges");
        repeat (2) @(posedge cvsd_clk); #1; check(rn_cvsd===1, "cvsd not released");

        // 2. Asynchronous assertion with BOTH clocks stopped.
        clk_run = 0; cvsd_run = 0; #5;
        reset_n = 0; #1;
        check(rn_main===0 && rn_cvsd===0, "async assert needs a clock");
        // 3. Release with clocks stopped: outputs must hold in reset.
        reset_n = 1; #1000;
        check(rn_main===0 && rn_cvsd===0, "release leaked through stopped clocks");

        // 4. Only cvsd clock restarts: main stays in reset, cvsd releases.
        cvsd_run = 1; #1000;
        check(rn_cvsd===1, "cvsd did not release after its clock restarted");
        check(rn_main===0, "main released by the wrong clock");
        // 5. Main clock restarts later.
        clk_run = 1; #200;
        check(rn_main===1, "main did not release after its clock restarted");

        // 6. Short glitch (< 1 clock period) with clocks running must still reset
        //    and then hold for the full synchronizer depth.
        @(negedge clk); reset_n = 0; #3; reset_n = 1;
        check(rn_main===0, "glitch did not assert");
        @(posedge clk); #1; check(rn_main===0, "glitch released after 1 edge");
        repeat (3) @(posedge clk); #1; check(rn_main===1, "glitch never released");

        // 7. Release immediately before a clock edge (skew corner): still >=2 edges.
        @(negedge clk); reset_n = 0; #2; @(negedge clk); #7; reset_n = 1; // 1 ns before posedge
        @(posedge clk); #1; check(rn_main===0, "near-edge release skipped meta stage");
        repeat (3) @(posedge clk); #1; check(rn_main===1, "near-edge release never completed");

        if (errors == 0) $display("PASS reset-release adversaries");
        else $display("FAILED %0d reset-release checks", errors);
        $finish;
    end
    initial begin #2_000_000; $display("TIMEOUT"); $finish(1); end
endmodule
