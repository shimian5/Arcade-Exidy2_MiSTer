`timescale 1ns/1ps
// Separate block-RAM inference candidate; baseline and production unchanged.
module exidy_expansion_loader (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        transfer_begin,
    input  logic        transfer_end,
    input  logic        ioctl_wr,
    input  logic [7:0]  ioctl_index,
    input  logic [23:0] ioctl_addr,
    input  logic [7:0]  ioctl_data,

    // Keep the established index-0 byte stream live and unmodified.
    output logic        legacy_base_wr,

    // Assert alongside existing reset/download gating while an extended image
    // is incomplete or has faulted.
    output logic        reset_hold,
    output logic        expansion_ready,
    output logic        protocol_fault,
    output logic [7:0]  active_profile,

    input  logic        question_read,
    input  logic [4:0]  question_bank,
    input  logic [15:0] question_cpu_addr,
    output logic [7:0]  question_data,
    output logic        question_valid,

    input  logic        cvsd_clk,
    input  logic        cvsd_read,
    input  logic [13:0] cvsd_addr,
    output logic [7:0]  cvsd_data,
    output logic        cvsd_valid
);
    localparam logic [7:0] INDEX_BASE = 8'd0;
    localparam logic [7:0] INDEX_PCB = 8'd1;
    localparam logic [7:0] INDEX_OPTIONS = 8'd2;
    localparam logic [7:0] INDEX_QUESTION = 8'd5;
    localparam logic [7:0] INDEX_CVSD = 8'd6;
    localparam logic [7:0] INDEX_DESCRIPTOR = 8'd7;
    localparam logic [23:0] QUESTION_BYTES = 24'h030000;
    localparam logic [23:0] CVSD_BYTES = 24'h004000;
    localparam int Q_DEPTH = 196608; // 24 banks * 8192 bytes
    localparam int CVSD_DEPTH = 16384;

    logic [7:0] question_mem [0:Q_DEPTH-1];
    logic [7:0] cvsd_mem [0:CVSD_DEPTH-1];
    logic [7:0] descriptor [0:15];

    logic transfer_active;
    logic [7:0] transfer_index;
    logic [23:0] transfer_count;
    logic transfer_fault;

    logic extended_armed;
    logic extended_pending;
    logic descriptor_valid;
    logic base_seen;
    logic question_seen;
    logic cvsd_seen;
    logic [6:0] marker_pcb;
    logic [7:0] marker_byte;
    logic [23:0] expected_base_len;
    logic [23:0] expected_question_len;
    logic [23:0] expected_cvsd_len;
    logic [7:0] descriptor_profile;
    logic [7:0] descriptor_mask;
    logic [17:0] q_read_address;
    logic [7:0] question_ram_data, cvsd_ram_data;
    logic question_result_from_ram, cvsd_result_from_ram;

    logic cvsd_ready_clk;
    (* async_reg = "true" *) logic cvsd_ready_meta;
    (* async_reg = "true" *) logic cvsd_ready_sync;

    // Match the existing downloader's live index-0 write decode, including
    // malformed/progression-fault packets so the legacy path is never buffered.
    assign legacy_base_wr = ioctl_wr && (ioctl_index == INDEX_BASE);
    assign reset_hold = extended_pending || protocol_fault;
    assign q_read_address = question_offset(question_bank, question_cpu_addr[12:0]);
    assign question_data = question_result_from_ram ? question_ram_data : 8'd0;
    assign cvsd_data = cvsd_result_from_ram ? cvsd_ram_data : 8'd0;

    wire valid_download_byte = ioctl_wr && transfer_active && !transfer_begin &&
                               (ioctl_index == transfer_index) && (ioctl_addr == transfer_count);
    wire question_write = valid_download_byte && (transfer_index == INDEX_QUESTION) &&
                          !protocol_fault && extended_armed && descriptor_valid && base_seen &&
                          ((descriptor_profile == 8'd1) || (descriptor_profile == 8'd2)) &&
                          !question_seen && (ioctl_addr < QUESTION_BYTES);
    wire cvsd_write = valid_download_byte && (transfer_index == INDEX_CVSD) &&
                      !protocol_fault && extended_armed && descriptor_valid && base_seen &&
                      (descriptor_profile == 8'd3) && !cvsd_seen && (ioctl_addr < CVSD_BYTES);
    wire question_window_ready = expansion_ready && !protocol_fault &&
                                 ((active_profile == 8'd1) || (active_profile == 8'd2)) &&
                                 (question_cpu_addr >= 16'h2000) && (question_cpu_addr <= 16'h3fff);
    wire question_ram_read = question_read && question_window_ready && (question_bank < 5'd24);

    // RAM processes have no asynchronous reset or output-zero mux. Registered
    // result selectors below provide the same reset/read-visible contract.
    always_ff @(posedge clk) begin
        if (reset_n && question_write) question_mem[ioctl_addr[17:0]] <= ioctl_data;
        if (reset_n && cvsd_write) cvsd_mem[ioctl_addr[13:0]] <= ioctl_data;
    end
    always_ff @(posedge clk) begin
        if (question_ram_read) question_ram_data <= question_mem[q_read_address];
    end
    always_ff @(posedge cvsd_clk) begin
        if (cvsd_read && cvsd_ready_sync) cvsd_ram_data <= cvsd_mem[cvsd_addr];
    end

    function automatic logic [23:0] descriptor_u24(input integer low_byte);
        descriptor_u24 = {descriptor[low_byte+2], descriptor[low_byte+1], descriptor[low_byte]};
    endfunction

    function automatic logic [17:0] question_offset(input logic [4:0] bank, input logic [12:0] address_low);
        question_offset = {bank, address_low};
    endfunction

    task automatic clear_extension;
        begin
            extended_armed <= 1'b0;
            extended_pending <= 1'b0;
            descriptor_valid <= 1'b0;
            expansion_ready <= 1'b0;
            protocol_fault <= 1'b0;
            base_seen <= 1'b0;
            question_seen <= 1'b0;
            cvsd_seen <= 1'b0;
            active_profile <= 8'd0;
            expected_base_len <= 24'd0;
            expected_question_len <= 24'd0;
            expected_cvsd_len <= 24'd0;
            descriptor_mask <= 8'd0;
            cvsd_ready_clk <= 1'b0;
        end
    endtask

    always_ff @(posedge clk or negedge reset_n) begin : download_and_main_read
        if (!reset_n) begin
            transfer_active <= 1'b0;
            transfer_index <= 8'd0;
            transfer_count <= 24'd0;
            transfer_fault <= 1'b0;
            extended_armed <= 1'b0;
            extended_pending <= 1'b0;
            descriptor_valid <= 1'b0;
            expansion_ready <= 1'b0;
            protocol_fault <= 1'b0;
            active_profile <= 8'd0;
            marker_pcb <= 7'd0;
            marker_byte <= 8'd0;
            expected_base_len <= 24'd0;
            expected_question_len <= 24'd0;
            expected_cvsd_len <= 24'd0;
            descriptor_mask <= 8'd0;
            base_seen <= 1'b0;
            question_seen <= 1'b0;
            cvsd_seen <= 1'b0;
            cvsd_ready_clk <= 1'b0;
            question_result_from_ram <= 1'b0;
            question_valid <= 1'b0;
        end else begin
            question_valid <= 1'b0;

            if (transfer_begin) begin
                if (transfer_active) begin
                    protocol_fault <= 1'b1;
                    expansion_ready <= 1'b0;
                    extended_pending <= 1'b1;
                    cvsd_ready_clk <= 1'b0;
                    transfer_active <= 1'b0;
                end else begin
                    transfer_active <= 1'b1;
                    transfer_index <= ioctl_index;
                    transfer_count <= 24'd0;
                    transfer_fault <= 1'b0;
                    if (ioctl_index == INDEX_PCB) begin
                        clear_extension();
                        extended_pending <= 1'b1; // marker must resolve before running
                        marker_byte <= 8'd0;
                    end else if ((ioctl_index == INDEX_BASE) && (!extended_armed || protocol_fault)) begin
                        // Legacy loader order is index 0 then index 1. Never let an
                        // old completed descriptor reinterpret this new base image.
                        clear_extension();
                    end
                    if (((ioctl_index == INDEX_QUESTION) || (ioctl_index == INDEX_CVSD)) &&
                        !base_seen) transfer_fault <= 1'b1;
                    if ((ioctl_index == INDEX_BASE) && extended_armed && base_seen && !protocol_fault)
                        transfer_fault <= 1'b1;
                end
            end

            if (ioctl_wr && transfer_active && !transfer_begin) begin
                if ((ioctl_index != transfer_index) || (ioctl_addr != transfer_count)) begin
                    transfer_fault <= 1'b1;
                end else begin
                    transfer_count <= transfer_count + 24'd1;
                    if (transfer_index == INDEX_PCB) begin
                        if (ioctl_addr == 24'd0) marker_byte <= ioctl_data;
                        else transfer_fault <= 1'b1;
                    end else if (transfer_index == INDEX_DESCRIPTOR) begin
                        if (ioctl_addr < 24'd16) descriptor[ioctl_addr[3:0]] <= ioctl_data;
                        else transfer_fault <= 1'b1;
                    end else if (transfer_index == INDEX_QUESTION) begin
                        if (protocol_fault || !extended_armed || !descriptor_valid || !base_seen ||
                            ((descriptor_profile != 8'd1) && (descriptor_profile != 8'd2)) ||
                            question_seen || (ioctl_addr >= QUESTION_BYTES)) begin
                            transfer_fault <= 1'b1;
                        end
                    end else if (transfer_index == INDEX_CVSD) begin
                        if (protocol_fault || !extended_armed || !descriptor_valid || !base_seen ||
                            (descriptor_profile != 8'd3) || cvsd_seen || (ioctl_addr >= CVSD_BYTES)) begin
                            transfer_fault <= 1'b1;
                        end
                    end else if ((transfer_index == INDEX_BASE) && extended_armed) begin
                        if (!descriptor_valid || base_seen || (expected_base_len == 24'd0) ||
                            (ioctl_addr >= expected_base_len)) begin
                            transfer_fault <= 1'b1;
                        end
                    end
                end
            end

            if (transfer_end && transfer_active && !transfer_begin) begin
                transfer_active <= 1'b0;
                if (transfer_fault) begin
                    protocol_fault <= 1'b1;
                    expansion_ready <= 1'b0;
                    extended_pending <= extended_armed || (transfer_index == INDEX_PCB) ||
                                        (transfer_index == INDEX_DESCRIPTOR);
                    cvsd_ready_clk <= 1'b0;
                end else if (transfer_index == INDEX_PCB) begin
                    if (transfer_count != 24'd1) begin
                        protocol_fault <= 1'b1;
                        extended_pending <= 1'b1;
                    end else if (!marker_byte[7]) begin
                        clear_extension();
                    end else begin
                        marker_pcb <= marker_byte[6:0];
                        extended_armed <= 1'b1;
                        extended_pending <= 1'b1;
                        protocol_fault <= 1'b0;
                    end
                end else if (transfer_index == INDEX_DESCRIPTOR) begin
                    if (!extended_armed || protocol_fault || descriptor_valid ||
                        (transfer_count != 24'd16) ||
                        (descriptor[0] != 8'h45) || (descriptor[1] != 8'h58) ||
                        (descriptor[2] != 8'd1) ||
                        (descriptor[14] != 8'd0) || (descriptor[15] != 8'd0)) begin
                        protocol_fault <= 1'b1;
                        extended_pending <= 1'b1;
                    end else begin
                        descriptor_profile <= descriptor[3];
                        descriptor_mask <= descriptor[4];
                        expected_base_len <= descriptor_u24(5);
                        expected_question_len <= descriptor_u24(8);
                        expected_cvsd_len <= descriptor_u24(11);
                        if ((descriptor[3] == 8'd1) || (descriptor[3] == 8'd2)) begin
                            if ((descriptor[4] != 8'h03) || (marker_pcb != 7'h30) ||
                                (descriptor_u24(5) == 24'd0) ||
                                (descriptor_u24(8) != QUESTION_BYTES) ||
                                (descriptor_u24(11) != 24'd0)) begin
                                protocol_fault <= 1'b1;
                                extended_pending <= 1'b1;
                            end else begin
                                descriptor_valid <= 1'b1;
                                active_profile <= descriptor[3];
                                protocol_fault <= 1'b0;
                            end
                        end else if (descriptor[3] == 8'd3) begin
                            if ((descriptor[4] != 8'h05) || (marker_pcb != 7'h10) ||
                                (descriptor_u24(5) == 24'd0) ||
                                (descriptor_u24(8) != 24'd0) ||
                                (descriptor_u24(11) != CVSD_BYTES)) begin
                                protocol_fault <= 1'b1;
                                extended_pending <= 1'b1;
                            end else begin
                                descriptor_valid <= 1'b1;
                                active_profile <= descriptor[3];
                                protocol_fault <= 1'b0;
                            end
                        end else begin
                            protocol_fault <= 1'b1;
                            extended_pending <= 1'b1;
                        end
                    end
                end else if ((transfer_index == INDEX_BASE) && extended_armed) begin
                    if (!descriptor_valid || (transfer_count != expected_base_len)) begin
                        protocol_fault <= 1'b1;
                        extended_pending <= 1'b1;
                    end else begin
                        base_seen <= 1'b1;
                        if (((descriptor_mask & 8'h02) == 0) &&
                            ((descriptor_mask & 8'h04) == 0)) begin
                            expansion_ready <= 1'b1;
                            extended_pending <= 1'b0;
                            extended_armed <= 1'b0;
                        end
                    end
                end else if (transfer_index == INDEX_QUESTION) begin
                    if (protocol_fault || !extended_armed || !descriptor_valid || !base_seen ||
                        (descriptor_mask != 8'h03) || (transfer_count != expected_question_len) ||
                        (expected_question_len != QUESTION_BYTES)) begin
                        protocol_fault <= 1'b1;
                        expansion_ready <= 1'b0;
                        extended_pending <= 1'b1;
                    end else begin
                        question_seen <= 1'b1;
                        expansion_ready <= 1'b1;
                        extended_pending <= 1'b0;
                        extended_armed <= 1'b0;
                    end
                end else if (transfer_index == INDEX_CVSD) begin
                    if (protocol_fault || !extended_armed || !descriptor_valid || !base_seen ||
                        (descriptor_mask != 8'h05) || (transfer_count != expected_cvsd_len) ||
                        (expected_cvsd_len != CVSD_BYTES)) begin
                        protocol_fault <= 1'b1;
                        expansion_ready <= 1'b0;
                        extended_pending <= 1'b1;
                        cvsd_ready_clk <= 1'b0;
                    end else begin
                        cvsd_seen <= 1'b1;
                        expansion_ready <= 1'b1;
                        extended_pending <= 1'b0;
                        extended_armed <= 1'b0;
                        cvsd_ready_clk <= 1'b1;
                    end
                end else if ((transfer_index != INDEX_OPTIONS) && (transfer_index != 8'd3) &&
                             (transfer_index != 8'd4) && (transfer_index != INDEX_BASE)) begin
                    protocol_fault <= 1'b1;
                    expansion_ready <= 1'b0;
                    cvsd_ready_clk <= 1'b0;
                end
            end

            if (question_read) begin
                question_result_from_ram <= question_ram_read;
                if (question_window_ready) begin
                    question_valid <= 1'b1;
                end else begin
                    question_valid <= expansion_ready;
                end
            end
        end
    end

    // The readiness bit is the only control crossing into the independent CVSD
    // clock domain. Memory contents use a true dual-clock read/write pattern.
    always_ff @(posedge cvsd_clk or negedge reset_n) begin
        if (!reset_n) begin
            cvsd_ready_meta <= 1'b0;
            cvsd_ready_sync <= 1'b0;
            cvsd_result_from_ram <= 1'b0;
            cvsd_valid <= 1'b0;
        end else begin
            cvsd_ready_meta <= cvsd_ready_clk;
            cvsd_ready_sync <= cvsd_ready_meta;
            cvsd_valid <= 1'b0;
            if (cvsd_read) begin
                cvsd_valid <= cvsd_ready_sync;
                cvsd_result_from_ram <= cvsd_ready_sync;
            end
        end
    end
endmodule
