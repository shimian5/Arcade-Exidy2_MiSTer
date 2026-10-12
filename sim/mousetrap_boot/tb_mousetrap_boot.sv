`timescale 1ns/1ps
module tb_mousetrap_boot;
    reg clk=0, state_reset_n=0, global_reset=1;
    reg command_commit=0;
    reg [7:0] command_data=8'h11;
    wire [7:0] cvsd_command, io_data, cpu_data, datao;
    wire [15:0] addr;
    wire [211:0] cpu_regs;
    wire cpu_reset, digit, pb0, decoder_reset_n;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    wire cpu_wait_n, rom_read;
    wire [13:0] rom_addr;
    reg rom_ready=0, pending=0;
    reg [7:0] rom_data=0, rom[0:16383];
    integer divider=0, rom_reads=0, io_writes=0, digit_writes=0;
    integer io_log;
    reg prev_io_wr=0;
    reg [127:0] bank_initial, bank_before_warm;
    reg [7:0] first_digit_data [0:31];
    integer first_digit_count=0;
    integer epoch=0;
    integer n;
    string rom_path, io_path, case_name;
    reg raw_case=0;
    reg [7:0] expected_h, expected_l;
    reg clock_state=0, run_clock=1;
    reg expected_first_digit=0;

    always #34.802816 clk=~clk;
    always #32321.520 if(run_clock) clock_state=~clock_state;

    Z80_boot cpu(.clk(clk), .clk_en(divider==0), .reset(cpu_reset),
        .addr(addr), .datai(io_rd ? io_data : cpu_data), .datao(datao),
        .m1(m1), .mem_rd(mem_rd), .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr),
        .wait_n(cpu_wait_n), .busrq_n(1'b1), .intreq(1'b0), .intvec(8'hff),
        .intack(intack), .nmi(1'b0), .REG(cpu_regs));
    speechRomBus bus(.clk(clk), .reset(cpu_reset), .cpu_addr(addr),
        .mem_rd(mem_rd), .io_rd(io_rd), .rom_ready(rom_ready), .rom_data(rom_data),
        .rom_read(rom_read), .rom_addr(rom_addr), .wait_n(cpu_wait_n), .cpu_data(cpu_data));
    mousetrapVoiceIo voice(.clk(clk), .state_reset_n(state_reset_n),
        .decoder_reset_n(state_reset_n), .z80_global_reset(global_reset),
        .io_addr(addr[7:0]), .io_data_in(datao), .io_wr(io_wr),
        .cvsd_clock_state(clock_state), .io_data_out(io_data),
        .riot_pa_write_commit(command_commit), .riot_pa_write_data(command_data),
        .cvsd_data(cvsd_command), .z80_reset(cpu_reset),
        .cvsd_decoder_reset_n(decoder_reset_n), .cvsd_digit(digit), .riot_pb0_in(pb0));

    always @(posedge clk) begin
        divider <= (divider==7) ? 0 : divider+1;
        rom_ready <= rom_read;
        if (rom_read) begin
            rom_data <= rom[rom_addr];
            rom_reads <= rom_reads+1;
            pending <= 1;
        end
        if (rom_ready) pending <= 0;
        if (state_reset_n && io_wr && !prev_io_wr && !cpu_reset) begin
            if ($isunknown({addr[7:0],datao,digit})) begin
                if (raw_case) begin
                    $display("EXPECTED_UNKNOWN_RAW_FIRST_IO at %0t addr=%h data=%h digit=%b",
                        $time,addr[7:0],datao,digit);
                    $fclose(io_log);
                    $finish;
                end
                $fatal(1,"seeded bank case produced unknown I/O data");
            end
            io_writes <= io_writes+1;
            $fdisplay(io_log,"%0t,%0d,%04h,%02h,%0d",$time,epoch,addr,datao,addr[4] ? -1 : datao[0]);
            if (!addr[4]) begin
                if (first_digit_count<32) first_digit_data[first_digit_count] <= datao;
                first_digit_count <= first_digit_count+1;
                digit_writes <= digit_writes+1;
            end
        end
        prev_io_wr <= io_wr;
    end

    task check_initial_bank;
        input [7:0] high0;
        input [7:0] low0;
        input integer high_stride;
        input integer low_stride;
        integer k;
        reg [7:0] h, l;
        begin
            for (k=0;k<8;k=k+1) begin
                h=high0+k*high_stride;
                l=low0+k*low_stride;
                if (cpu_regs[88+k*16 +: 8] !== h || cpu_regs[80+k*16 +: 8] !== l)
                    $fatal(1,"seed bank mismatch mode=%s pair=%0d H=%h L=%h expected=%h/%h",
                        case_name,k,cpu_regs[88+k*16 +: 8],cpu_regs[80+k*16 +: 8],h,l);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("ROM=%s",rom_path) || !$value$plusargs("IO_LOG=%s",io_path) ||
            !$value$plusargs("CASE=%s",case_name)) $fatal(1,"ROM, IO_LOG and CASE plusargs required");
        raw_case=(case_name=="raw");
        $readmemh(rom_path,rom);
        io_log=$fopen(io_path,"w");
        if (!io_log) $fatal(1,"could not create I/O log");
        $fdisplay(io_log,"time_ps,epoch,address,data,digit");
        repeat (6) @(negedge clk);

        if (raw_case) begin
            if (!$isunknown(cpu_regs[207:80]))
                $fatal(1,"uninitialized source did not produce unknown bank state in simulation");
            $display("PASS raw T80_Reg simulation bank is unknown before firmware release");
        end else begin
            case (case_name)
                "zero": begin expected_h=8'h00; expected_l=8'h00; check_initial_bank(8'h00,8'h00,0,0); end
                "seed_a": begin expected_h=8'h20; expected_l=8'h80; check_initial_bank(8'h20,8'h80,1,1); end
                "seed_b": begin expected_h=8'hd0; expected_l=8'h30; check_initial_bank(8'hd0,8'h30,1,3); end
                "seed_odd": begin expected_h=8'h21; expected_l=8'h81; expected_first_digit=1; check_initial_bank(8'h21,8'h81,1,1); end
                default: $fatal(1,"unknown seed case %s",case_name);
            endcase
            bank_initial=cpu_regs[207:80];
        end

        // Keep global CPU reset asserted while releasing the subsystem reset,
        // then deliver the PA4-high command callback and enter the ROM reset vector.
        state_reset_n=1;
        repeat (3) @(negedge clk);
        if (!raw_case && cpu_regs[207:80] !== bank_initial)
            $fatal(1,"T80 reset altered register banks before firmware startup");
        command_data=8'h11;
        command_commit=1;
        @(negedge clk); command_commit=0; global_reset=0;

        if (raw_case) begin
            #3ms;
            if (digit_writes != 0)
                $fatal(1,"raw uninitialized bank unexpectedly produced %0d digit writes",digit_writes);
            $display("EXPECTED_RAW_UNINITIALIZED_NO_DIGITS io_writes=%0d rom_reads=%0d",io_writes,rom_reads);
            $fclose(io_log);
            $finish;
        end

        wait (digit_writes>=16);
        if (first_digit_data[0][0] !== expected_first_digit)
            $fatal(1,"first speech digit bit mode=%s got=%b expected=%b",case_name,first_digit_data[0][0],expected_first_digit);
        // Drain the one-cycle synchronous ROM response before the warm PA4 reset.
        wait (!rom_read && !rom_ready && !pending);
        @(negedge clk);
        bank_before_warm=cpu_regs[207:80];
        command_data=8'h01;
        command_commit=1;
        @(negedge clk); command_commit=0;
        #1;
        if (!cpu_reset) $fatal(1,"PA4-low command did not assert speech CPU reset");
        repeat (8) @(negedge clk);
        if (cpu_regs[207:80] !== bank_before_warm)
            $fatal(1,"PA4 warm reset changed T80 register bank mode=%s before=%h after=%h",
                case_name,bank_before_warm,cpu_regs[207:80]);
        $display("PASS PA4 warm reset retained all 128 physical bank bits mode=%s",case_name);

        epoch=1;
        command_data=8'h11;
        command_commit=1;
        @(negedge clk); command_commit=0;
        #1;
        if (cpu_reset) $fatal(1,"PA4-high command did not release speech CPU");
        wait (digit_writes>=20);
        if (first_digit_count<20) $fatal(1,"firmware did not resume after warm reset");
        $fclose(io_log);
        $display("PASS seeded firmware startup mode=%s reads=%0d IOWrites=%0d digitWrites=%0d bank-before-warm=%h bank-after-warm=%h",
            case_name,rom_reads,io_writes,digit_writes,bank_before_warm,cpu_regs[207:80]);
        $finish;
    end

    initial begin #5ms; $display("WATCHDOG phase mode=%s rom_reads=%0d addr=%h mem_rd=%b io_rd=%b io_wr=%b reset=%b wait_n=%b pending=%b ready=%b state=%0d digits=%0d",case_name,rom_reads,addr,mem_rd,io_rd,io_wr,cpu_reset,cpu_wait_n,pending,rom_ready,bus.state,digit_writes); $fatal(1,"boot test watchdog mode=%s",case_name); end
endmodule
