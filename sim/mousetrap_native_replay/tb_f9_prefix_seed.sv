`timescale 1ns/1ps
// Simulation-only B-seed control for the native Mouse Trap F9 entry prefix.
// The ROM payload is supplied externally; this fixture contains no ROM bytes.
module tb_f9_prefix_seed;
    reg clk=0, cold_reset_n=0, global_reset=1;
    reg clock_state=0, command_commit=0;
    reg [7:0] command_data=8'hEF;
    wire [7:0] command, io_data, cpu_data, datao;
    wire [15:0] addr;
    wire cpu_reset, digit, pb0, decoder_reset_n;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    wire wait_n, rom_read;
    wire [13:0] rom_addr;
    reg rom_ready=0;
    reg [7:0] rom_data=0, rom[0:16383];
    integer divider=0, rom_reads=0, output_count=0;
    integer seed_b=0, io_log;
    reg prev_io_wr=0;
    reg [7:0] io_data_out_byte;
    string rom_path, io_path;

    always #34.921279 clk=~clk;
    always #32321.520 clock_state=~clock_state;
    always @(posedge clk) begin
        divider <= divider==7 ? 0 : divider+1;
        rom_ready <= rom_read;
        if(rom_read) begin rom_data<=rom[rom_addr]; rom_reads=rom_reads+1; end
        if(cold_reset_n && io_wr && !prev_io_wr && !cpu_reset && addr[7:0]==8'hEF) begin
            output_count=output_count+1;
            io_data_out_byte=datao;
            $fdisplay(io_log,"%0t,%0d,%04h,%02h,%0d",$time,output_count,addr,datao,clock_state);
        end
        prev_io_wr=io_wr;
    end

    Z80 cpu(.clk(clk), .clk_en(divider==0), .reset(cpu_reset), .addr(addr),
        .datai(io_rd ? io_data : cpu_data), .datao(datao), .m1(m1),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr),
        .wait_n(wait_n), .busrq_n(1'b1), .intreq(1'b0), .intvec(8'hff),
        .intack(intack), .nmi(1'b0));
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

    task automatic pa(input [7:0] value);
        begin
            @(negedge clk); command_data=value; command_commit=1;
            @(negedge clk); command_commit=0;
            repeat(2) @(negedge clk);
        end
    endtask

    initial begin
        if(!$value$plusargs("ROM=%s",rom_path) || !$value$plusargs("IO_LOG=%s",io_path) ||
           !$value$plusargs("SEED=%d",seed_b)) $fatal(1,"ROM, IO_LOG and SEED required");
        $readmemh(rom_path,rom);
        io_log=$fopen(io_path,"w");
        if(!io_log) $fatal(1,"could not create output log");
        $fdisplay(io_log,"time_ps,ordinal,address,data,clock");
        repeat(5) @(posedge clk);
        @(negedge clk); cold_reset_n=1; pa(8'hEF);
        #131879; pa(8'hF9); global_reset=0;
        fork
            begin
                wait(output_count==3);
                #1000;
                $fclose(io_log);
                if(rom_reads<20) $fatal(1,"insufficient firmware execution: ROM reads=%0d",rom_reads);
                $display("PREFIX seedB=%02h outputs=%0d ROM=%0d",seed_b,output_count,rom_reads);
                $finish;
            end
            begin
                #5ms;
                $fatal(1,"timed out waiting for first three EF writes: writes=%0d ROM=%0d",output_count,rom_reads);
            end
        join
    end
endmodule
