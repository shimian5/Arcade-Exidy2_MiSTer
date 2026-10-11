`timescale 1ns/1ps
// Synthetic instruction stream; no game ROM is embedded in this fixture.
module t80_voice_io_case #(parameter integer CPU_DIV=1, parameter integer BROKEN_RAW_CALLBACK=0)(output reg done=0);
    reg clk=0, reset_n=0, global_reset=1, decoder_reset_n=1;
    reg [4:0] riot_addr=0;
    reg [7:0] riot_din=0;
    reg riot_cs=0, riot_rw_n=1;
    wire [7:0] riot_dout, pa_pins, pb_pins;
    wire irq_n;
    wire command_commit;
    wire [7:0] command_data, saved_command;
    wire digit, pb0, cpu_reset, decoder_reset_out;
    reg clock_state=0;
    wire [15:0] addr;
    wire [7:0] datao, rom_data_out, io_data_out;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    wire adapter_wait_n, rom_read;
    wire [13:0] rom_addr;
    reg rom_ready=0;
    reg [7:0] rom_data=0;
    reg [7:0] rom[0:16383];
    integer divider=0, pause_remaining=0, stretch_remaining=0;
    wire clk_en=(divider==0) && (pause_remaining==0);
    wire wait_n=adapter_wait_n && !(io_wr && stretch_remaining>0);
    integer writes=0, reads=0, stores=0, epochs=0;
    integer held_write_cycles=0, disabled_write_cycles=0, wait_write_cycles=0;
    reg prev_wr=0, prev_rd=0, prev_mem_wr=0;
    reg expected_digit=0, expected_pb0=0;
    reg [15:0] held_addr;
    reg [7:0] held_data;
    reg monitor=0;
    always #5 clk=~clk;

    Z80 cpu(.clk(clk), .clk_en(clk_en), .reset(cpu_reset), .addr(addr),
        .datai(io_rd ? io_data_out : rom_data_out), .datao(datao), .m1(m1),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr),
        .wait_n(wait_n), .busrq_n(1'b1), .intreq(1'b0), .intvec(8'hff),
        .intack(intack), .nmi(1'b0));
    speechRomBus rom_bus(.clk(clk), .reset(cpu_reset), .cpu_addr(addr),
        .mem_rd(mem_rd), .io_rd(io_rd), .rom_ready(rom_ready), .rom_data(rom_data),
        .rom_read(rom_read), .rom_addr(rom_addr), .wait_n(adapter_wait_n),
        .cpu_data(rom_data_out));
    mousetrapVoiceCommand command_adapter(.clk(clk), .reset_n(reset_n),
        .accepted_write(riot_cs && !riot_rw_n), .address(riot_addr), .data(riot_din),
        .command_commit(command_commit), .command_data(command_data));
    mousetrapVoiceIo voice(.clk(clk), .state_reset_n(reset_n),
        .decoder_reset_n(decoder_reset_n), .z80_global_reset(global_reset),
        .io_addr(addr[7:0]), .io_data_in(datao), .io_wr(io_wr),
        .cvsd_clock_state(clock_state), .io_data_out(io_data_out),
        .riot_pa_write_commit(command_commit),
        .riot_pa_write_data(BROKEN_RAW_CALLBACK ? riot_din : command_data),
        .cvsd_data(saved_command), .z80_reset(cpu_reset),
        .cvsd_decoder_reset_n(decoder_reset_out), .cvsd_digit(digit), .riot_pb0_in(pb0));
    R6532 riot(.phi2(clk), .rst_n(reset_n), .cs(riot_cs), .rw_n(riot_rw_n),
        .irq_n(irq_n), .add(riot_addr), .din(riot_din), .dout(riot_dout),
        .pa_in(8'hff), .pa_out(pa_pins), .pb_in({7'h7f,pb0}), .pb_out(pb_pins));

    always @(posedge clk) begin
        divider <= (divider==CPU_DIV-1) ? 0 : divider+1;
        if (pause_remaining>0) pause_remaining <= pause_remaining-1;
        if (stretch_remaining>0) stretch_remaining <= stretch_remaining-1;
        rom_ready <= rom_read;
        if (rom_read) rom_data <= rom[rom_addr];
        if (monitor && !cpu_reset) begin
            if (io_wr && !prev_wr) begin
                held_addr=addr; held_data=datao;
                case (writes)
                    0: begin
                        if (addr[7:0]!==8'h10 || datao!==8'h01) $fatal(1,"PB-only OUT wrong");
                        expected_pb0=1;
                        pause_remaining <= 9;
                        stretch_remaining <= 18;
                    end
                    1: begin
                        if (addr[7:0]!==8'h20 || datao!==8'h01) $fatal(1,"digit-only OUT wrong");
                        expected_digit=1;
                    end
                    2: begin
                        if (addr[7:0]!==8'h00 || datao!==8'h00) $fatal(1,"both-low OUT wrong");
                        expected_digit=0; expected_pb0=0;
                    end
                    3: if (addr[7:0]!==8'h30 || datao!==8'h01) $fatal(1,"unselected OUT wrong");
                    4: begin
                        if (addr[7:0]!==8'h00 || datao!==8'h01) $fatal(1,"both-high OUT wrong");
                        expected_digit=1; expected_pb0=1;
                    end
                    default: $fatal(1,"extra I/O write");
                endcase
                writes=writes+1;
            end else if (io_wr) begin
                held_write_cycles=held_write_cycles+1;
                if (!clk_en) disabled_write_cycles=disabled_write_cycles+1;
                if (!wait_n) wait_write_cycles=wait_write_cycles+1;
                if (addr!==held_addr || datao!==held_data) $fatal(1,"held T80 OUT bus changed");
            end
            if (io_rd && !prev_rd) reads=reads+1;
            if (mem_wr && !prev_mem_wr) begin
                if (addr!==16'h2000+stores) $fatal(1,"store address wrong %h",addr);
                case (stores)
                    0: if (datao!==8'hf3) $fatal(1,"T80 command IN failed: %h",datao);
                    1: begin
                        if (datao!==8'h7f) $fatal(1,"T80 low clock IN failed: %h",datao);
                        clock_state=1;
                    end
                    2: if (datao!==8'hf3) $fatal(1,"T80 combined IN failed: %h",datao);
                    3: if (datao!==8'hff) $fatal(1,"T80 unselected IN failed: %h",datao);
                    default: $fatal(1,"extra memory store");
                endcase
                stores=stores+1;
            end
        end
        prev_wr=io_wr; prev_rd=io_rd; prev_mem_wr=mem_wr;
        #1;
        if (monitor && !cpu_reset && (digit!==expected_digit || pb0!==expected_pb0))
            $fatal(1,"OUT side effect misaligned or repeated div=%0d write=%0d",CPU_DIV,writes);
    end

    task automatic tick;
        begin @(posedge clk); #2; end
    endtask
    task automatic riot_write(input [4:0] address, input [7:0] data);
        begin
            @(negedge clk); riot_addr=address; riot_din=data; riot_cs=1; riot_rw_n=0;
            tick();
            @(negedge clk); riot_cs=0; riot_rw_n=1;
            repeat(3) tick();
        end
    endtask
    integer pc=0;
    task automatic emit(input [7:0] value);
        begin rom[pc]=value; pc=pc+1; end
    endtask
    task automatic store(input [7:0] index);
        begin emit(8'h32); emit(index); emit(8'h20); end
    endtask
    initial begin
        foreach(rom[i]) rom[i]=0;
        emit(8'hdb); emit(8'h40); store(0); // command only
        emit(8'hdb); emit(8'h80); store(1); // low clock only
        emit(8'hdb); emit(8'h00); store(2); // command + high clock
        emit(8'h3e); emit(1); emit(8'hd3); emit(8'h10);
        emit(8'hd3); emit(8'h20);
        emit(8'h3e); emit(0); emit(8'hd3); emit(0);
        emit(8'h3e); emit(1); emit(8'hd3); emit(8'h30);
        emit(8'hd3); emit(0);
        emit(8'hdb); emit(8'hc0); store(3); emit(8'h76);
        repeat(5) tick();
        @(negedge clk); reset_n=1;
        repeat(4) tick();
        if(saved_command!==8'hff) $fatal(1,"RIOT reset callback missing");
        riot_write(1,8'hff); // DDR output; ORA=0 => CPU reset
        if(saved_command!==0 || !cpu_reset || pa_pins!==0) $fatal(1,"DDRA callback mismatch");
        riot_write(0,8'h96);
        if(saved_command!==8'h96 || pa_pins!==8'h96) $fatal(1,"ORA callback mismatch");
        @(negedge clk); global_reset=0; monitor=1;
        wait(stores==4); repeat(8) tick();
        if(writes!=5 || reads!=4 || disabled_write_cycles==0 || wait_write_cycles==0)
            $fatal(1,"transaction/stretch coverage incomplete");
        monitor=0; epochs=1;
        riot_write(0,8'h86); // reset CPU without resetting digit/decoder/handshake
        if(!cpu_reset || saved_command!==8'h86 || !digit || !pb0 || !decoder_reset_out)
            $fatal(1,"PA4 CPU reset lost voice state");
        repeat(12) tick();
        if(io_wr || io_rd) $fatal(1,"reset CPU issued I/O");
        // Release by DDRA input bit4, with zero ORA4; callback must pull high.
        @(negedge clk); writes=0; reads=0; stores=0; clock_state=0;
        riot_write(1,8'hef);
        if(cpu_reset || saved_command!==8'h96 || pa_pins!==8'h96)
            $fatal(1,"DDRA release did not apply input pull-up");
        monitor=1;
        wait(stores==4); repeat(8) tick();
        if(writes!=5 || reads!=4) $fatal(1,"warm reset CPU did not replay program");
        // PB0 follows the actual RIOT input register unless DDR selects output.
        riot_write(3,0);
        if(!pb_pins[0]) $fatal(1,"voice PB0 did not reach actual RIOT input");
        riot_write(3,1); riot_write(2,0);
        if(pb_pins[0]) $fatal(1,"RIOT DDR output failed to override voice input");
        $display("PASS T80 voice join div=%0d epochs=2 reads=8 writes=10 held=%0d disabled=%0d wait=%0d",CPU_DIV,held_write_cycles,disabled_write_cycles,wait_write_cycles);
        done=1;
    end
endmodule
module tb_t80_voice_io_join #(parameter integer BROKEN_RAW_CALLBACK=0);
    wire done1,done4;
    t80_voice_io_case #(.CPU_DIV(1), .BROKEN_RAW_CALLBACK(BROKEN_RAW_CALLBACK)) c1(done1);
    t80_voice_io_case #(.CPU_DIV(4), .BROKEN_RAW_CALLBACK(BROKEN_RAW_CALLBACK)) c4(done4);
    initial begin wait(done1 && done4); $display("PASS actual T80 voice I/O and RIOT callback join"); $finish; end
    initial begin #300us; $fatal(1,"T80 voice I/O join watchdog"); end
endmodule
