`timescale 1ns/1ps
// Replays an ordered MAME audio-CPU RAM-window access log (CSV: R|W,addr,data)
// through the RAM address map under test and compares every read to MAME's value.
module tb_audio_ram;
  reg [15:0] a=0; wire [10:0] ra;
`ifdef FLAT
  assign ra = a[10:0];
`else
  exidyAudioRamAddr map(.cpu_addr(a),.ram_addr(ra));
`endif
  reg [7:0] ram [0:2047];
  integer fd, n, reads=0, bad=0, k, r; string line; reg [7:0] kind; integer addr, data;
  initial begin
    for (k=0;k<2048;k++) ram[k]=0;
    if (!$value$plusargs("TRACE=%s",line)) $fatal(1,"need +TRACE=");
    fd=$fopen(line,"r"); if (fd==0) $fatal(1,"cannot open trace");
    while (!$feof(fd)) begin
      r=$fscanf(fd,"%c,%x,%x\n",kind,addr,data);
      if (r==3 && addr<16'h0800) begin
        a=addr[15:0]; #1;
        if (kind=="W") ram[ra]=data[7:0];
        else begin reads++; if (ram[ra]!==data[7:0]) bad++; end
      end
    end
    $display("reads=%0d mismatches=%0d",reads,bad);
    if (bad==0) $display("PASS audio ram map"); else $display("FAILED audio ram map");
    $finish;
  end
endmodule
