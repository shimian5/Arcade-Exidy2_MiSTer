`timescale 1ns/1ps
module tb_fax_wrapper_transport;
  reg clk=0,audio_clk=0,remote_running=1,reset_n=0;
  always #5 clk=~clk;
  always #37 if(remote_running) audio_clk=~audio_clk;
  reg [31:0] gp_out=0;
  wire io_ack,io_strobe,fp_enable;
  wire [15:0] io_din;
  wire raw_download,raw_wr;
  wire [15:0] raw_index;
  wire [26:0] raw_addr;
  wire [7:0] raw_data;
  reg speech_read=0;
  reg [13:0] speech_addr=0;
  reg question_read=0;
  reg [4:0] question_bank=0;
  reg [15:0] question_cpu_addr=0;
  wire [7:0] speech_data,question_data,base_data;
  wire speech_valid,speech_enable,question_valid,question_image_ready;
  wire ioctl_wait,base_wr,reset_hold;
  wire [24:0] base_addr;
  source_ack ack(.clk_sys(clk),.gp_out(gp_out),.io_wait(ioctl_wait),.*);
  source_fio fio(.clk_sys(clk),.ioctl_download(raw_download),.ioctl_wr(raw_wr),
      .ioctl_index(raw_index),.ioctl_addr(raw_addr),.ioctl_dout(raw_data),.*);
  exidySpeechLoader dut(.*);

  reg [7:0] base_rom[0:84543];
  reg [7:0] question_rom[0:196607];
  reg [7:0] descriptor[0:15];
  reg [7:0] stream_order[0:4];
  reg [7:0] marker_byte[0:0];
  string image_dir,set_name,path;
  integer order_count=0,base_seen=0,stall_cycles=0;

  wire adapter_fault=dut.adapter_fault;
  wire protocol_fault=dut.protocol_fault;
  wire [7:0] active_profile=dut.active_profile;
  wire expansion_ready=dut.ready;

  always @(posedge clk) begin
    if(base_wr) begin
      if(base_addr!==25'(base_seen) || base_data!==base_rom[base_seen])
        $fatal(1,"production wrapper base tuple %0d addr=%0d data=%02x",base_seen,base_addr,base_data);
      base_seen++;
    end
    if(ioctl_wait) stall_cycles++;
  end

  task automatic spi_word(input [15:0] value);
    integer timeout;
    begin
      @(negedge clk); gp_out[15:0]=value; gp_out[17]=1; timeout=0;
      while(!io_ack && timeout<300) begin @(negedge clk); timeout++; end
      if(!io_ack) $fatal(1,"source ACK-high timeout");
      gp_out[17]=0; timeout=0;
      while(io_ack && timeout<300) begin @(negedge clk); timeout++; end
      if(io_ack) $fatal(1,"source ACK-low timeout");
    end
  endtask
  task automatic select_fio; @(negedge clk); gp_out[18]=1; repeat(4) @(negedge clk); endtask
  task automatic deselect_fio; @(negedge clk); gp_out[18]=0; repeat(4) @(negedge clk); endtask
  task automatic begin_stream(input integer index_value);
    begin
      select_fio(); spi_word(16'h55); spi_word(16'(index_value)); deselect_fio();
      select_fio(); spi_word(16'h53); spi_word(16'hff); deselect_fio();
      select_fio(); spi_word(16'h54);
    end
  endtask
  task automatic end_stream;
    begin
      deselect_fio(); select_fio(); spi_word(16'h53); spi_word(0); deselect_fio();
      repeat(8) @(negedge clk);
      if(dut.bridge.transfer_active || adapter_fault) $fatal(1,"transport did not retire cleanly");
    end
  endtask
  function automatic integer stream_length(input integer index_value);
    case(index_value) 0:stream_length=84544; 1:stream_length=1; 2:stream_length=1;
      5:stream_length=196608; 6:stream_length=16384; 7:stream_length=16; default:stream_length=0; endcase
  endfunction
  function automatic [7:0] stream_byte(input integer index_value,input integer address);
    case(index_value)
      0:stream_byte=base_rom[address]; 1:stream_byte=marker_byte[address];
      2:stream_byte=8'hdc; 5:stream_byte=question_rom[address];
      6:stream_byte=8'((address*13) ^ (address>>3) ^ 8'h6d); 7:stream_byte=descriptor[address];
      default:stream_byte=0;
    endcase
  endfunction
  task automatic send_stream(input integer index_value);
    integer count;
    begin
      count=stream_length(index_value);
      if(!count) $fatal(1,"unsupported MRA stream %0d",index_value);
      begin_stream(index_value);
      for(integer i=0;i<count;i++) spi_word({8'd0,stream_byte(index_value,i)});
      end_stream();
    end
  endtask
  task automatic load_set(input integer expected_profile);
    begin
      for(integer i=0;i<5;i++) begin
        case(stream_order[i])
          1:send_stream(1); 7:send_stream(7); 0:send_stream(0);
          5:send_stream(5); 2:send_stream(2);
          default:$fatal(1,"unexpected MRA XML index %0d",stream_order[i]);
        endcase
      end
      if(adapter_fault || protocol_fault || reset_hold || !expansion_ready ||
         !question_image_ready || active_profile!=expected_profile)
        $fatal(1,"production wrapper did not accept complete FAX profile=%0d",expected_profile);
      if(base_seen!=84544) $fatal(1,"base tuple count %0d",base_seen);
      for(integer i=0;i<196608;i++)
        if(dut.bridge.loader.question_mem[i]!==question_rom[i])
          $fatal(1,"question RAM mismatch at %0d",i);
      for(integer bank=0;bank<24;bank++) begin
        for(integer edgebyte=0;edgebyte<2;edgebyte++) begin
          @(negedge clk); question_read=1; question_bank=5'(bank);
          question_cpu_addr=edgebyte ? 16'h3fff:16'h2000;
          @(negedge clk); question_read=0;
          if(!question_valid || question_data!==question_rom[bank*8192+(edgebyte?8191:0)])
            $fatal(1,"public question read mismatch bank=%0d edge=%0d",bank,edgebyte);
        end
      end
      for(integer bank=24;bank<32;bank++) begin
        @(negedge clk); question_read=1; question_bank=5'(bank); question_cpu_addr=16'h2000;
        @(negedge clk); question_read=0;
        if(!question_valid || question_data!==8'h00)
          $fatal(1,"out-of-image bank %0d was not quarantined to zero",bank);
      end
    end
  endtask
  task automatic reset_core;
    begin @(negedge clk); reset_n=0; repeat(5) @(negedge clk); reset_n=1; repeat(8) @(negedge clk); end
  endtask
  task automatic exercise_recovery_and_speech;
    begin
      // B0 stays a legacy core profile and an index-5 stream is ignored.
      marker_byte[0]=8'hB0; send_stream(1);
      if(reset_hold || expansion_ready || protocol_fault || question_image_ready)
        $fatal(1,"legacy B0 marker changed extension state");
      send_stream(5);
      if(reset_hold || expansion_ready || protocol_fault || question_image_ready)
        $fatal(1,"legacy index 5 was not ignored");

      // Each question profile must match its exact normalized PCB marker.
      reset_core();
      marker_byte[0]=(set_name=="fax" ? 8'hF4:8'hF8);
      descriptor[3]=(set_name=="fax" ? 8'd2:8'd1);
      send_stream(1); send_stream(7);
      if(!protocol_fault || !reset_hold || expansion_ready)
        $fatal(1,"wrong marker/profile pair was accepted");

      // Recover through reset, then move through real FAX state into speech.
      reset_core();
      marker_byte[0]=8'h90;
      descriptor[0]=8'h45; descriptor[1]=8'h58; descriptor[2]=8'h01;
      descriptor[3]=8'h03; descriptor[4]=8'h05;
      descriptor[5]=8'h40; descriptor[6]=8'h4A; descriptor[7]=8'h01;
      descriptor[8]=0; descriptor[9]=0; descriptor[10]=0;
      descriptor[11]=0; descriptor[12]=8'h40; descriptor[13]=0;
      descriptor[14]=0; descriptor[15]=0;
      base_seen=0; send_stream(1); send_stream(7); send_stream(0); send_stream(6);
      repeat(5) @(posedge audio_clk);
      if(protocol_fault || reset_hold || !speech_enable || active_profile!=3)
        $fatal(1,"speech profile failed after FAX recovery fault=%b hold=%b enable=%b profile=%0d ready=%b adapter=%b",
               protocol_fault,reset_hold,speech_enable,active_profile,expansion_ready,adapter_fault);
      for(integer i=0;i<16384;i++)
        if(dut.bridge.loader.cvsd_mem[i]!==8'((i*13) ^ (i>>3) ^ 8'h6d))
          $fatal(1,"speech payload mismatch at %0d",i);
      speech_read=1; speech_addr=0; repeat(3) @(posedge audio_clk);
      remote_running=0; stall_cycles=0;
      fork
        begin begin_stream(6); spi_word({8'd0,stream_byte(6,0)}); end_stream(); end
        begin
          integer wait_cycles;
          wait_cycles=0;
          while(!ioctl_wait && wait_cycles<1000) begin @(posedge clk); wait_cycles++; end
          if(!ioctl_wait) $fatal(1,"index-6 transfer did not assert host wait");
          repeat(25) @(posedge clk);
          if(!ioctl_wait || stall_cycles<20) $fatal(1,"host did not remain stalled for stopped speech-reader backpressure");
          remote_running=1;
        end
      join
      speech_read=0;
      if(!protocol_fault || !reset_hold) $fatal(1,"duplicate speech transfer did not fault after drain");
      marker_byte[0]=8'hB0; send_stream(1);
      if(reset_hold || speech_enable || question_image_ready)
        $fatal(1,"legacy reload did not clear speech and question readiness");
    end
  endtask

  initial begin
    if(!$value$plusargs("IMAGE_DIR=%s",image_dir)) $fatal(1,"IMAGE_DIR missing");
    if(!$value$plusargs("SET=%s",set_name)) $fatal(1,"SET missing");
    if(!$value$plusargs("ORDER_COUNT=%d",order_count)) $fatal(1,"ORDER_COUNT missing");
    if(order_count!=5) $fatal(1,"MRA XML order count must be five");
    path=$sformatf("%s/%s_index0.mem",image_dir,set_name); $readmemh(path,base_rom);
    path=$sformatf("%s/%s_index5.mem",image_dir,set_name); $readmemh(path,question_rom);
    path=$sformatf("%s/%s_index7.mem",image_dir,set_name); $readmemh(path,descriptor);
    path=$sformatf("%s/%s_index1.mem",image_dir,set_name); $readmemh(path,marker_byte);
    path=$sformatf("%s/%s_order.mem",image_dir,set_name); $readmemh(path,stream_order);
    if(stream_order[0]!=1 || stream_order[1]!=7 || stream_order[2]!=0 ||
       stream_order[3]!=5 || stream_order[4]!=2) $fatal(1,"MRA XML order mismatch");
    repeat(5) @(negedge clk); reset_n=1; repeat(8) @(negedge clk);
    base_seen=0; load_set(set_name=="fax" ? 1:2);
    exercise_recovery_and_speech();
    $display("PASS production wrapper + source transport set=%s base=%0d questions=196608 reads=48",set_name,base_seen);
    $finish;
  end
  initial begin #800000000; $fatal(1,"production wrapper transport watchdog"); end
endmodule
