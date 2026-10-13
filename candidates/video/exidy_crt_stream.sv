// SPDX-License-Identifier: GPL-3.0-or-later
// Low-latency RGB24 conversion: native 336x280 to CRT 336x262.
// 32 rolling rows, completed-row publication, no game timing feedback.
// See sim/prove_crt_stream_schedule.py for the exact-rate/phase contract.
module exidy_crt_stream (
	input  wire        clk_native, clk_crt, reset_async,
	input  wire        ce_native,
	input  wire [23:0] rgb_native,
	input  wire [8:0]  x_native, y_native,
	input  wire        hb_native, vb_native,
	output reg         ce_out,
	output reg  [23:0] rgb_out,
	output reg  [8:0]  x_out, y_out,
	output reg         hs_out, vs_out, hb_out, vb_out,
	output wire        frame_valid,
	output reg  [31:0] malformed_frames, source_skips, stream_faults
);
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg [1:0] reset_native_pipe=2'b11, reset_crt_pipe=2'b11;
always @(posedge clk_native or posedge reset_async)
	if(reset_async) reset_native_pipe<=2'b11;
	else reset_native_pipe<={reset_native_pipe[0],1'b0};
always @(posedge clk_crt or posedge reset_async)
	if(reset_async) reset_crt_pipe<=2'b11;
	else reset_crt_pipe<={reset_crt_pipe[0],1'b0};
wire reset_native=reset_native_pipe[1], reset_crt=reset_crt_pipe[1];

reg frame_request, frame_ack, source_fault;
reg [15:0] committed_rows, committed_gray, first_row_sequence;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg ack_meta, ack_sync, request_meta, request_sync, fault_meta, fault_sync;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg [15:0] rows_meta, rows_sync;
always @(posedge clk_native) begin
	if(reset_native) begin ack_meta<=0; ack_sync<=0; end
	else begin ack_meta<=frame_ack; ack_sync<=ack_meta; end
end
always @(posedge clk_crt) begin
	if(reset_crt) begin
		request_meta<=0; request_sync<=0; fault_meta<=0; fault_sync<=0;
		rows_meta<=0; rows_sync<=0;
	end else begin
		request_meta<=frame_request; request_sync<=request_meta;
		fault_meta<=source_fault; fault_sync<=fault_meta;
		rows_meta<=committed_gray; rows_sync<=rows_meta;
	end
end
function automatic [15:0] gray_to_binary(input [15:0] gray);
	reg [15:0] value;
	value[15]=gray[15];
	for(integer bit_index=14;bit_index>=0;bit_index=bit_index-1)
		value[bit_index]=value[bit_index+1]^gray[bit_index];
	return value;
endfunction
wire [15:0] available_rows=gray_to_binary(rows_sync);
wire mailbox_free=frame_request==ack_sync;
// frame_request itself must not be sampled in CRT logic. Only the synchronized
// toggle is used below; the first-row sequence is a held bundled payload.
wire request_pending=request_sync!=frame_ack;
// Capture the held mailbox payload only after its request has crossed the
// synchronizer. Qualify local use one clock later; no source-domain comparison
// may feed RGB/validity directly. The sender holds it until acknowledgement.
reg [15:0] first_sequence_local;
reg captured_request;
always @(posedge clk_crt) begin
	if(reset_crt) begin first_sequence_local<=0; captured_request<=0; end
	else if(request_pending) begin
		first_sequence_local<=first_row_sequence;
		captured_request<=request_sync;
	end
end
wire payload_ready=captured_request==request_sync;
wire source_active=ce_native && !hb_native && !vb_native && x_native<256 && y_native<256;
wire source_start=source_active && x_native==0 && y_native==0;
wire [15:0] source_address={y_native[7:0],x_native[7:0]};
reg capturing;
reg [16:0] expected_address;
// The local reset pipe asserts asynchronously and releases synchronously.
// Raw reset must not create an asynchronous RAM enable/data path.
wire write_pixel=!reset_native && source_active &&
	(source_start ? mailbox_free : capturing && {1'b0,source_address}==expected_address);
wire [15:0] next_commit=committed_rows+16'd1;

// Mixed-clock RAM, without reset or initialization. A row may be prefetched
// only after publication, and displayed only while its sequence is owned.
reg [23:0] pixels[0:8191];
reg [23:0] read_rgb;
reg [8:0] raster_x, raster_y;
reg [2:0] pixel_div;
reg reader_valid;
reg [15:0] read_sequence;
wire [15:0] row_distance=available_rows-read_sequence;
// 0 means the desired row is the latest published row. Reserve the last slot
// for a writer that has begun its next row but has not published it yet.
wire row_ready=row_distance<16'd31;
always @(posedge clk_native) if(write_pixel)
	pixels[{y_native[4:0],x_native[7:0]}]<=rgb_native;
always @(posedge clk_crt) if(reader_valid && row_ready && raster_x<256 && raster_y<256)
	read_rgb<=pixels[{raster_y[4:0],raster_x[7:0]}];

always @(posedge clk_native) begin
	if(reset_native) begin
		frame_request<=0; source_fault<=0; capturing<=0; expected_address<=0;
		committed_rows<=0; committed_gray<=0; first_row_sequence<=0;
		malformed_frames<=0; source_skips<=0;
	end else begin
		if(source_start) begin
			if(capturing) malformed_frames<=malformed_frames+32'd1;
			capturing<=mailbox_free;
			expected_address<=17'd1;
			source_fault<=!mailbox_free;
			if(!mailbox_free) source_skips<=source_skips+32'd1;
		end else if(source_active && capturing) begin
			if({1'b0,source_address}!=expected_address) begin
				capturing<=0; source_fault<=1;
				malformed_frames<=malformed_frames+32'd1;
			end else begin
				expected_address<=expected_address+17'd1;
				if(source_address==16'hffff) capturing<=0;
			end
		end
		if(write_pixel && x_native==255) begin
			committed_rows<=next_commit;
			committed_gray<=next_commit^(next_commit>>1);
			if(y_native==0) begin
				first_row_sequence<=next_commit;
				frame_request<=!frame_request;
			end
		end
	end
end

wire pixel_tick=pixel_div==7;
wire active_pixel=raster_x<256 && raster_y<256;
assign frame_valid=reader_valid && !fault_sync;
always @(posedge clk_crt) begin
	ce_out<=0;
	if(reset_crt) begin
		frame_ack<=0; reader_valid<=0; read_sequence<=0;
		raster_x<=0; raster_y<=0; pixel_div<=0; stream_faults<=0;
		rgb_out<=0; x_out<=0; y_out<=0;
		hs_out<=0; vs_out<=0; hb_out<=1; vb_out<=1;
	end else if(!reader_valid && request_pending && payload_ready && !fault_sync) begin
		// Start immediately after a complete row, not a complete frame.
		// Source payload stays stable until this acknowledgement returns.
		frame_ack<=request_sync; read_sequence<=first_sequence_local;
		reader_valid<=1; raster_x<=0; raster_y<=0; pixel_div<=0;
	end else begin
		pixel_div<=pixel_div+3'd1;
		if(fault_sync) begin
			if(reader_valid) stream_faults<=stream_faults+32'd1;
			reader_valid<=0;
			// Retire an invalid frame's mailbox so the next source frame can
			// publish a fresh first row. Do not restart from its partial data.
			frame_ack<=request_sync;
		end
		if(pixel_tick) begin
			ce_out<=1; x_out<=raster_x; y_out<=raster_y;
			hs_out<=raster_x>=272 && raster_x<304;
			vs_out<=raster_y==258;
			hb_out<=raster_x>=256 || !reader_valid || fault_sync;
			vb_out<=raster_y>=256 || !reader_valid || fault_sync;
			rgb_out<=reader_valid && !fault_sync && active_pixel && row_ready ? read_rgb : 24'd0;
			if(reader_valid && active_pixel && !fault_sync) begin
				if(!row_ready) begin
					reader_valid<=0; hb_out<=1; vb_out<=1;
					stream_faults<=stream_faults+32'd1;
				end else if(raster_x==255) read_sequence<=read_sequence+16'd1;
			end
			if(raster_x==0 && raster_y==0 && reader_valid && !fault_sync) begin
				// Startup already acknowledged its first row. At later frame
				// starts the new first-row token must identify the next sequence.
				if(request_pending) begin
					if(!payload_ready || first_sequence_local!=read_sequence) begin
						reader_valid<=0; rgb_out<=0; hb_out<=1; vb_out<=1;
						stream_faults<=stream_faults+32'd1;
					end
					frame_ack<=request_sync;
				end
			end
			if(raster_x==335) begin
				raster_x<=0;
				raster_y<=raster_y==261 ? 9'd0 : raster_y+9'd1;
			end else raster_x<=raster_x+9'd1;
		end
	end
end
endmodule
