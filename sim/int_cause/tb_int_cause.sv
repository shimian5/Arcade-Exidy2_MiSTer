`timescale 1ns/1ps
module tb_int_cause;
  reg [1:0] profile=0; reg m1m2=0,m2char=0,m1char=0; wire [4:2] cause; wire irq;
  exidyIntCause dut(.*);
  integer errors=0, p, c;
  // Independent model of MAME latch_condition: (collision ^ invert) & mask on bits 4,3,2.
  function automatic [7:0] mame_mask(input [1:0] pr); case(pr) 1:mame_mask=8'h04; 2:mame_mask=8'h14; 3:mame_mask=8'h0c; default:mame_mask=8'h14; endcase endfunction
  function automatic [7:0] mame_inv (input [1:0] pr); case(pr) 1:mame_inv=8'h04;  2:mame_inv=8'h04;  3:mame_inv=8'h0c; default:mame_inv=8'h00; endcase endfunction
  task automatic expect_cond(input [1:0] pr, input [7:0] coll, input [7:0] want_bits, input string why);
    reg [7:0] got;
    begin
      profile=pr; m1m2=coll[4]; m2char=coll[3]; m1char=coll[2]; #1;
      got = {3'b0,cause,2'b0};
      if (got!==want_bits) begin errors++; $display("FAIL %s: profile %0d coll %02h got %02h want %02h",why,pr,coll,got,want_bits); end
    end
  endtask
  initial begin
    // Exhaustive against the MAME formula.
    for (p=0;p<4;p++) for (c=0;c<8;c++) begin
      reg [7:0] coll, want; coll={3'b0,c[2],c[1],c[0],2'b0}; want=(coll^mame_inv(p))&mame_mask(p);
      expect_cond(p[1:0],coll,want,"formula");
      if (irq!==((coll&mame_mask(p))!=0)) begin errors++; $display("FAIL irq profile %0d coll %02h",p,coll); end
    end
    // Values observed in MAME 0.264 captures (bits 7 added by the caller: 0 at vblank, 1 on collision).
    expect_cond(2'd2,8'h00,8'h04,"pepper2/hardhat vblank reads 04");
    expect_cond(2'd2,8'h04,8'h00,"pepper2/hardhat collision reads 80 (bit2 low)");
    expect_cond(2'd1,8'h00,8'h04,"venture vblank reads 04");
    expect_cond(2'd1,8'h04,8'h00,"venture collision reads 80");
    expect_cond(2'd3,8'h00,8'h0c,"teetert vblank reads 0c");
    expect_cond(2'd3,8'h04,8'h08,"teetert M1/char reads 88");
    expect_cond(2'd3,8'h08,8'h04,"teetert M2/char reads 84");
    expect_cond(2'd0,8'h00,8'h00,"legacy/mtrap vblank reads 00");
    expect_cond(2'd0,8'h04,8'h04,"legacy/mtrap M1/char reads 84");
    // Masked collisions must not raise an IRQ (Venture ignores sprite2/bg and sprite1/sprite2).
    profile=1; m1m2=1; m2char=1; m1char=0; #1; if (irq) begin errors++; $display("FAIL venture irq on masked collision"); end
    if (errors==0) $display("PASS int cause"); else $display("FAILED %0d",errors);
    $finish;
  end
endmodule
