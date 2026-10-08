`timescale 1ns/1ps

module tb_pia_return_mailbox;
  parameter integer PHASE_NS = 0;
  parameter integer SHIFT_PS = 0;
  parameter integer USE_FIFO = 0;
  reg master_clk = 0, audio_clk = 0;
  reg audio_reset_n = 0, master_reset_n = 0;
  reg a_cs=0, a_rw=0, m_cs=0, m_rw=0;
  reg [1:0] a_addr=0, m_addr=0;
  reg [7:0] a_din=0, m_din=0;
  wire [7:0] a_dout, m_dout, a_pa_o, a_pb_o, m_pa_o, m_pb_o;
  wire [7:0] a_pa_oe, a_pb_oe, m_pa_oe, m_pb_oe;
  wire a_irq_a,a_irq_b,m_irq_a,m_irq_b,a_ca2_o,a_ca2_oe,a_cb2_o,a_cb2_oe;
  wire m_ca2_o,m_ca2_oe,m_cb2_o,m_cb2_oe;
  reg [7:0] a_pa_i=0,a_pb_i=0,m_pb_i=0;
  wire [7:0] main_byte;
  wire main_notify;
  wire fifo_overflow;
  wire [7:0] m_pa_i = main_byte;
  wire m_ca1 = main_notify;
  reg [7:0] cpu_databus=0, cpu_sample=0;
  reg cpu_enable=0;
  integer tick=0, phase;
  integer passed=0;
  reg seen_20=0, seen_30=0, seen_40=0;
  reg pulse_seen_low=0, pulse_seen_byte=0;

  always @(main_byte) begin
    if (main_byte == 8'h20) seen_20 = 1;
    if (main_byte == 8'h30) seen_30 = 1;
    if (main_byte == 8'h40) seen_40 = 1;
  end
  always @(main_notify or main_byte) begin
    if (main_notify === 1'b0 && main_byte === 8'h60) begin
      pulse_seen_low = 1;
      pulse_seen_byte = 1;
    end
  end

  always #3.5 master_clk = ~master_clk;
  initial begin
    #(PHASE_NS + SHIFT_PS/1000.0); forever #11 audio_clk = ~audio_clk;
  end

  pia6821 audio_pia(.clk(audio_clk),.rst(~audio_reset_n),.cs(a_cs),.rw(a_rw),.addr(a_addr),
    .data_in(a_din),.data_out(a_dout),.irqa(a_irq_a),.irqb(a_irq_b),
    .pa_i(a_pa_i),.pa_o(a_pa_o),.pa_oe(a_pa_oe),.pa_ddr_ovrd(8'h00),
    .ca1(1'b0),.ca2_i(1'b0),.ca2_o(a_ca2_o),.ca2_oe(a_ca2_oe),
    .pb_i(a_pb_i),.pb_o(a_pb_o),.pb_oe(a_pb_oe),.cb1(m_ca2_o),.cb2_i(1'b0),.cb2_o(a_cb2_o),.cb2_oe(a_cb2_oe));
  pia6821 main_pia(.clk(master_clk),.rst(~master_reset_n),.cs(m_cs),.rw(m_rw),.addr(m_addr),
    .data_in(m_din),.data_out(m_dout),.irqa(m_irq_a),.irqb(m_irq_b),
    .pa_i(m_pa_i),.pa_o(m_pa_o),.pa_oe(m_pa_oe),.pa_ddr_ovrd(8'h00),
    .ca1(m_ca1),.ca2_i(1'b0),.ca2_o(m_ca2_o),.ca2_oe(m_ca2_oe),
    .pb_i(m_pb_i),.pb_o(m_pb_o),.pb_oe(m_pb_oe),.cb1(1'b0),.cb2_i(1'b0),.cb2_o(m_cb2_o),.cb2_oe(m_cb2_oe));
  generate if (USE_FIFO != 0) begin : use_fifo
`ifdef PIA_PRODUCTION
    exidyPiaReturn mailbox(.audio_clk(audio_clk),.master_clk(master_clk),
      .audio_reset_n(audio_reset_n),.master_reset_n(master_reset_n),
      .audio_byte(a_pb_o),.audio_notify(a_cb2_o),
      .main_byte(main_byte),.main_notify(main_notify),.overflow(fifo_overflow));
