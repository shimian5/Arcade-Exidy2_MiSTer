`timescale 1ns/1ps
module tb_t80_speech_bridge_reset;
    logic clk=0, cvsd_clk=0, cvsd_run=1, reset_n=0;
    logic raw_download=0, raw_wr=0;
    logic [15:0] raw_index=0;
    logic [26:0] raw_addr=0;
    logic [7:0] raw_data=0;
    logic cpu_reset_request=1;
    wire reset_hold;
    wire remote_reads_ready;
    wire cpu_reset_n_async = reset_n && !cpu_reset_request && !reset_hold;
    wire cpu_reset_n;
    wire cpu_reset = !cpu_reset_n;
    logic [15:0] addr;
    wire [7:0] datao;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack, wait_n, rom_read;
    wire [13:0] rom_addr;
    wire [7:0] cpu_data, adapter_data;
    wire [7:0] question_data, cvsd_data, active_profile;
    wire question_valid, cvsd_valid, ioctl_wait, legacy_base_wr, expansion_ready;
    wire adapter_fault, protocol_fault, ioctl_wr, transfer_begin, transfer_end, transfer_active;
    wire [7:0] ioctl_index, ioctl_data;
    wire [23:0] ioctl_addr;
    wire quarantine_request, quarantine_generation, read_accept, cvsd_quarantine_ack, cvsd_ack_generation;
    logic question_read=0;
    logic [4:0] question_bank=0;
    logic [15:0] question_cpu_addr=0;
    logic [13:0] cvsd_addr=0;
    integer timeout;
    integer accepted_remote_reads=0;
    integer zero_read_count=0;
    logic zero_read_active=0;

    always #5 clk=~clk;
    // CPU and the CVSD read port share the documented speech clock. The
    // loader/download domain runs at 10 ns with a 4 ns phase offset.
    initial begin
        #1; cvsd_clk=1;
        forever begin #37; if(cvsd_run) cvsd_clk=~cvsd_clk; end
    end

    // Main-domain reset_hold and the remote-domain drain/readiness condition
    // assert asynchronously here and release through two speech-clock stages.
    exidy_reset_sync cpu_reset_sync(.clk(cvsd_clk),.reset_n(cpu_reset_n_async),.reset_n_sync(cpu_reset_n));
    Z80 cpu (.clk(cvsd_clk), .clk_en(1'b1), .reset(cpu_reset), .addr(addr),
        .datai(cpu_data), .datao(datao), .m1(m1), .mem_rd(mem_rd), .mem_wr(mem_wr),
        .io_rd(io_rd), .io_wr(io_wr), .wait_n(wait_n), .busrq_n(1'b1),
        .intreq(1'b0), .intvec(8'hff), .intack(intack), .nmi(1'b0));
    speechRomBus adapter (.clk(cvsd_clk), .reset(cpu_reset), .cpu_addr(addr), .mem_rd(mem_rd), .io_rd(io_rd),
        .rom_ready(cvsd_valid), .rom_data(cvsd_data), .rom_read(rom_read), .rom_addr(rom_addr),
        .wait_n(wait_n), .cpu_data(adapter_data));
    assign cpu_data=adapter_data;
    exidy_expansion_bridge_rr bridge (
        .clk(clk), .reset_n(reset_n), .cvsd_clk(cvsd_clk), .raw_download(raw_download), .raw_wr(raw_wr),
        .raw_index(raw_index), .raw_addr(raw_addr), .raw_data(raw_data), .question_read(question_read),
        .question_bank(question_bank), .question_cpu_addr(question_cpu_addr), .cvsd_read(rom_read),
        .cvsd_addr(rom_addr), .question_data(question_data), .cvsd_data(cvsd_data), .active_profile(active_profile),
        .question_valid(question_valid), .cvsd_valid(cvsd_valid), .ioctl_wait(ioctl_wait),
        .legacy_base_wr(legacy_base_wr), .reset_hold(reset_hold), .expansion_ready(expansion_ready),
        .adapter_fault(adapter_fault), .protocol_fault(protocol_fault), .ioctl_wr(ioctl_wr),
        .transfer_begin(transfer_begin), .transfer_end(transfer_end), .transfer_active(transfer_active),
        .ioctl_index(ioctl_index), .ioctl_data(ioctl_data), .ioctl_addr(ioctl_addr),
        .quarantine_request(quarantine_request), .quarantine_generation(quarantine_generation),
        .read_accept(read_accept), .cvsd_quarantine_ack(cvsd_quarantine_ack), .cvsd_ack_generation(cvsd_ack_generation));
    assign remote_reads_ready = !bridge.remote.req_sync &&
                                (bridge.remote.gen_sync == bridge.remote.ack_generation) &&
                                !(|bridge.remote.outstanding);

    function automatic [7:0] payload(input integer a);
        case(a)
            0: payload=8'hc3; 1: payload=8'h04; 2: payload=8'h00; 4: payload=8'h76;
            default: payload=8'((a*13) ^ (a>>7) ^ 8'h5a);
        endcase
    endfunction

    task automatic begin_stream(input [15:0] idx);
        @(negedge clk); raw_index=idx; raw_addr=0; raw_wr=0; raw_download=1;
        timeout=0;
        while(!transfer_active && timeout<50) begin @(negedge clk); timeout++; end
        if(!transfer_active) $fatal(1,"transfer begin timeout index=%0d",idx);
    endtask
    task automatic byte_write(input integer a,input [7:0] value);
        integer spins;
        begin
            spins=0;
            while(ioctl_wait && spins<1000) begin @(negedge clk); spins++; end
            if(ioctl_wait) $fatal(1,"transport wait timeout index=%0d addr=%0d",raw_index,a);
            @(negedge clk); raw_addr=27'(a); raw_data=value; raw_wr=1;
            @(negedge clk); raw_wr=0;
        end
    endtask
    task automatic end_stream;
        integer spins;
        begin
            @(negedge clk); raw_wr=0; raw_download=0;
            spins=0;
            while(transfer_active && spins<100) begin @(negedge clk); spins++; end
            if(transfer_active) $fatal(1,"transfer end timeout index=%0d",raw_index);
            repeat(3) @(negedge clk);
            if(adapter_fault) $fatal(1,"transport fault index=%0d",raw_index);
        end
    endtask
    task automatic marker;
        begin_stream(1); byte_write(0,8'h90); end_stream();
    endtask
    task automatic descriptor;
        reg [7:0] d[0:15];
        begin
            d='{8'h45,8'h58,8'h01,8'h03,8'h05,8'h01,8'h00,8'h00,
               8'h00,8'h00,8'h00,8'h00,8'h40,8'h00,8'h00,8'h00};
            begin_stream(7);
            for(integer i=0;i<16;i++) byte_write(i,d[i]);
            end_stream();
            if(protocol_fault) $fatal(1,"descriptor rejected");
        end
    endtask
    task automatic base;
        begin_stream(0); byte_write(0,8'h42); end_stream();
    endtask
    task automatic write_speech_payload;
        for(integer i=0;i<16384;i++) byte_write(i,payload(i));
        end_stream();
    endtask
    task automatic wait_image_ready;
        wait(expansion_ready && !reset_hold && !quarantine_request && remote_reads_ready);
        if(cvsd_ack_generation !== quarantine_generation) $fatal(1,"image ready with mismatched generation");
    endtask
    task automatic start_new_session;
        begin
            marker(); descriptor(); base();
            begin_stream(6);
            repeat(4) @(negedge clk);
            if(quarantine_generation==cvsd_ack_generation)
                $fatal(1,"generation did not toggle while CVSD clock was stopped");
            if(!cpu_reset || !ioctl_wait || !reset_hold)
                $fatal(1,"old-generation acknowledgment released CPU/download");
            $display("PASS old generation ack held CPU reset with CVSD clock stopped");
            cvsd_run=1;
            timeout=0;
            while(cvsd_ack_generation!=quarantine_generation && timeout<100) begin @(negedge cvsd_clk); timeout++; end
            if(cvsd_ack_generation!=quarantine_generation) $fatal(1,"matching generation ack timeout");
            if(!cpu_reset) $fatal(1,"CPU reset released before session payload/readiness completed");
            write_speech_payload();
            wait_image_ready();
        end
    endtask

    always @(posedge cvsd_clk) begin
        if(read_accept) accepted_remote_reads++;
        #1;
        if(!cpu_reset && mem_rd && !io_rd && addr==16'h0000 && wait_n) begin
            if(adapter_data!==8'hc3) $fatal(1,"post-reset $0000 read returned %h",adapter_data);
            if(!zero_read_active) zero_read_count++;
            zero_read_active <= 1;
        end else zero_read_active <= 0;
    end

    initial begin
        $display("START");
        repeat(5) @(negedge clk); reset_n=1;
        wait(!bridge.reset_n_main && !bridge.reset_n_cvsd);
        wait(bridge.reset_n_main && bridge.reset_n_cvsd);
        marker(); descriptor(); base();
        begin_stream(6); write_speech_payload(); wait_image_ready();
        $display("Release source reset=%b hold=%b remote=%b r_sync=%b gen=%b ack=%b",cpu_reset_n_async,reset_hold,remote_reads_ready,bridge.remote.req_sync,bridge.remote.gen_sync,bridge.remote.ack_generation);
        cpu_reset_request=0;
        repeat(3) @(posedge cvsd_clk); #1;
        $display("CPU reset_n=%b reset=%b source=%b addr=%h",cpu_reset_n,cpu_reset,cpu_reset_n_async,addr);
        repeat(10) @(posedge cvsd_clk); #1;
        $display("CPU controls mem_rd=%b m1=%b wait=%b addr=%h adapter_state=%0d",mem_rd,m1,wait_n,addr,adapter.state);
        // The synthetic program jumps to $0004. Reset while the accepted read
        // response and quarantine pipe are still in flight, then stop CVSD.
        wait(rom_read && rom_addr==14'h0004); $display("GOT $0004 @%0t",$time);
        timeout=accepted_remote_reads;
        @(posedge cvsd_clk); #1;
        if(accepted_remote_reads==timeout || !bridge.remote.outstanding[0])
            $fatal(1,"did not capture accepted request in remote outstanding pipe");
        cvsd_run=0;
        cpu_reset_request=1;
        $display("STOP accepted, start new session @%0t",$time);
        start_new_session();
        cpu_reset_request=0;
        timeout=0;
        while(zero_read_count==0 && timeout<100) begin @(negedge cvsd_clk); timeout++; end
        if(zero_read_count==0) $fatal(1,"first post-reset $0000 read missing");
        $display("PASS accepted in-flight reset and post-reset data c3");

        // Also abort a not-yet-sampled CPU request: hold the speech clock low
        // after the adapter raises rom_read but before the next speech edge.
        wait(addr==16'h0004 && !mem_rd);
        cpu_reset_request=1;
        repeat(3) @(negedge cvsd_clk);
        cpu_reset_request=0;
        wait(rom_read && rom_addr==14'h0000);
        timeout=accepted_remote_reads;
        cvsd_run=0;
        #1;
        if(accepted_remote_reads!=timeout || (|bridge.remote.outstanding))
            $fatal(1,"unsampled pulse entered the remote endpoint");
        cpu_reset_request=1;
        start_new_session();
        cpu_reset_request=0;
        timeout=0;
        while(zero_read_count<2 && timeout<100) begin @(negedge cvsd_clk); timeout++; end
        if(zero_read_count<2) $fatal(1,"post-abort $0000 fetch did not complete");
        $display("PASS unsampled request aborted across stopped-domain reset; post-reset data c3");
        #20 $finish;
    end
    initial begin #3000000; $fatal(1,"full bridge reset fixture timeout"); end
endmodule







