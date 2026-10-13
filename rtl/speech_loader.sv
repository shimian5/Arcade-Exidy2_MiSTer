`timescale 1ns/1ps
// Production binding for the qualified expansion transport. Only Mouse Trap's
// new 90 marker opts in; existing B0/D0 interrupt profiles remain legacy loads.
module exidySpeechLoader (
    input wire clk, audio_clk, reset_n,
    input wire raw_download, raw_wr,
    input wire [15:0] raw_index,
    input wire [24:0] raw_addr,
    input wire [7:0] raw_data,
    input wire speech_read,
    input wire [13:0] speech_addr,
    input wire question_read,
    input wire [4:0] question_bank,
    input wire [15:0] question_cpu_addr,
    output wire [7:0] speech_data,
    output wire speech_valid, speech_enable,
    output wire [7:0] question_data,
    output wire question_valid, question_image_ready,
    output wire ioctl_wait, base_wr, reset_hold,
    output wire [24:0] base_addr,
    output wire [7:0] base_data
);
    wire [7:0] active_profile;
    wire ready, adapter_fault, protocol_fault;
    wire fax_profile_selected = (active_profile == 8'd1) || (active_profile == 8'd2);
    wire relevant = raw_index == 16'd0 || raw_index == 16'd1 ||
                    raw_index == 16'd6 || raw_index == 16'd7 ||
                    ((raw_index == 16'd5) && fax_profile_selected &&
                     !adapter_fault && !protocol_fault);
    wire recognized_marker = raw_data == 8'h90 || raw_data == 8'hF4 || raw_data == 8'hF8;
    wire [7:0] loader_data = raw_index == 16'd1 && !recognized_marker ?
                             {1'b0,raw_data[6:0]} : raw_data;
    wire [7:0] bridge_question_data;
    wire bridge_question_valid;
    wire [23:0] normalized_addr;
    exidy_expansion_bridge_rr bridge (
        .clk(clk), .reset_n(reset_n), .cvsd_clk(audio_clk),
        .raw_download(raw_download && relevant), .raw_wr(raw_wr && relevant),
        .raw_index(raw_index), .raw_addr({2'b00,raw_addr}), .raw_data(loader_data),
        .question_read(question_read), .question_bank(question_bank),
        .question_cpu_addr(question_cpu_addr),
        .cvsd_read(speech_read), .cvsd_addr(speech_addr),
        .question_data(bridge_question_data), .question_valid(bridge_question_valid), .cvsd_data(speech_data),
        .cvsd_valid(speech_valid), .active_profile(active_profile),
        .ioctl_wait(ioctl_wait), .legacy_base_wr(base_wr), .reset_hold(reset_hold),
        .expansion_ready(ready), .adapter_fault(adapter_fault), .protocol_fault(protocol_fault),
        .ioctl_addr(normalized_addr), .ioctl_data(base_data), .ioctl_wr(),
        .ioctl_index(), .transfer_begin(), .transfer_end(), .transfer_active(),
        .quarantine_request(), .quarantine_generation(), .read_accept(),
        .cvsd_quarantine_ack(), .cvsd_ack_generation()
    );
    // Forward the normalized byte/address together with its delayed write pulse.
    assign base_addr = {1'b0,normalized_addr};
    assign question_image_ready = ready && fax_profile_selected &&
                                  !adapter_fault && !protocol_fault;
    assign question_valid = bridge_question_valid && question_image_ready;
    assign question_data = question_image_ready ? bridge_question_data : 8'd0;
    wire enable_main = ready && active_profile == 8'd3 && !adapter_fault && !protocol_fault;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
    reg enable_meta, enable_sync;
    always @(posedge audio_clk or negedge reset_n) begin
        if (!reset_n) begin enable_meta <= 1'b0; enable_sync <= 1'b0; end
        else begin enable_meta <= enable_main; enable_sync <= enable_meta; end
    end
    assign speech_enable = enable_sync;
endmodule
