`timescale 1ns/1ps
module fax_t65_harness #(
    parameter integer STARTUP_CHECK = 0,
    parameter integer IMAGE_READY = 1
) (
    input wire master_clock,
    input wire reset_n,
    output reg done = 0,
    output wire [7:0] ram_zero,
    output wire [7:0] ram_400,
    output wire [4:0] question_bank,
    output wire fax_enabled
);
    reg [6:0] cencnt = 0;
    reg PH_1 = 0;
    always @(posedge master_clock) begin
        cencnt <= cencnt + 7'd1;
        PH_1 <= cencnt[5:0] == 6'd31;
    end

    wire CPU_RWn;
    wire [23:0] CPU_addrbus;
    wire [7:0] CPU_databus_out;
    reg [7:0] CPU_databus_in = 0;
    wire [15:0] cpu_addr = CPU_addrbus[15:0];
    reg [7:0] program_rom [0:65535];
    reg [7:0] work_ram [0:2047];
    reg [7:0] CPU_PROM_out = 0;
    reg [7:0] CPU_RAM_out = 0;
    wire [7:0] VRAM_CPU_out = 8'h00;
    wire [7:0] VRAM_out_CSCG1_CPU = 8'h00;
    wire [7:0] VRAM_out_CSCG2_CPU = 8'h00;
    reg [7:0] question_rom_q = 0;
    reg [7:0] question_rom [0:196607];
    wire fax_controls_selected, fax_question_selected;
    wire [7:0] fax_controls_data, fax_question_data;
    wire question_read;
    wire [15:0] question_cpu_addr;
    wire question_image_ready = IMAGE_READY != 0;
    wire [7:0] pcb = 8'h74;
    wire fax_startup_check = STARTUP_CHECK != 0;
    wire [3:0] p1_answer_pressed = 4'b1010;
    wire [3:0] p2_answer_pressed = 4'b0101;
    wire p1_start1_pressed = 1'b1;
    wire p1_start2_pressed = 1'b0;
    wire p2_start_pressed = 1'b0;
    wire [7:0] DIPSWA = 8'hA6;

    wire RAMSEL = fax_enabled ? (cpu_addr[15:11] != 5'd0) :
                               (cpu_addr[15:10] != 6'd0);
    wire ROMSEL = (cpu_addr[15:13] == 3'b100) || (cpu_addr[15:13] == 3'b111) ? 1'b0 :
                  ((cpu_addr == 16'h1c00) || (cpu_addr == 16'h1a00) ? 1'b1 : 1'b1);
    wire SRAMSEL = 1'b1, CHARSEL = 1'b1, EXTVID = 1'b1;
    wire IOSEL = ((cpu_addr == 16'h1c00) || (cpu_addr == 16'h1a00)) ? 1'b0 : 1'b1;
    wire [7:0] ESR = 8'h00, EIR = 8'h00, audio_data_out = 8'h00, IN2 = 8'h00;

    faxProfileControls #(.STARTUP_CHECK(1'b0)) FAX_CONTROLS (
        .question_image_ready(question_image_ready), .pcb(pcb), .cpu_addr(cpu_addr),
        .cpu_read(CPU_RWn), .other_read_data(8'd0),
        .p1_answer_pressed(p1_answer_pressed), .p2_answer_pressed(p2_answer_pressed),
        .p1_start1_pressed(p1_start1_pressed), .p1_start2_pressed(p1_start2_pressed || p2_start_pressed),
        .fax_enabled(fax_enabled), .fax_selected(fax_controls_selected), .read_data(fax_controls_data)
    );

    faxQuestionWindow FAX_QUESTIONS (
        .fax_enabled(fax_enabled), .cpu_clk(master_clock), .cpu_reset_n(reset_n),
        .cpu_addr(cpu_addr), .cpu_read(CPU_RWn), .cpu_write(PH_1 && !CPU_RWn),
        .cpu_write_data(CPU_databus_out), .question_data(question_rom_q), .other_read_data(8'd0),
        .question_bank(question_bank), .question_read(question_read),
        .question_cpu_addr(question_cpu_addr), .question_selected(fax_question_selected),
        .read_data(fax_question_data)
    );

    always @(posedge master_clock) begin
        CPU_PROM_out <= program_rom[cpu_addr];
        CPU_RAM_out <= work_ram[ fax_enabled ? cpu_addr[10:0] : {1'b0,cpu_addr[9:0]} ];
        question_rom_q <= question_rom[{question_bank,question_cpu_addr[12:0]}];
        if (!CPU_RWn && cpu_addr == 16'h0407 && CPU_databus_out == 8'hC0) done <= 1'b1;
        if (!CPU_RWn && !RAMSEL) begin
            work_ram[fax_enabled ? cpu_addr[10:0] : {1'b0,cpu_addr[9:0]}] <= CPU_databus_out;
        end
    end

    // Generated from the current production fax_input_byte declaration and
    // CPU_databus_in mux in rtl/Exidy2.v by sim/fax_cpu/run.ps1.
    `include "production_fax_read_mux.vh"

    T65 M6502 (
        .Mode(2'b00), .Res_n(reset_n), .Enable(PH_1), .Clk(master_clock), .Rdy(1'b1),
        .Abort_n(1'b1), .IRQ_n(1'b1), .NMI_n(1'b1), .SO_n(1'b1),
        .R_W_n(CPU_RWn), .A(CPU_addrbus), .DI(CPU_databus_in), .DO(CPU_databus_out)
    );

    assign ram_zero = work_ram[0];
    assign ram_400 = work_ram[11'h400];

    task automatic put(input [15:0] address, input [7:0] value);
        program_rom[address] = value;
    endtask

    integer i;
    initial begin
        for (i=0;i<2048;i=i+1) work_ram[i]=0;
        for (i=0;i<196608;i=i+1) question_rom[i]=8'h00;
        for (i=0;i<16;i=i+1) question_rom[(3*8192)+i]=8'hD3 ^ i[7:0];
        // Real 6502 bytecode: write and read both zero-page and FAX's second
        // 1 KiB RAM page, select question bank 3, then sample P1/P2 inputs.
        put(16'h8000,8'h78);                         // SEI
        put(16'h8001,8'hA9); put(16'h8002,8'hA5);   // LDA #$A5
        put(16'h8003,8'h8D); put(16'h8004,8'h00); put(16'h8005,8'h00); // STA $0000
        put(16'h8006,8'hA9); put(16'h8007,8'h5A);   // LDA #$5A
        put(16'h8008,8'h8D); put(16'h8009,8'h00); put(16'h800A,8'h04); // STA $0400
        put(16'h800B,8'hAD); put(16'h800C,8'h00); put(16'h800D,8'h00); // LDA $0000
        put(16'h800E,8'h8D); put(16'h800F,8'h02); put(16'h8010,8'h00); // STA $0002
        put(16'h8011,8'hAD); put(16'h8012,8'h00); put(16'h8013,8'h04); // LDA $0400
        put(16'h8014,8'h8D); put(16'h8015,8'h03); put(16'h8016,8'h00); // STA $0003
        put(16'h8017,8'hA9); put(16'h8018,8'h03);   // LDA #3
        put(16'h8019,8'h8D); put(16'h801A,8'h00); put(16'h801B,8'h20); // STA $2000
        put(16'h801C,8'hAD); put(16'h801D,8'h00); put(16'h801E,8'h20); // LDA $2000
        put(16'h801F,8'h8D); put(16'h8020,8'h04); put(16'h8021,8'h00); // STA $0004
        put(16'h8022,8'hAD); put(16'h8023,8'h00); put(16'h8024,8'h1C); // LDA $1C00
        put(16'h8025,8'h8D); put(16'h8026,8'h05); put(16'h8027,8'h00); // STA $0005
        put(16'h8028,8'hAD); put(16'h8029,8'h00); put(16'h802A,8'h1A); // LDA $1A00
        put(16'h802B,8'h8D); put(16'h802C,8'h06); put(16'h802D,8'h00); // STA $0006
        put(16'h802E,8'hA9); put(16'h802F,8'hC0);   // LDA #$C0
        put(16'h8030,8'h8D); put(16'h8031,8'h07); put(16'h8032,8'h04); // STA $0407
        put(16'h8033,8'h4C); put(16'h8034,8'h33); put(16'h8035,8'h80); // JMP $8033
        put(16'hFFFC,8'h00); put(16'hFFFD,8'h80);
    end
endmodule
