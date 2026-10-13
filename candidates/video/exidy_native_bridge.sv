// SPDX-License-Identifier: GPL-3.0-or-later
// Video-clock requests drive the board raster, so the FIFO cannot accumulate
// PLL frequency error. Gray pointers qualify stable RGB/timing packets across
// domains; output pixels always occupy exactly eight transport-clock cycles.
module exidy_native_bridge #(
	parameter EXTERNAL_PACKETS=0
) (
	input  wire        clk_sys, clk_video, reset_async,
	input  wire        ce_packet,
	input  wire [23:0] rgb_in,
	input  wire        hs_in, vs_in, hb_in, vb_in,
	input  wire [8:0]  hpos_in, vpos_in,
	output wire        ce_render, ce_video, ce_master,
	output wire [23:0] rgb_out,
	output wire        hs_out, vs_out, hb_out, vb_out,
	output wire [8:0]  hpos_out, vpos_out,
	output wire        fault
);
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg [1:0] reset_sys_pipe=2'b11, reset_video_pipe=2'b11;
	always @(posedge clk_sys or posedge reset_async) begin
		if(reset_async) reset_sys_pipe<=2'b11;
		else reset_sys_pipe<={reset_sys_pipe[0],1'b0};
	end
	always @(posedge clk_video or posedge reset_async) begin
		if(reset_async) reset_video_pipe<=2'b11;
		else reset_video_pipe<={reset_video_pipe[0],1'b0};
	end
	wire reset_sys=reset_sys_pipe[1];
	wire reset_video=reset_video_pipe[1];
	reg [2:0] pixel_div=0;
	reg pixel_request=0;
	reg master_request=0;
	assign ce_video=!reset_video && pixel_div==3'd7;
	always @(posedge clk_video) begin
		if(reset_video) begin pixel_div<=0; pixel_request<=0; master_request<=0; end
		else begin
			pixel_div<=pixel_div+3'd1;
			if(ce_video) pixel_request<=!pixel_request;
			if(pixel_div[1:0]==2'd3) master_request<=!master_request;
		end
	end
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg request_meta=0, request_sync=0;
	reg request_seen=0;
	always @(posedge clk_sys) begin
		if(reset_sys) begin request_meta<=0; request_sync<=0; request_seen<=0; end
		else begin
			request_meta<=pixel_request;
			request_sync<=request_meta;
			request_seen<=request_sync;
		end
	end
	assign ce_render=!reset_sys && (request_sync!=request_seen);
	// The native HSC advances twice per video pixel. Both request streams
	// originate in the fixed video PLL, preserving their exact rate ratio.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg master_meta=0, master_sync=0;
	reg master_seen=0;
	always @(posedge clk_sys) begin
		if(reset_sys) begin master_meta<=0; master_sync<=0; master_seen<=0; end
		else begin
			master_meta<=master_request;
			master_sync<=master_meta;
			master_seen<=master_sync;
		end
	end
	assign ce_master=!reset_sys && (master_sync!=master_seen);
	wire write_packet = EXTERNAL_PACKETS ? ce_packet : ce_render;

	// Eight packets leave several pixel periods for synchronization/prefetch.
	// Explicit logic mapping keeps the tiny asynchronous-read packet store
	// and its held-data CDC constraints independent of RAM address-register inference.
	(* ramstyle="logic" *) reg [45:0] pixels[0:7];
	reg [3:0] write_pointer=0, read_pointer=0;
	reg [3:0] write_gray=0, read_gray=0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg [3:0] read_gray_meta=0, read_gray_sync=0;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg [3:0] write_gray_meta=0, write_gray_sync=0;
	wire [3:0] write_next=write_pointer+4'd1;
	wire [3:0] read_next=read_pointer+4'd1;
	wire [3:0] write_next_gray=(write_next >> 1)^write_next;
	wire [3:0] read_next_gray=(read_next >> 1)^read_next;
	wire full=write_gray=={~read_gray_sync[3:2],read_gray_sync[1:0]};
	wire empty=read_gray==write_gray_sync;
	reg overflow=0, underflow=0, stream_started=0;
	wire [3:0] seen_write_pointer={
		write_gray_sync[3], ^write_gray_sync[3:2],
		^write_gray_sync[3:1], ^write_gray_sync[3:0]};
	wire [3:0] available=seen_write_pointer-read_pointer;
	always @(posedge clk_sys) begin
		if(reset_sys) begin
			write_pointer<=0; write_gray<=0; overflow<=0;
			read_gray_meta<=0; read_gray_sync<=0;
		end else begin
			read_gray_meta<=read_gray;
			read_gray_sync<=read_gray_meta;
			if(write_packet) begin
				if(full) overflow<=1;
				else begin
					pixels[write_pointer[2:0]]<={rgb_in,hs_in,vs_in,hb_in,vb_in,hpos_in,vpos_in};
					write_pointer<=write_next;
					write_gray<=write_next_gray;
				end
			end
		end
	end
	always @(posedge clk_video) begin
		if(reset_video) begin
			read_pointer<=0; read_gray<=0; underflow<=0; stream_started<=0;
			write_gray_meta<=0; write_gray_sync<=0;
		end else begin
			write_gray_meta<=write_gray;
			write_gray_sync<=write_gray_meta;
			if(ce_video) begin
				if(!stream_started) begin
					if(available>=3) stream_started<=1;
				end else if(empty) underflow<=1;
				else begin read_pointer<=read_next; read_gray<=read_next_gray; end
			end
		end
	end
	// The pointer synchronizer settles before reading a packet. The small
	// asynchronous-read store maps to registers, not an ambiguous mixed-clock RAM.
	assign {rgb_out,hs_out,vs_out,hb_out,vb_out,hpos_out,vpos_out}=
		stream_started && !empty ? pixels[read_pointer[2:0]] :
		{24'd0,1'b1,1'b0,1'b1,1'b1,9'd0,9'd0};
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
	reg underflow_meta=0, underflow_sync=0;
	always @(posedge clk_sys) begin
		if(reset_sys) begin underflow_meta<=0; underflow_sync<=0; end
		else begin underflow_meta<=underflow; underflow_sync<=underflow_meta; end
	end
	assign fault=overflow || underflow_sync;
endmodule
