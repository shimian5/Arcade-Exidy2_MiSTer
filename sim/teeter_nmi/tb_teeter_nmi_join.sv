`timescale 1ns/1ps
// Direct mixed-language join of the production Teeter NMI generator and T65.
module tb_teeter_nmi_join;
    localparam integer PERIOD = 75260;
    logic clk = 0;
    logic reset_n = 0;
    logic profile = 1;
    logic pause = 0;
    logic [5:0] phase_count = 0;
    logic ph1_enable = 0;
    wire nmi_n;
    wire rw_n, sync, ef, mf, xf, ml_n, vp_n, vda, vpa, ph3;
    wire [23:0] address;
    wire [7:0] do_bus;
    wire [63:0] regs;
    wire nmi_ack;
    logic [7:0] memory [0:65535];
    wire [7:0] di = memory[address[15:0]];
    integer ticks = 0;
    logic [23:0] paused_address;

    always #5 clk = ~clk;

    exidyTeeterNmi #(.PERIOD_TICKS(PERIOD)) generator (
        .clk(clk), .reset_n(reset_n), .teeter_profile(profile),
        .ph1_enable(ph1_enable), .nmi_n(nmi_n)
    );

    // Match Exidy2's registered PH_1 compare cadence (one enable every 64 clocks).
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            phase_count <= 0;
            ph1_enable <= 0;
        end else begin
            ph1_enable <= (phase_count == 31);
            phase_count <= (phase_count == 63) ? 0 : phase_count + 1'b1;
        end
    end

    T65 cpu (
        .Mode(2'b00), .BCD_en(1'b1), .Res_n(reset_n), .Enable(ph1_enable),
        .Clk(clk), .Rdy(!pause), .Abort_n(1'b1), .IRQ_n(1'b1), .NMI_n(nmi_n),
        .SO_n(1'b1), .R_W_n(rw_n), .Sync(sync), .EF(ef), .MF(mf), .XF(xf),
        .ML_n(ml_n), .VP_n(vp_n), .VDA(vda), .VPA(vpa), .PH3(ph3),
        .A(address), .DI(di), .DO(do_bus), .Regs(regs), .DEBUG(), .NMI_ack(nmi_ack)
    );

    always @(posedge clk) ticks <= ticks + 1;

    initial begin
        for (integer i = 0; i < 65536; i++) memory[i] = 8'hEA;
        memory[16'h8000] = 8'h4C; // JMP $8000
        memory[16'h8001] = 8'h00;
        memory[16'h8002] = 8'h80;
        memory[16'h9000] = 8'h40; // RTI
        memory[16'hFFFA] = 8'h00; memory[16'hFFFB] = 8'h90;
        memory[16'hFFFC] = 8'h00; memory[16'hFFFD] = 8'h80;
        memory[16'hFFFE] = 8'h00; memory[16'hFFFF] = 8'h90;

        repeat (4) @(posedge clk);
        #1;
        if (nmi_n !== 1'b1) $fatal(1, "reset did not hold NMI inactive");
        reset_n = 1;

        // Let the real T65 fetch its synthetic reset program.
        wait (address[15:0] == 16'h8000 && rw_n);
        @(negedge clk);
        pause = 1;
        paused_address = address;

        // Wait for the full production nominal 600 Hz interval and its PH_1 capture.
        while (nmi_ack !== 1'b1 && ticks < PERIOD + 256)
            @(posedge clk);
        #1;
        if (nmi_ack !== 1'b1) $fatal(1, "T65 did not capture generator event while paused");
        if (address !== paused_address) $fatal(1, "T65 bus advanced during pause");

        // The generator must release after the PH_1 edge, while the T65 retains the request.
        wait (nmi_n === 1'b1);
        repeat (128) @(posedge clk);
        #1;
        if (nmi_ack !== 1'b1 || address !== paused_address)
            $fatal(1, "paused T65 lost NMI or advanced before resume");

        @(negedge clk);
        pause = 0;
        wait (address[15:0] == 16'h9000 && rw_n);
        $display("PASS actual Teeter NMI generator -> T65: period=%0d paused capture and resume vector", PERIOD);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "watchdog: mixed-language Teeter NMI join timed out");
    end
endmodule
