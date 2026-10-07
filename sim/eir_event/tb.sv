`timescale 1ns/1ps
module exidy_eir_event_fixture (
    input wire master_clock, BCLK, VL1, nEIR,
    input wire m_coina, m_coinb,
    input wire [8:0] vscnt,
    input wire [7:0] pcb,
    input wire nM01VDT, nM02VDT, nSGCVID, CBLB, nCBLB,
    output wire [7:0] eir_state,
    output wire irq,
    output wire coint,
    output wire [4:2] cause,
    output wire collision_irq,
    output wire collision_select
);
    reg [7:0] EIR;
    // The runner inserts the guarded source span here, unchanged.
    // It includes declarations and assignments for cDET, rCPU_IRQ, COINT,
    // INT_CAUSE, cDET_sel, and the IRQ/EIR event blocks.
endmodule

module tb;
    reg master_clock=0, BCLK=1, VL1=0, nEIR=1;
    reg m_coina=1, m_coinb=1;
    reg [8:0] vscnt=0;
    reg [7:0] pcb=8'h40; // profile 1, held static during each capture
    reg nM01VDT=1, nM02VDT=1, nSGCVID=1, CBLB=1, nCBLB=1;
    wire [7:0] EIR;
    wire rCPU_IRQ, COINT;
    wire [4:2] int_cause;
    wire int_coll_irq,cDET_sel;
    integer errors=0;

    exidy_eir_event_fixture dut(
        .master_clock(master_clock),.BCLK(BCLK),.VL1(VL1),.nEIR(nEIR),
        .m_coina(m_coina),.m_coinb(m_coinb),.vscnt(vscnt),.pcb(pcb),
        .nM01VDT(nM01VDT),.nM02VDT(nM02VDT),.nSGCVID(nSGCVID),
        .CBLB(CBLB),.nCBLB(nCBLB),.eir_state(EIR),.irq(rCPU_IRQ),
        .coint(COINT),.cause(int_cause),.collision_irq(int_coll_irq),
        .collision_select(cDET_sel));

    task automatic check(input bit ok, input string label);
        if (!ok) begin errors=errors+1; $display("FAIL %s EIR=%02h IRQ=%b COINT=%b cause=%b",label,EIR,rCPU_IRQ,COINT,int_cause); end
        else $display("PASS %s EIR=%02h IRQ=%b COINT=%b cause=%b",label,EIR,rCPU_IRQ,COINT,int_cause);
    endtask
    task automatic master_tick;
        begin master_clock=1; #2; master_clock=0; #2; end
    endtask
    task automatic bclk_fall;
        begin BCLK=1; #1; BCLK=0; #1; end
    endtask
    task automatic bclk_rise;
        begin BCLK=0; #1; BCLK=1; #1; end
    endtask
    task automatic rearm;
        begin
            nEIR=0; #1; check(!rCPU_IRQ,"EIR-read clears IRQ");
            nEIR=1; #1; bclk_fall();
            check(!rCPU_IRQ,"IRQ remains clear without source");
            bclk_rise();
        end
    endtask

    initial begin
        $display("fixture source-extracted Exidy2 IRQ/EIR logic; no reset is modeled");
        // Establish known state by sampling inactive coins and generating one
        // real source event. The production block has no reset for these regs.
        master_tick();
        VL1=1; bclk_fall();
        check(rCPU_IRQ && EIR===8'h84,"profile1 vblank capture (live coin inputs)");
        VL1=0; bclk_rise(); rearm();
        check(EIR===8'h84,"IRQ read-clear preserves EIR snapshot");

        // A COINT rise is produced by master-clock sampling. Change the raw
        // coin level back before BCLK creates the IRQ edge: IRQ uses sampled
        // COINT, while EIR captures the live coin input at its own edge.
        m_coina=0; master_tick();
        check(COINT,"coin fall sampled into COINT");
        m_coina=1; bclk_fall();
        check(rCPU_IRQ && EIR[6]===1'b0,"coin IRQ with live coin restored before EIR capture");
        bclk_rise(); master_tick(); rearm();

        // Profile 1 only passes collision bit 2 to IRQ. With the corresponding
        // collision asserted, the cause latch is inverted to zero, as in RTL.
        nM01VDT=0; nM02VDT=1; nSGCVID=0; CBLB=0; nCBLB=1;
        #1; check(int_coll_irq && int_cause===3'b000,"profile1 collision mask and inverted cause");
        bclk_fall();
        check(rCPU_IRQ && EIR[4:2]===3'b000,"collision IRQ captures source-selected cause");
        nM01VDT=1; nM02VDT=1; nSGCVID=1; CBLB=1; nCBLB=1;
        bclk_rise(); rearm();

        // Assert a new vblank event on the same instant as a read-clear. The
        // source expression gates its set term with nEIR, so read-clear wins;
        // there must be no new posedge of rCPU_IRQ and no EIR recapture.
        VL1=1; #1; nEIR=0; BCLK=0; #1;
        check(!rCPU_IRQ && EIR===8'h80,"simultaneous read-clear and vblank suppresses recapture");
        nEIR=1; VL1=0; BCLK=1; #1;

        // Explicitly test a new event while read-select is held active: EIR
        // and IRQ remain unchanged despite an asserted source.
        nEIR=0; VL1=1; bclk_fall();
        check(!rCPU_IRQ && EIR===8'h80,"source held during EIR read is not captured");
        nEIR=1; VL1=0; bclk_rise();

        if (errors==0) $display("PASS exidy eir event fixture");
        else $display("FAIL exidy eir event fixture errors=%0d",errors);
        $finish;
    end
endmodule
