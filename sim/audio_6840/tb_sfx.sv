`timescale 1ns/1ps
// Replays timestamped 6840/sfxctrl writes into the production berzerk_sound_fx and logs
// output toggles of the three timer outputs (cycle numbers of the module clock).
module tb_sfx;
  reg clock=0, reset=1, cs=0, vs=0; reg [2:0] addr=0; reg [7:0] di=0; wire [11:0] sample;
  berzerk_sound_fx dut(.clock(clock),.reset(reset),.cs(cs),.vs(vs),.addr(addr),.di(di),.sample(sample));
  integer fd, ev, cyc=0, r, nc, nk, nr, nd, nextc=-1, nextk=0, nextr=0, nextd=0, endc;
  reg [2:0] q_prev=0; reg [2:0] q_now;
  string path, outpath;
  always #5 clock=~clock;
  initial begin
    if (!$value$plusargs("STIM=%s",path)) $fatal(1,"STIM");
    if (!$value$plusargs("OUT=%s",outpath)) $fatal(1,"OUT");
    if (!$value$plusargs("CYCLES=%d",endc)) endc=1000000;
    fd=$fopen(path,"r"); ev=$fopen(outpath,"w");
    r=$fscanf(fd,"%d %d %d %d\n",nextc,nextk,nextr,nextd);
    repeat(4) @(posedge clock); reset=0;
  end
  always @(posedge clock) if (!reset) begin
    cs<=0; vs<=0;
    while (nextc>=0 && nextc<=cyc) begin
      addr<=nextr[2:0]; di<=nextd[7:0]; if (nextk==0) cs<=1; else vs<=1;
      if ($fscanf(fd,"%d %d %d %d\n",nextc,nextk,nextr,nextd)!=4) nextc=-1;
      break;   // one write per clock edge
    end
    q_now={dut.ptm6840_q3,dut.ptm6840_q2,dut.ptm6840_q1};
    if (q_now!==q_prev) begin $fwrite(ev,"%0d %0d\n",cyc,q_now ^ q_prev); q_prev<=q_now; end
    cyc<=cyc+1;
    if (cyc>=endc) begin $fclose(ev); $finish; end
  end
endmodule
