`timescale 1ns/1ps
module tb_exidy_output_control;
reg clk_sys=0, clk_output=0;
always #5 clk_sys=~clk_sys;
always #7 clk_output=~clk_output;
reg management_reset=0,user_reset=0,native_locked=1,output_locked=1;
reg request_crt=0,native_frame=0,output_frame=0;
reg stall_active=0,start_busy=0;
wire cfg_waitrequest=stall_active || start_busy;
wire cfg_write; wire [5:0] cfg_address; wire [31:0] cfg_writedata;
wire selected_crt,transport_reset,blank_output;
exidy_output_control dut(.*);
integer nwrite=0;
reg [5:0] addresses[0:15]; reg [31:0] words[0:15];
integer accepted_cycle[0:15],sys_cycle=0,stall_cycles=0,busy_cycles=0;
reg [15:0] stall_seen=0;
always @(posedge clk_sys) begin
    sys_cycle=sys_cycle+1;
    if(cfg_write && !cfg_waitrequest) begin
        addresses[nwrite]=cfg_address; words[nwrite]=cfg_writedata;
        accepted_cycle[nwrite]=sys_cycle; nwrite=nwrite+1;
        // pll_cfg waitrequest does not pulse for M/C; START alone runs busy/done.
        if(cfg_address==6'd2) begin start_busy=1; busy_cycles=5; end
    end
end
always @(negedge clk_sys) begin
    if(stall_cycles>0) begin
        stall_cycles=stall_cycles-1;
        if(stall_cycles==0) stall_active=0;
    end else if(cfg_write && !start_busy && !stall_seen[nwrite]) begin
        stall_seen[nwrite]=1; stall_cycles=3; stall_active=1;
    end
    if(busy_cycles>0) begin
        busy_cycles=busy_cycles-1;
        if(busy_cycles==0) start_busy=0;
    end
end
task tick_frame;
    begin @(negedge clk_output); output_frame=1; @(negedge clk_output); output_frame=0; end
endtask
task wait_visible;
    integer k;
    begin
        for(k=0;k<8 && blank_output;k=k+1) tick_frame();
        if(blank_output) $fatal(1,"output failed two-frame warmup");
    end
endtask
integer timeout;
initial begin
    repeat(5) @(negedge clk_sys); management_reset=1;
    repeat(3) @(negedge clk_sys); management_reset=0;
    timeout=0;
    while((nwrite<3 || selected_crt!==1'b0 || blank_output) && timeout<10000) begin
        @(negedge clk_sys); timeout=timeout+1;
        if(timeout%100==0) tick_frame();
    end
    if(timeout==10000) $fatal(1,"native startup timed out");
    if(nwrite!=3 || addresses[0]!=4 || words[0]!=32'h00004040 ||
       addresses[1]!=5 || words[1]!=32'h00001010 || addresses[2]!=2 || words[2]!=1)
        $fatal(1,"native config mismatch n=%0d (%0d,%08x) (%0d,%08x) (%0d,%08x)",nwrite,
          addresses[0],words[0],addresses[1],words[1],addresses[2],words[2]);
    if(accepted_cycle[1]-accepted_cycle[0]<256 || accepted_cycle[2]-accepted_cycle[1]<256)
        $fatal(1,"startup M/C guard gaps too short: M-C=%0d C-START=%0d",
          accepted_cycle[1]-accepted_cycle[0],accepted_cycle[2]-accepted_cycle[1]);

    while(dut.state!=dut.IDLE) @(negedge clk_sys);
    request_crt=1; native_frame=1; @(negedge clk_sys); native_frame=0;
    timeout=0;
    while((nwrite<6 || selected_crt!==1'b1 || blank_output) && timeout<10000) begin
        @(negedge clk_sys); timeout=timeout+1;
        if(timeout%100==0) tick_frame();
    end
    if(timeout==10000) $fatal(1,"CRT switch timed out writes=%0d state=%0d wait=%b sel=%b reset=%b",nwrite,dut.state,cfg_waitrequest,selected_crt,transport_reset);
    if(addresses[3]!=4 || words[3]!=32'h00024241 ||
       addresses[4]!=5 || words[4]!=32'h00021211 || addresses[5]!=2 || words[5]!=1)
        $fatal(1,"CRT config mismatch: M=%08x C=%08x",words[3],words[4]);
    if(accepted_cycle[4]-accepted_cycle[3]<256 || accepted_cycle[5]-accepted_cycle[4]<256)
        $fatal(1,"CRT M/C guard gaps too short: M-C=%0d C-START=%0d",
          accepted_cycle[4]-accepted_cycle[3],accepted_cycle[5]-accepted_cycle[4]);
    if(words[3][16] || !words[3][17] || words[4][16] || !words[4][17])
        $fatal(1,"bypass/odd-duty packing wrong");

    user_reset=1; repeat(4) @(negedge clk_sys); user_reset=0;
    wait_visible();
    if(!selected_crt) $fatal(1,"user reset changed selected mode");
    native_locked=0; repeat(4) @(negedge clk_sys);
    if(!transport_reset || !selected_crt) $fatal(1,"lock loss did not blank while retaining mode");
    native_locked=1;
    timeout=0;
    while(blank_output && timeout<10000) begin
        @(negedge clk_sys); timeout=timeout+1;
        if(timeout%100==0) tick_frame();
    end
    if(blank_output) $fatal(1,"lock recovery warmup timed out");
    $display("PASS output controller: native/CRT M-C-START packing, busy/done stalls, two-frame warmup, reset mode retention, lock recovery");
    $finish;
end
initial begin #5000000; $fatal(1,"global timeout"); end
endmodule
