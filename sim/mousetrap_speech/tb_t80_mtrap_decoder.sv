`timescale 1ns/1ps
// Private ROM is loaded at run time; this fixture embeds no game ROM bytes.
module tb_t80_mtrap_decoder;
    reg clk=0, cold_reset_n=0, global_reset=1;
    reg clock_state=0, command_commit=0;
    reg [7:0] command_data=8'h11;
    wire [7:0] command, io_data, cpu_data, datao;
    wire [15:0] addr;
    wire cpu_reset, digit, pb0, decoder_reset_n;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    wire wait_n, rom_read;
    wire [13:0] rom_addr;
    reg rom_ready=0;
    reg [7:0] rom_data=0, rom[0:16383];
    wire signed [31:0] sample_q24, integrator_q24;
    wire [31:0] step_q24;
    wire [2:0] history;
    integer divider=0;
    integer io_writes=0, io_reads=0, rom_reads=0, samples=0, nonzero_samples=0;
    integer mem_writes=0, io_log, sample_log, command_code=17;
    reg prev_io_wr=0, prev_io_rd=0, prev_mem_wr=0;
    reg previous_clock=0, sampled_digit=0;
    reg run_clock=1, stream_last_clock=0, stream_valid=0, sample_ce=0;
    integer sample_phase=0, pcm_ticks=0, pcm_nonzero=0, pcm_log;
    wire signed [31:0] pcm_q24;
    wire stream_idle;
    string rom_path, io_path, sample_path, pcm_path;
    // Nominal master = 4*3.579545 MHz; T80 enable /8 = 1.7897725 MHz.
    always #34.921279 clk=~clk;
    // Exact MAME Mouse Trap RC half-period; firmware sees the same clock state.
    always #32321.520 if(run_clock) clock_state=~clock_state;
    always @(posedge clk) begin
        stream_last_clock<=clock_state;
        // Decoder output changes by NBA on the falling edge; deliver it to
        // the renderer one master-clock later, without stale endpoint capture.
        stream_valid<=cold_reset_n && stream_last_clock && !clock_state;
        if (!cold_reset_n) begin sample_phase<=0; sample_ce<=0; end
        else if (sample_phase+192000>=14318180) begin
            sample_phase<=sample_phase+192000-14318180;
            sample_ce<=1;
        end else begin sample_phase<=sample_phase+192000; sample_ce<=0; end
    end
    always @(posedge clk) begin
        divider <= divider==7 ? 0 : divider+1;
        rom_ready <= rom_read;
        if(rom_read) begin rom_data<=rom[rom_addr]; rom_reads=rom_reads+1; end
    end
    Z80 cpu(.clk(clk), .clk_en(divider==0), .reset(cpu_reset), .addr(addr),
        .datai(io_rd ? io_data : cpu_data), .datao(datao), .m1(m1),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr),
        .wait_n(wait_n), .busrq_n(1'b1), .intreq(1'b0),
        .intvec(8'hff), .intack(intack), .nmi(1'b0));
    speechRomBus bus(.clk(clk), .reset(cpu_reset), .cpu_addr(addr),
        .mem_rd(mem_rd), .io_rd(io_rd), .rom_ready(rom_ready), .rom_data(rom_data),
        .rom_read(rom_read), .rom_addr(rom_addr), .wait_n(wait_n), .cpu_data(cpu_data));
    mousetrapVoiceIo voice(.clk(clk), .state_reset_n(cold_reset_n),
        .decoder_reset_n(cold_reset_n), .z80_global_reset(global_reset),
        .io_addr(addr[7:0]), .io_data_in(datao), .io_wr(io_wr),
        .cvsd_clock_state(clock_state), .io_data_out(io_data),
        .riot_pa_write_commit(command_commit), .riot_pa_write_data(command_data),
        .cvsd_data(command), .z80_reset(cpu_reset), .cvsd_decoder_reset_n(decoder_reset_n),
        .cvsd_digit(digit), .riot_pb0_in(pb0));
    exidyMc3417 decoder(.clk(clk), .cold_reset_n(decoder_reset_n),
        .clock_reset(1'b0), .cvsd_clock(clock_state), .digit(digit),
        .sample_q24(sample_q24), .history(history), .step_q24(step_q24),
        .integrator_q24(integrator_q24));
    exidyMc3417Stream stream(.clk(clk), .cold_reset_n(cold_reset_n),
        .sample_ce(sample_ce), .clock_transition(stream_last_clock!=clock_state),
        .sample_valid(stream_valid), .sample_q24(sample_q24),
        .pcm_q24(pcm_q24), .idle(stream_idle));
    always @(posedge clk) begin
        if(cold_reset_n && sample_ce) begin
            #2;
            if ($isunknown({pcm_q24,stream_idle})) $fatal(1,"unknown firmware PCM state");
            pcm_ticks=pcm_ticks+1;
            if(pcm_q24!=0) pcm_nonzero=pcm_nonzero+1;
            $fdisplay(pcm_log,"%0t,%0d,%0d",$time,pcm_q24,stream_idle);
        end
    end
    always @(posedge clk) begin
        if(cold_reset_n) begin
            if(io_wr && !prev_io_wr && !cpu_reset) begin
                if ($isunknown(addr[7:0]) || $isunknown(datao[0]))
                    $fatal(1,"unknown actual-ROM I/O write from uninitialized CPU register bank");
                io_writes=io_writes+1;
                $fdisplay(io_log,"%0t,W,%04h,%02h,%0d",$time,addr,datao,clock_state);
            end
            if(io_rd && !prev_io_rd && !cpu_reset) begin
                io_reads=io_reads+1;
                // Capture completed read data at the stable bus boundary.
                $fdisplay(io_log,"%0t,R,%04h,%02h,%0d",$time,addr,io_data,clock_state);
            end
            if(mem_wr && !prev_mem_wr && !cpu_reset) mem_writes=mem_writes+1;
            if(previous_clock && !clock_state) begin
                samples=samples+1;
                sampled_digit=digit;
                #1;
                if ($isunknown({sampled_digit,history,step_q24,integrator_q24,sample_q24}))
                    $fatal(1,"unknown decoder state in actual-ROM run");
                $fdisplay(sample_log,"%0t,%0d,%0d,%0d,%0d,%0d",
                    $time,sampled_digit,history,step_q24,integrator_q24,sample_q24);
                if(sample_q24!=0) nonzero_samples=nonzero_samples+1;
            end
        end
        prev_io_wr=io_wr; prev_io_rd=io_rd; prev_mem_wr=mem_wr;
        previous_clock=clock_state;
    end
    initial begin
        if(!$value$plusargs("ROM=%s",rom_path) ||
           !$value$plusargs("IO_LOG=%s",io_path) ||
           !$value$plusargs("SAMPLE_LOG=%s",sample_path) ||
           !$value$plusargs("PCM_LOG=%s",pcm_path))
            $fatal(1,"private ROM and output paths required");
        if($value$plusargs("COMMAND=%d",command_code)) begin end
        command_data=command_code;
        $readmemh(rom_path,rom);
        io_log=$fopen(io_path,"w"); sample_log=$fopen(sample_path,"w");
        pcm_log=$fopen(pcm_path,"w");
        if(!io_log || !sample_log || !pcm_log) $fatal(1,"could not create ignored output");
        $fdisplay(io_log,"time_ps,kind,address,data,clock");
        $fdisplay(sample_log,"time_ps,digit,history,step_q24,integrator_q24,sample_q24");
        $fdisplay(pcm_log,"time_ps,pcm_q24,idle");
        repeat(5) @(posedge clk);
        @(negedge clk); cold_reset_n=1; command_commit=1;
        @(negedge clk); command_commit=0;
        @(negedge clk); global_reset=0;
        #200ms;
        run_clock=0;
        #34ms;
        $fclose(io_log); $fclose(sample_log); $fclose(pcm_log);
        if(!stream_idle || pcm_q24!=0 || pcm_ticks<44000 || pcm_nonzero<100)
            $fatal(1,"firmware stream coverage/tail failed ticks=%0d nonzero=%0d idle=%0d pcm=%0d",
                pcm_ticks,pcm_nonzero,stream_idle,pcm_q24);
        $display("PASS actual firmware fixed-rate stream ticks=%0d nonzero=%0d stopped-clock tail=0",pcm_ticks,pcm_nonzero);
        if(rom_reads<100 || io_reads<100 || io_writes<100 ||
           samples<3000 || nonzero_samples<100)
            $fatal(1,"real speech ROM coverage too low ROM=%0d IN=%0d OUT=%0d samples=%0d nonzero=%0d",
                rom_reads,io_reads,io_writes,samples,nonzero_samples);
        $display("PASS actual Mouse Trap ROM + T80 + I/O + decoder command=%02h ROM=%0d IN=%0d OUT=%0d samples=%0d nonzero=%0d ignored_mem_writes=%0d",
            command_data,rom_reads,io_reads,io_writes,samples,nonzero_samples,mem_writes);
        $finish;
    end
endmodule
