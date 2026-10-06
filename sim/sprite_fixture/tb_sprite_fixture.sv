module tb_sprite_fixture;
  reg [15:0] CPU_addrbus = 16'h0000;
  reg CPU_RWn = 1'b1;
  reg [7:0] CPU_databus_out = 8'h00;
  reg IOSEL = 1'b1;
  wire nWM2V, nWM2H, nWM1V, nWM1H;
  reg BCLK = 1'b1;
  reg nCBLB = 1'b1;
  reg CBLB = 1'b0;
  reg [8:0] vscnt = 9'd0;
  reg [5:0] hscnt = 6'd0;
  reg [7:0] pcb = 8'h00;

  reg [4:0] M1R = 5'h00, M2R = 5'h00;
  reg [7:0] CPL = 8'h00;
  reg ADSEL = 1'b0;
  reg [7:0] rM1H = 8'h00, rM2H = 8'h00, rM1V = 8'h00, rM2V = 8'h00;
  reg [7:0] M1H = 8'h00, M2H = 8'h00, M1V = 8'h00, M2V = 8'h00;
  wire [10:0] SPRITE_ADDR;

  reg EM1VID = 1'b0, EM2VID = 1'b0;
  reg M1VID = 1'b0, M2VID = 1'b0, SGCVID = 1'b0;
  wire nM01VDT, nM02VDT, nSGCVID;
  reg cDET = 1'b0;

  reg COINT = 1'b0, VL1 = 1'b0, nEIR = 1'b1;
  reg m_coina = 1'b0, m_coinb = 1'b0;
  reg rCPU_IRQ = 1'b0;
  reg [7:0] EIR = 8'h00;

  `include "rtl_extracted.svh"

  task automatic fail(input [8*120-1:0] what);
    begin $display("FAIL %0s", what); $fatal(1); end
  endtask

  task automatic bus_write(input [15:0] address, input [7:0] data, input io_select);
    begin
      CPU_addrbus = 16'h0000; CPU_RWn = 1'b1; IOSEL = 1'b1; #1;
      CPU_databus_out = data; CPU_addrbus = address; CPU_RWn = 1'b0; IOSEL = io_select; #1;
      CPU_RWn = 1'b1; IOSEL = 1'b1; #1;
    end
  endtask

  task automatic clock_bclk;
    begin BCLK = 1'b0; #1; BCLK = 1'b1; #1; BCLK = 1'b0; #1; end
  endtask

  task automatic replay_event(input [15:0] address, input [7:0] data, input [7:0] expected, input integer frame);
    begin
      bus_write(address, data, (address >= 16'h5100 && address <= 16'h5101) ? 1'b0 : 1'b1);
      case (address)
        16'h5000: if (rM1H !== expected) begin $display("DIVERGENCE frame=%0d address=5000 expected=%02X actual=%02X",frame,expected,rM1H); $fatal(1); end
        16'h5040: if (rM1V !== expected) begin $display("DIVERGENCE frame=%0d address=5040 expected=%02X actual=%02X",frame,expected,rM1V); $fatal(1); end
        16'h5080: if (rM2H !== expected) begin $display("DIVERGENCE frame=%0d address=5080 expected=%02X actual=%02X",frame,expected,rM2H); $fatal(1); end
        16'h50c0: if (rM2V !== expected) begin $display("DIVERGENCE frame=%0d address=50c0 expected=%02X actual=%02X",frame,expected,rM2V); $fatal(1); end
        16'h5100: if (M1R[3:0] !== expected[3:0] || M2R[3:0] !== expected[7:4]) begin
          $display("DIVERGENCE frame=%0d address=5100 input=%02X expected_M1=%X expected_M2=%X actual_M1=%X actual_M2=%X",frame,data,expected[3:0],expected[7:4],M1R[3:0],M2R[3:0]); $fatal(1);
        end
        16'h5101: if (ADSEL !== expected[7] || M2R[4] !== expected[6] || M1R[4] !== expected[5] || CPL[4:0] !== expected[4:0]) begin
          $display("DIVERGENCE frame=%0d address=5101 input=%02X expected=%02X actual tuple=%b%b%b%05b",frame,data,expected,ADSEL,M2R[4],M1R[4],CPL[4:0]); $fatal(1);
        end
        default: fail("unexpected address in replay excerpt");
      endcase
      $display("REPLAY_EVENT frame=%0d address=%04X data=%02X expected=%02X PASS",frame,address,data,expected);
    end
  endtask

  initial begin
    $display("fixture=production RTL fragments + independent MAME Venture expectations");

    // Both horizontal/vertical banks and the RTL's +1 vertical position load.
    bus_write(16'h5000, 8'h00, 1'b1);
    if (rM1H !== 8'h00) fail("M1H exact-base write");
    bus_write(16'h5040, 8'hff, 1'b1);
    if (rM1V !== 8'h00) fail("M1V vertical +1 wraps at 8 bits");
    bus_write(16'h5080, 8'hff, 1'b1);
    if (rM2H !== 8'hff) fail("M2H exact-base write");
    bus_write(16'h50c0, 8'hfe, 1'b1);
    if (rM2V !== 8'hff) fail("M2V vertical +1");

    // Boundary/mirror source difference: MAME maps $503f, RTL exact decode does not.
    bus_write(16'h5000, 8'h21, 1'b1);
    bus_write(16'h503f, 8'h99, 1'b1);
    if (rM1H !== 8'h21) fail("RTL unexpectedly accepted MAME mirrored $503f");
    bus_write(16'h5040, 8'h30, 1'b1);
    bus_write(16'h507f, 8'h99, 1'b1);
    if (rM1V !== 8'h31) fail("RTL unexpectedly accepted MAME mirrored $507f");
    bus_write(16'h5080, 8'h40, 1'b1);
    bus_write(16'h50bf, 8'h99, 1'b1);
    if (rM2H !== 8'h40) fail("RTL unexpectedly accepted MAME mirrored $50bf");
    bus_write(16'h50c0, 8'h50, 1'b1);
    bus_write(16'h50ff, 8'h99, 1'b1);
    if (rM2V !== 8'h51) fail("RTL unexpectedly accepted MAME mirrored $50ff");

    // The image latch at $5100 holds two independent low nibbles.
    bus_write(16'h5100, 8'ha3, 1'b0);
    if (M1R[3:0] !== 4'h3 || M2R[3:0] !== 4'ha) fail("dual image latch nibble mapping");
    // $5101 source tuple is {ADSEL,M2R[4],M1R[4],CPL[4:0]}.
    bus_write(16'h5101, 8'ha5, 1'b0);
    if (ADSEL !== 1'b1 || M2R[4] !== 1'b0 || M1R[4] !== 1'b1 || CPL[4:0] !== 5'h05)
      fail("control tuple bit mapping");

    // Check both sprite-address banks and board-dependent bit 10.
    hscnt = 6'b000000; pcb = 8'h00; #1;
    if (SPRITE_ADDR !== {1'b1,M1R[4:0],1'b0,M1V[3:0]}) fail("M1 graphics address with pcb[4]=0");
    pcb = 8'h10; #1;
    if (SPRITE_ADDR !== {1'b0,M1R[4:0],1'b0,M1V[3:0]}) fail("M1 graphics address with pcb[4]=1");
    hscnt = 6'b000100; #1;
    if (SPRITE_ADDR !== {1'b1,M2R[4:0],1'b0,M2V[3:0]}) fail("M2 graphics address");

    // Video counters load latched coordinates at blank edges, then advance.
    nCBLB = 1'b0; clock_bclk();
    if (M1H !== rM1H || M2H !== rM2H) fail("horizontal counter reload");
    nCBLB = 1'b1; clock_bclk();
    if (M1H !== rM1H + 8'd1 || M2H !== rM2H + 8'd1) fail("horizontal counter increment");
    vscnt = 9'd0; CBLB = 1'b0; #1; CBLB = 1'b1; #1;
    if (M1V !== rM1V || M2V !== rM2V) fail("vertical counter reload at line zero");
    vscnt = 9'd1; CBLB = 1'b0; #1; CBLB = 1'b1; #1;
    if (M1V !== rM1V + 8'd1 || M2V !== rM2V + 8'd1) fail("vertical counter increment");

    // cDET truth table probes: M1/BG, M2/BG, M1/M2-only, and blanking.
    EM1VID=1; M1VID=1; EM2VID=0; M2VID=0; SGCVID=1; CBLB=0; #1;
    if (cDET !== 1'b1) fail("M1/background collision detect");
    EM1VID=0; M1VID=0; EM2VID=1; M2VID=1; #1;
    if (cDET !== 1'b1) fail("M2/background collision detect");
    SGCVID=0; #1;
    if (cDET !== 1'b0) fail("M2-only pixel without background");
    EM1VID=1; M1VID=1; EM2VID=1; M2VID=1; #1;
    if (cDET !== 1'b0) fail("object/object only is not cDET");
    SGCVID=1; CBLB=1; #1;
    if (cDET !== 1'b0) fail("blanking suppresses cDET");

    // Venture's pinned MAME policy accepts only M1/background (mask/invert 04/04).
    // RTL instead raises IRQ for either sprite/background; show that bounded divergence.
    CBLB=0; EM1VID=0; M1VID=0; EM2VID=1; M2VID=1; SGCVID=1; nEIR=1; #1;
    if (!cDET) fail("MAME-vs-RTL M2/background divergence probe missing");
    clock_bclk(); #1;
    if (rCPU_IRQ !== 1'b1) fail("aggregate cDET did not request RTL IRQ");
    if (EIR[4] !== 1'b0 || EIR[2] !== 1'b0) fail("M2/background latch bits unexpected");
    nEIR=0; #1; if (rCPU_IRQ !== 1'b0) fail("IRQ acknowledge clear");

    // M1/background collision is represented as high by RTL EIR[2]; MAME invert=04
    // presents collision as bit 2 low. This is an explicit polarity comparison.
    nEIR=1; EM1VID=1; M1VID=1; EM2VID=0; M2VID=0; SGCVID=1; #1;
    clock_bclk(); #1;
    if (rCPU_IRQ !== 1'b1 || EIR[2] !== 1'b1) fail("M1/background RTL EIR polarity");

    // Actual captured CPU writes, independently expected from the public register map.
    `include "replay_events.svh"

    $display("PASS source-extracted sprite latches, bank decode, counter boundaries, collision/IRQ probes");
    $display("LIMIT MAME Venture mask/invert=04/04: M1/background only; RTL cDET also requests IRQ for M2/background");
    $display("LIMIT canonicalized accepted bus logs cannot prove whether MAME mirrored sprite addresses were used");
    $finish;
  end
endmodule