`else
    exidyPiaReturnFifo mailbox(.audio_clk(audio_clk),.master_clk(master_clk),
      .audio_reset_n(audio_reset_n),.master_reset_n(master_reset_n),
      .audio_byte(a_pb_o),.audio_notify(a_cb2_o),
      .main_byte(main_byte),.main_notify(main_notify),.overflow(fifo_overflow));
`endif
  end else begin : use_snapshot
    exidyPiaReturnMailbox mailbox(.audio_clk(audio_clk),.master_clk(master_clk),
      .audio_reset_n(audio_reset_n),.master_reset_n(master_reset_n),
      .audio_byte(a_pb_o),.audio_notify(a_cb2_o),.main_byte(main_byte),.main_notify(main_notify));
    assign fifo_overflow = 1'b0;
  end endgenerate

  always @(posedge master_clk) begin
    cpu_databus <= m_dout;
    cpu_enable <= (tick % 64 == 31);
    if (cpu_enable) cpu_sample <= cpu_databus;
    tick <= tick + 1;
  end

  task automatic write_audio(input [1:0] addr,input [7:0] value);
    begin @(negedge audio_clk); a_addr=addr; a_din=value; a_rw=0; a_cs=1;
      @(posedge audio_clk); #1; a_cs=0; a_rw=1; end
  endtask
  task automatic hold_audio_write(input [1:0] addr,input [7:0] value,input integer cycles);
    begin @(negedge audio_clk); a_addr=addr; a_din=value; a_rw=0; a_cs=1;
      repeat(cycles) @(negedge audio_clk);
      @(posedge audio_clk); #1; a_cs=0; a_rw=1; end
  endtask
  task automatic write_main(input [1:0] addr,input [7:0] value);
    begin @(negedge master_clk); m_addr=addr; m_din=value; m_rw=0; m_cs=1;
      @(posedge master_clk); #1; m_cs=0; m_rw=1; end
  endtask
  task automatic check_byte(input [7:0] raw, input [7:0] expected, input bit is_partial);
    integer start_tick;
    begin
      wait(main_notify===1'b1); // establish delivered idle-high before testing the falling notification
      write_audio(2'b10,raw);
      wait(main_notify===1'b0);
      $display("notify phase=%0d expected=%02x main=%02x audioPB=%02x cb2=%b oe=%b at %0t",PHASE_NS,expected,main_byte,a_pb_o,a_cb2_o,a_cb2_oe,$time);
      // Notification and byte must be the same captured bundle.
      if (main_byte !== expected) $fatal(1,"phase %0d notify paired with %02x expected %02x",PHASE_NS,main_byte,expected);
      repeat(3) @(negedge master_clk);
      m_addr=1; m_rw=1; m_cs=0; #1;
      if (m_dout[7] !== 1'b1) $fatal(1,"phase %0d forwarded CA1 event missing CRA bit7",PHASE_NS);
      // First legal PH1 is tick 31, consumption happens one registered edge later.
      start_tick=tick;
      m_addr=0; m_rw=1; m_cs=0;
      #1;
      if (m_dout !== expected) $fatal(1,"phase %0d PIA input read %02x expected %02x",PHASE_NS,m_dout,expected);
      wait(cpu_enable===1'b1);
      m_cs=1;
      @(posedge master_clk); #1;
      if (cpu_sample !== expected) $fatal(1,"phase %0d first CPU sample %02x expected %02x",PHASE_NS,cpu_sample,expected);
      // Hold the selected PA read through audio-domain sampling, as a real CPU
      // cycle spans many master ticks; the CA2 handshake pulse must not be
      // shortened to a single master tick.
      repeat(2) @(negedge audio_clk);
      @(negedge master_clk); m_cs=0;
      #1;
      if (m_dout !== expected) $fatal(1,"phase %0d PA read %02x expected %02x",PHASE_NS,m_dout,expected);
      wait(main_notify===1'b1);
      if (a_cb2_o !== 1'b1) $fatal(1,"phase %0d PIA CB2 ACK did not return high",PHASE_NS);
      passed=passed+1;
    end
  endtask

  initial begin
    #200000; $fatal(1,"watchdog phase %0d",PHASE_NS);
  end
  initial begin
    phase=PHASE_NS;
    repeat(4) @(posedge master_clk); master_reset_n=1;
    repeat(4) @(posedge audio_clk); audio_reset_n=1;
    repeat(8) @(posedge master_clk);
    write_main(0,8'h00); write_main(1,8'h2c); // PA input; firmware's E-set CA2 mode, CRA bit7 remains readable
    write_audio(2,8'hff); write_audio(3,8'h3c); write_audio(3,8'h25);
    write_audio(3,8'h21); write_audio(2,8'hff); write_audio(3,8'h25);
    check_byte(8'h00,8'h00,0);
    check_byte(8'hff,8'hff,0);
    check_byte(8'ha5,8'ha5,0);
    check_byte(8'h5a,8'h5a,0);
    // Partial DDR: undriven audio PIA PB inputs are tied low.
    write_audio(3,8'h21); write_audio(2,8'h05); write_audio(3,8'h25);
    check_byte(8'ha5,8'h05,1);
    write_audio(3,8'h21); write_audio(2,8'hff); write_audio(3,8'h25);
    // Reset each side independently while a notification is outstanding.
    write_audio(2,8'hc3);
    wait(main_notify===1'b0);
    if (main_byte!==8'hc3) $fatal(1,"phase %0d reset setup pending byte=%02x audio=%02x notify=%b",PHASE_NS,main_byte,a_pb_o,main_notify);
    @(negedge master_clk); #3.497;
    audio_reset_n=0; #0.001;
    if (main_byte!==0 || main_notify!==0 || m_pa_i!==0) $fatal(1,"phase %0d source reset failed to mask output 1ps before master edge",PHASE_NS);
    @(posedge master_clk); #0.001;
    if (main_byte!==0 || main_notify!==0 || m_pa_i!==0) $fatal(1,"phase %0d source reset output was nonzero after master edge",PHASE_NS);
    repeat(3) @(posedge audio_clk); audio_reset_n=1;
    repeat(5) @(posedge master_clk);
    if (main_byte!==0 || main_notify!==0) $fatal(1,"stale audio response survived reset");
    @(negedge master_clk); #3.497;
    master_reset_n=0; #0.001;
    if (main_byte!==0 || main_notify!==0 || m_pa_i!==0) $fatal(1,"phase %0d destination reset failed to mask output 1ps before master edge",PHASE_NS);
    @(posedge master_clk); #0.001;
    if (main_byte!==0 || main_notify!==0 || m_pa_i!==0) $fatal(1,"phase %0d destination reset output was nonzero after master edge",PHASE_NS);
    repeat(3) @(posedge master_clk); master_reset_n=1;
    repeat(4) @(posedge audio_clk);
    write_main(0,0); write_main(1,8'h2c);
    write_audio(2,8'hff); write_audio(3,8'h3c); write_audio(3,8'h25);
    repeat(8) @(posedge audio_clk);
    $display("postreset setup phase=%0d pb=%02x cb2=%b oe=%b main=%02x notify=%b",PHASE_NS,a_pb_o,a_cb2_o,a_cb2_oe,main_byte,main_notify);
    check_byte(8'h96,8'h96,0);
    // Burst actual PIA PB writes while the main PIA has not read/acknowledged
    // the first forwarded CA1 event. FIFO must preserve every changed bundle;
    // the one-slot snapshot candidate's coalescing is recorded, not waived.
    write_audio(2,8'h10);
    wait(main_notify===1'b0);
    write_audio(2,8'h20); write_audio(2,8'h30); write_audio(2,8'h40);
    repeat(40) @(posedge master_clk);
    if (USE_FIFO) begin
      if (!seen_20 || !seen_30 || !seen_40 || main_byte!==8'h40)
        $fatal(1,"phase %0d FIFO lost burst values seen=%b%b%b final=%02x",PHASE_NS,seen_20,seen_30,seen_40,main_byte);
      if (fifo_overflow) $fatal(1,"phase %0d FIFO overflowed during 4-snapshot burst",PHASE_NS);
    end else begin
      $display("SNAPSHOT BURST phase=%0d delivered20=%b delivered30=%b delivered40=%b final=%02x",PHASE_NS,seen_20,seen_30,seen_40,main_byte);
    end
    if (main_byte!==8'h40) $fatal(1,"phase %0d burst final byte did not converge to 40",PHASE_NS);
    repeat(3) @(negedge master_clk);
    m_addr=1; m_rw=1; m_cs=0; #1;
    if (m_dout[7]!==1'b1) $fatal(1,"phase %0d burst forwarded CA1 did not set CRA bit7",PHASE_NS);
    // The actual main PIA PA read clears the CA2 E output, held long enough
    // for the audio PIA CB1 sampler and CB2 return transition.
    @(negedge master_clk); m_addr=0; m_rw=1; m_cs=1;
    #1;
    if (m_dout!==8'h40) $fatal(1,"phase %0d burst PA read did not expose final 40",PHASE_NS);
    repeat(2) @(negedge audio_clk);
    @(negedge master_clk); m_cs=0;
    wait(main_notify===1'b1);
    if (a_cb2_o!==1'b1) $fatal(1,"phase %0d burst read did not return CB2 high",PHASE_NS);
    // CRB mode 101 makes CB2 a one-audio-period pulse on each PB write.
    // Prove whether a single source-edge low pulse and its byte cross both
    // clocks while no PA read is used to stretch the source notification.
    write_audio(3,8'h2c);
    wait(main_notify===1'b1);
    pulse_seen_low=0; pulse_seen_byte=0;
    write_audio(2,8'h60);
    repeat(100) @(posedge master_clk);
    if (USE_FIFO && (!pulse_seen_low || !pulse_seen_byte))
      $fatal(1,"phase %0d FIFO missed CRB mode101 one-edge pulse/byte",PHASE_NS);
    if (!USE_FIFO)
      $display("SNAPSHOT PULSE phase=%0d deliveredLow=%b deliveredByte=%b",PHASE_NS,pulse_seen_low,pulse_seen_byte);
    if (USE_FIFO && fifo_overflow) $fatal(1,"phase %0d FIFO overflow during one-edge pulse",PHASE_NS);
    // Hold the actual mode-101 PB write active for 16 audio periods. The
    // mailbox must keep the byte/flag coherent while the source level is low.
    wait(main_notify===1'b1);
    hold_audio_write(2,8'h61,16);
    wait(main_notify===1'b0);
    if (main_byte!==8'h61) $fatal(1,"phase %0d mode101 held write paired wrong byte %02x",PHASE_NS,main_byte);
    wait(main_notify===1'b1);
    if (USE_FIFO && fifo_overflow) $fatal(1,"phase %0d FIFO overflow during 16-edge held write",PHASE_NS);
    if (USE_FIFO && fifo_overflow) $fatal(1,"FIFO overflow phase %0d",PHASE_NS);
    $display("PASS actual paired pia6821 + %s phase=%0dns shift=%0dps samples=%0d",USE_FIFO ? "exidyPiaReturnFifo" : "exidyPiaReturnMailbox",PHASE_NS,SHIFT_PS,passed);
    $finish;
  end
endmodule
