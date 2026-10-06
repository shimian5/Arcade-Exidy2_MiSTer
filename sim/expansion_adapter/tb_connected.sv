`timescale 1ns/1ps
module tb_connected;
  reg clk=0,cvsd_clk=0,remote_running=1,reset_n=0;
  always #5 clk=~clk;
  always #37 if(remote_running) cvsd_clk=~cvsd_clk;
  reg [31:0] gp_out=0;
  wire io_ack,io_strobe,fp_enable;
  wire [15:0] io_din;
  wire raw_download,raw_wr;
  wire [15:0] raw_index;
  wire [26:0] raw_addr;
  wire [7:0] raw_data;
  wire cvsd_quarantine_ack,cvsd_ack_generation,quarantine_generation;
  wire ioctl_wait,quarantine_request,transfer_begin,transfer_end,ioctl_wr,adapter_fault,transfer_active;
  wire [7:0] ioctl_index,ioctl_data;
  wire [23:0] ioctl_addr;
  wire read_accept,legacy_base_wr,reset_hold,expansion_ready,protocol_fault;
  wire [7:0] active_profile,question_data,cvsd_data;
  wire question_valid,cvsd_valid;
  reg question_read=0;
  reg [4:0] question_bank=0;
  reg [15:0] question_cpu_addr=0;
  reg [13:0] cvsd_addr=0;
  source_ack ack(.clk_sys(clk),.gp_out(gp_out),.io_wait(ioctl_wait),.*);
  source_fio fio(.clk_sys(clk),.ioctl_download(raw_download),.ioctl_wr(raw_wr),
     .ioctl_index(raw_index),.ioctl_addr(raw_addr),.ioctl_dout(raw_data),.*);
  exidy_expansion_bridge bridge(.cvsd_read(1'b1),.*);
  integer testcase=0,words=0,speech_writes=0,base_writes=0,stall_cycles=0;
  integer image=0;
  reg delayed_observer=0;
  reg rom_mode=0;
  reg [7:0] rom_image[0:196607];
  string rom_path;
  function automatic [7:0] pattern(input integer address,input integer version);
    if(rom_mode) pattern=rom_image[address];
    else pattern=8'((address*13) ^ (address>>8) ^ (version*91));
  endfunction
  function automatic [7:0] question_pattern(input integer address,input integer profile);
    if(rom_mode) question_pattern=rom_image[address];
    else if(profile==1 && (address>>13)>=22) question_pattern=0;
    else question_pattern=8'(((address>>13)*37) ^ address ^ (address>>8));
  endfunction
  always @(posedge clk) begin
    if((ioctl_index==6) && (transfer_active || transfer_begin || transfer_end) && !quarantine_request)
      $fatal(1,"speech quarantine released before loader verdict");
    if(ioctl_wr && ioctl_index==6) begin
      if(!cvsd_quarantine_ack || cvsd_ack_generation!=quarantine_generation ||
         read_accept || (|bridge.remote.outstanding)) $fatal(1,"connected overwrite before drain");
      if(ioctl_addr!=speech_writes || ioctl_data!=pattern(speech_writes,image))
        $fatal(1,"connected speech payload lost/reordered");
      speech_writes++;
    end
    if(legacy_base_wr) begin
      if(ioctl_data!=8'h42 || ioctl_addr!=0) $fatal(1,"legacy forwarding mismatch");
      base_writes++;
    end
    if(ioctl_wait && !remote_running) begin
      stall_cycles++;
      if(speech_writes!=0) $fatal(1,"host wait leaked speech byte");
      if(stall_cycles==25) remote_running=1;
    end
  end
  // Main spi_b/spi_w -> fpga_spi waits for ACK high, lowers strobe,
  // then waits for ACK low before issuing the next word.
  task automatic word(input [15:0] value);
    integer timeout;
    begin
      @(negedge clk); gp_out[15:0]=value; gp_out[17]=1;
      timeout=0;
      while(!io_ack && timeout<300) begin @(negedge clk); timeout++; end
      if(!io_ack) $fatal(1,"host ACK-high timeout");
      if(delayed_observer) repeat(3) @(negedge clk);
      gp_out[17]=0; timeout=0;
      while(io_ack && timeout<300) begin @(negedge clk); timeout++; end
      if(io_ack) $fatal(1,"host ACK-low timeout");
      if(delayed_observer) repeat(2) @(negedge clk);
      words++;
    end
  endtask
  task automatic select_fio;
    @(negedge clk); gp_out[18]=1; repeat(4) @(negedge clk);
  endtask
  task automatic deselect_fio;
    @(negedge clk); gp_out[18]=0; repeat(4) @(negedge clk);
  endtask
  task automatic begin_stream(input integer index);
    select_fio(); word(16'h55); word(16'(index)); deselect_fio();
    select_fio(); word(16'h53); word(16'hff); deselect_fio();
    select_fio(); word(16'h54);
  endtask
  task automatic end_stream(input bit expect_transport_fault=0);
    deselect_fio(); select_fio(); word(16'h53); word(0); deselect_fio();
    repeat(8) @(negedge clk);
    if(transfer_active || bridge.loader.transfer_active || (adapter_fault && !expect_transport_fault))
      $fatal(1,"connected stream did not retire");
  endtask
  task automatic marker(input integer pcb=16'h90);
    begin_stream(1); word(16'(pcb)); end_stream();
    if(!reset_hold || expansion_ready || protocol_fault) $fatal(1,"marker state mismatch");
  endtask
  task automatic send_descriptor(input integer profile=3, input integer field=-1,
                                 input integer value=0, input integer length=16);
    reg [7:0] bytes[0:15];
    begin
      bytes='{8'h45,8'h58,8'h01,8'h03,8'h05,8'h01,8'h00,8'h00,
              8'h00,8'h00,8'h00,8'h00,8'h40,8'h00,8'h00,8'h00};
      if(profile==1 || profile==2) begin
        bytes[3]=8'(profile); bytes[4]=3; bytes[10]=3; bytes[12]=0;
      end
      if(field>=0) bytes[field]=8'(value);
      begin_stream(7);
      for(integer i=0;i<length;i++) word(i<16 ? {8'd0,bytes[i]} : 16'd0);
      end_stream();
    end
  endtask
  task automatic descriptor;
    begin
      send_descriptor();
      if(protocol_fault || active_profile!=3) $fatal(1,"descriptor state mismatch");
    end
  endtask
  task automatic base;
    begin_stream(0); word(16'h42); end_stream();
  endtask
  task automatic speech(input integer length);
    speech_writes=0; begin_stream(6);
    for(integer i=0;i<length;i++) word({8'd0,pattern(i,image)});
    end_stream();
  endtask
  task automatic assert_closed;
    if(!protocol_fault || !reset_hold || expansion_ready)
      $fatal(1,"malformed connected session did not hold reset");
    repeat(6) @(negedge cvsd_clk);
    if(cvsd_valid || read_accept || !quarantine_request)
      $fatal(1,"faulted loader left speech read enabled");
  endtask
  task automatic matrix;
    integer profile;
    begin
      if(testcase==2 || testcase==3 || testcase==22 || testcase==23) begin
        profile=(testcase>=22) ? testcase-21 : testcase-1;
        marker(16'hb0); send_descriptor(profile); base();
        begin_stream(5);
        for(integer i=0;i<196608;i++) word({8'd0,question_pattern(i,profile)});
        end_stream();
        if(protocol_fault || adapter_fault || reset_hold || !expansion_ready || active_profile!=profile)
          $fatal(1,"full question image readiness failed");
        for(integer i=0;i<196608;i++)
          if(bridge.loader.question_mem[i]!==question_pattern(i,profile)) $fatal(1,"question memory mismatch");
        // Every bank, first/last byte and upper CPU-address aliasing are
        // independently exercised through the public synchronous read port.
        for(integer bank=0;bank<24;bank++) begin
          for(integer edgebyte=0;edgebyte<2;edgebyte++) begin
            @(negedge clk); question_read=1; question_bank=5'(bank);
            question_cpu_addr=edgebyte ? 16'h3fff : 16'h2000;
            @(negedge clk); question_read=0;
            if(!question_valid || question_data!==question_pattern(bank*8192+(edgebyte ? 8191 : 0),profile))
              $fatal(1,"question bank read mismatch");
          end
        end
        $display("PASS matrix case=%0d profile=%0d question_bytes=196608 bank_reads=48",testcase,profile);
        $finish;
      end
      if(testcase==17) begin
        send_descriptor(); assert_closed();
      end else if(testcase==18) begin
        begin_stream(1); end_stream(1);
        if(!adapter_fault) $fatal(1,"empty marker did not fault transport");
        assert_closed();
      end else begin
        marker(testcase==10 ? 16'hb0 : 16'h90);
        case(testcase)
          4: send_descriptor(3,0,0);
          5: send_descriptor(3,2,2);
          6: send_descriptor(3,4,3);
          7: send_descriptor(3,15,1);
          8: send_descriptor(3,3,4);
          9: send_descriptor(3,10,1);
          10: send_descriptor();
          11: base();
          12: begin descriptor(); speech(1); end
          13: begin descriptor(); base(); speech(16383); end
          14: begin descriptor(); base(); speech(16385); end
          15: begin descriptor(); base(); base(); end
          16: begin descriptor(); base(); speech(16384); begin_stream(9); word(16'h99); end_stream(); end
          19: send_descriptor(3,-1,0,15);
          20: send_descriptor(3,-1,0,17);
          24: begin send_descriptor(3,0,0); base(); speech(16384); end
          25: begin
            descriptor(); base(); speech(16384);
            if(reset_hold || !expansion_ready) $fatal(1,"extended readiness failed before reload");
            base(); begin_stream(1); word(16'h30); end_stream();
            repeat(6) @(negedge cvsd_clk);
            if(reset_hold || expansion_ready || protocol_fault || adapter_fault || cvsd_valid || read_accept)
              $fatal(1,"extended-to-legacy reload retained image or held reset");
            $display("PASS matrix legacy_reload ready=0 hold=0 speech_reads=0"); $finish;
          end
          26: begin
            send_descriptor(3,0,0); base(); speech(16384); assert_closed();
            base(); begin_stream(1); word(16'h30); end_stream();
            repeat(6) @(negedge cvsd_clk);
            if(reset_hold || expansion_ready || protocol_fault || adapter_fault || cvsd_valid || read_accept)
              $fatal(1,"legacy reload did not recover loader-only protocol fault");
            $display("PASS matrix legacy_fault_recovery ready=0 hold=0 speech_reads=0"); $finish;
          end
          27: begin
            descriptor(); base(); speech(16384);
            if(!expansion_ready || reset_hold) $fatal(1,"duplicate precondition failed");
            speech(16384);
          end
          default: $fatal(1,"unknown matrix case");
        endcase
        assert_closed();
      end
      $display("PASS matrix case=%0d protocol_fault=1 reset_hold=1 ready=0",testcase);
      $finish;
    end
  endtask
  task automatic verify_image;
    // Inspect actual loaded memory, then independently exercise every read
    // address through the loader's remote read port after readiness settles.
    for(integer i=0;i<16384;i++)
      if(bridge.loader.cvsd_mem[i]!==pattern(i,image)) $fatal(1,"stored payload mismatch at %0d",i);
    repeat(5) @(negedge cvsd_clk);
    for(integer i=0;i<16384;i++) begin
      cvsd_addr=14'(i); @(negedge cvsd_clk);
      if(!cvsd_valid || cvsd_data!==pattern(i,image)) $fatal(1,"remote payload mismatch at %0d",i);
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",testcase)) testcase=0;
    delayed_observer=(testcase==1);
    rom_mode=(testcase>=21 && testcase<=23);
    if(rom_mode) begin
      if(!$value$plusargs("ROM_IMAGE=%s",rom_path)) $fatal(1,"ROM image path missing");
      if(testcase==21) $readmemh(rom_path,rom_image,0,16383);
      else $readmemh(rom_path,rom_image);
    end
    repeat(5) @(negedge clk); reset_n=1;
    if(testcase>=2 && testcase!=21) matrix();
    for(image=0;image<2;image++) begin
      marker(); descriptor(); begin_stream(0); word(16'h42); end_stream();
      if(!reset_hold || expansion_ready || protocol_fault) $fatal(1,"incomplete image released reset");
      speech_writes=0; stall_cycles=0;
      @(negedge cvsd_clk); remote_running=0;
      begin_stream(6);
      for(integer i=0;i<16384;i++) word({8'd0,pattern(i,image)});
      end_stream();
      if(stall_cycles<25 || speech_writes!=16384 || !expansion_ready || reset_hold || protocol_fault)
        $fatal(1,"connected completion/host backpressure failed");
      verify_image();
    end
    if(base_writes!=2) $fatal(1,"legacy forwarding count mismatch");
    $display("PASS connected case=%0d words=%0d speech_writes=%0d base_writes=%0d stopped_wait_cycles=%0d",testcase,words,speech_writes,base_writes,stall_cycles);
    $finish;
  end
  initial begin #100000000; $fatal(1,"connected watchdog timeout"); end
endmodule
