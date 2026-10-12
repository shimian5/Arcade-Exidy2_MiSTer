`timescale 1ns/1ps
// Isolated HPS ioctl adapter. It normalizes the real hps_io widths, emits
// non-overlapping transaction events, and holds the host before CVSD overwrite.
module exidy_transport_adapter (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        raw_download,
    input  logic [15:0] raw_index,
    input  logic        raw_wr,
    input  logic [26:0] raw_addr,
    input  logic [7:0]  raw_data,
    input  logic        cvsd_quarantine_ack,
    input  logic        cvsd_ack_generation,
    output logic        ioctl_wait,
    output logic        quarantine_request,
    output logic        quarantine_generation,
    output logic        transfer_begin,
    output logic        transfer_end,
    output logic        ioctl_wr,
    output logic [7:0]  ioctl_index,
    output logic [23:0] ioctl_addr,
    output logic [7:0]  ioctl_data,
    output logic        adapter_fault,
    output logic        transfer_active
);
    logic download_d;
    logic end_pending;
    logic [1:0] drain_count;
    logic [7:0] active_index;
    logic [23:0] expected_addr;
    logic [23:0] accepted_count;
    logic pending_valid;
    logic [15:0] pending_index;
    logic [26:0] pending_addr;
    logic [7:0] pending_data;
    logic cvsd_end_ok;
    (* async_reg = "true" *) logic ack_meta;
    (* async_reg = "true" *) logic ack_sync;
    (* async_reg = "true" *) logic generation_meta, generation_sync;
    wire handshake_ready = ack_sync && (generation_sync == quarantine_generation);

    wire start_event = raw_download && !download_d;
    wire stop_event = !raw_download && download_d;
    wire bad_start = start_event && (transfer_active || end_pending ||
                                    (raw_index[15:8] != 0) || adapter_fault);
    wire bad_index = transfer_active && raw_download &&
                     (raw_index != {8'd0, active_index});

    assign ioctl_wait = (start_event || (quarantine_request && !handshake_ready)) &&
                        (((transfer_active) && (active_index == 8'd6)) ||
                         (start_event && (raw_index == 16'd6)));

    task automatic forward_byte(input logic [15:0] src_index,
                                input logic [26:0] src_addr,
                                input logic [7:0] src_data);
        begin
            if (adapter_fault) begin
                // A faulted session is closed until the shared reset.
            end else if ((src_index[15:8] != 0) || (src_index[7:0] != active_index) ||
                (src_addr[26:24] != 0) || (src_addr[23:0] != expected_addr)) begin
                adapter_fault <= 1'b1;
                quarantine_request <= 1'b1;
            end else begin
                ioctl_wr <= 1'b1;
                ioctl_index <= active_index;
                ioctl_addr <= src_addr[23:0];
                ioctl_data <= src_data;
                expected_addr <= expected_addr + 24'd1;
                accepted_count <= accepted_count + 24'd1;
            end
        end
    endtask

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            download_d <= 1'b0;
            end_pending <= 1'b0;
            drain_count <= 0;
            active_index <= 0;
            expected_addr <= 0;
            accepted_count <= 0;
            pending_valid <= 1'b0;
            pending_index <= 0;
            pending_addr <= 0;
            pending_data <= 0;
            cvsd_end_ok <= 1'b0;
            quarantine_request <= 1'b1; // unknown boot state is quarantined
            transfer_begin <= 1'b0;
            transfer_end <= 1'b0;
            ioctl_wr <= 1'b0;

            ioctl_index <= 0;
            ioctl_addr <= 0;
            ioctl_data <= 0;
            adapter_fault <= 1'b0;
            transfer_active <= 1'b0;
            ack_meta <= 1'b0;
            ack_sync <= 1'b0;
            quarantine_generation <= 1'b0;
            generation_meta <= 1'b0;
            generation_sync <= 1'b0;
        end else begin
            download_d <= raw_download;
            ack_meta <= cvsd_quarantine_ack;
            ack_sync <= ack_meta;
            generation_meta <= cvsd_ack_generation;
            generation_sync <= generation_meta;
            transfer_begin <= 1'b0;
            transfer_end <= 1'b0;
            ioctl_wr <= 1'b0;

            if (adapter_fault) begin
                quarantine_request <= 1'b1;
                pending_valid <= 1'b0; // discard, never replay a faulted byte
            end

            if (start_event) begin
                if (bad_start) begin
                    adapter_fault <= 1'b1;
                    quarantine_request <= 1'b1;
                end else begin
                    transfer_active <= 1'b1;
                    active_index <= raw_index[7:0];
                    // Begin and its index must be registered together so the
                    // downstream loader samples the new stream, not the last one.
                    ioctl_index <= raw_index[7:0];
                    expected_addr <= 0;
                    accepted_count <= 0;
                    transfer_begin <= 1'b1;
                    // Never toggle an unacknowledged generation back to its old
                    // value: an aborted transfer with a stopped remote clock
                    // must reuse the still-pending revocation.
                    if ((raw_index == 16'd6) &&
                        (generation_sync == quarantine_generation))
                        quarantine_generation <= !quarantine_generation;
                    if (raw_index == 16'd1 || raw_index == 16'd6) begin
                        quarantine_request <= 1'b1;
                        cvsd_end_ok <= 1'b0;
                    end
                end
            end

            if (bad_index) begin
                adapter_fault <= 1'b1;
                quarantine_request <= 1'b1;
            end

            // One skid byte covers a write already in flight when backpressure
            // asserts. ioctl_wait prevents the host from issuing the next word.
            if (!adapter_fault && !bad_start && !bad_index) begin
            if (pending_valid && ((active_index != 8'd6) || handshake_ready)) begin
                forward_byte(pending_index, pending_addr, pending_data);
                // The outgoing skid byte owns this cycle's write port. Retain
                // a simultaneous arrival for the next cycle instead of dropping it.
                pending_valid <= raw_wr && transfer_active;
                if (raw_wr && transfer_active) begin
                    pending_index <= raw_index;
                    pending_addr <= raw_addr;
                    pending_data <= raw_data;
                end
            end else if (raw_wr && transfer_active) begin
                if ((active_index == 8'd6) && !handshake_ready) begin
                    if (pending_valid) begin
                        adapter_fault <= 1'b1;
                        quarantine_request <= 1'b1;
                    end
                    else begin
                        pending_valid <= 1'b1;
                        pending_index <= raw_index;
                        pending_addr <= raw_addr;
                        pending_data <= raw_data;
                    end
                end else begin
                    forward_byte(raw_index, raw_addr, raw_data);
                end
            end else if (start_event && raw_wr && !transfer_active &&
                         !end_pending && (raw_index[15:8] == 0)) begin
                // A start and first write on one sampled edge are serialized:
                // begin pulse first, then this one-entry skid byte.
                pending_valid <= 1'b1;
                pending_index <= raw_index;
                pending_addr <= raw_addr;
                pending_data <= raw_data;
            end
            end

            if (stop_event && transfer_active) begin
                end_pending <= 1'b1;
                drain_count <= 2;
            end

            if (end_pending) begin
                // Byte handling above also owns late writes during the drain;
                // a second handler here would fault or double-handle arrivals.
                if ((raw_wr && transfer_active) || pending_valid) begin
                    drain_count <= 2;
                end else if (drain_count != 0) begin
                    drain_count <= drain_count - 1'b1;
                end else begin
                    transfer_end <= 1'b1;
                    transfer_active <= 1'b0;
                    end_pending <= 1'b0;
                    if ((active_index == 8'd6) && (accepted_count == 24'h004000) && !adapter_fault) begin
                        quarantine_request <= 1'b0;
                        cvsd_end_ok <= 1'b1;
                    end
                    if ((active_index == 8'd1) && (accepted_count != 24'd1))
                        adapter_fault <= 1'b1;
                end
            end
        end
    end
endmodule

// Remote-clock quarantine. Acknowledge only after new reads are blocked and
// every accepted read has drained from the configured synchronous read pipe.
module exidy_cvsd_read_quarantine #(
    parameter integer READ_LATENCY = 2
) (
    input  logic cvsd_clk,
    input  logic reset_n,
    input  logic quarantine_request,
    input  logic quarantine_generation,
    input  logic read_request,
    output logic read_accept,
    output logic quarantine_ack,
    output logic ack_generation
);
    (* async_reg = "true" *) logic req_meta;
    (* async_reg = "true" *) logic req_sync;
    (* async_reg = "true" *) logic gen_meta, gen_sync;
    logic [READ_LATENCY-1:0] outstanding;

    always_comb begin
        read_accept = read_request && !req_sync && (gen_sync == ack_generation);
        quarantine_ack = req_sync && !(|outstanding) && (gen_sync == ack_generation);
    end

    always_ff @(posedge cvsd_clk or negedge reset_n) begin
        if (!reset_n) begin
            req_meta <= 1'b1;
            req_sync <= 1'b1;
            outstanding <= '0;
            gen_meta <= 1'b0;
            gen_sync <= 1'b0;
            ack_generation <= 1'b0;
        end else begin
            req_meta <= quarantine_request;
            req_sync <= req_meta;
            gen_meta <= quarantine_generation;
            gen_sync <= gen_meta;
            outstanding <= (outstanding << 1) | READ_LATENCY'(read_accept);
            if ((req_sync || (gen_sync != ack_generation)) && !(|outstanding))
                ack_generation <= gen_sync;
        end
    end
endmodule
