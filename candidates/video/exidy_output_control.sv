// SPDX-License-Identifier: GPL-3.0-or-later
// Exidy candidate adapted from Victory's output controller. This programs the
// existing pll_cfg M/C/START interface; it never switches clock sources.
// User reset restarts picture warmup but preserves the selected output mode.
module exidy_output_control (
    input wire clk_sys, clk_output,
    input wire management_reset, user_reset,
    input wire native_locked, output_locked, request_crt, native_frame,
    input wire output_frame, cfg_waitrequest,
    output wire cfg_write,
    output wire [5:0] cfg_address,
    output wire [31:0] cfg_writedata,
    output reg selected_crt=0,
    output reg transport_reset=1,
    output wire blank_output
);
localparam [4:0] BOOT_LOCK=0, BLANK_WAIT=1,
    WRITE_M=2, GAP_M=3, WRITE_C=4, GAP_C=5,
    WRITE_START=6, START_BUSY=7, START_DONE=8,
    LOCK_GUARD=9, RELEASE=10, WARMUP=11, IDLE=12;
reg [4:0] state=BOOT_LOCK;
reg [9:0] settle_count=0;
reg target_crt=0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg native_lock_meta=0,native_lock_sync=0,output_lock_meta=0,output_lock_sync=0;
always @(posedge clk_sys) begin
    native_lock_meta<=native_locked; native_lock_sync<=native_lock_meta;
    output_lock_meta<=output_locked; output_lock_sync<=output_lock_meta;
end
wire clocks_ready=native_lock_sync && output_lock_sync;
assign cfg_write=state==WRITE_M || state==WRITE_C || state==WRITE_START;
assign cfg_address=state==WRITE_M ? 6'd4 : state==WRITE_C ? 6'd5 : 6'd2;
// pll_cfg packs divide halves into [7:0]/[15:8], odd duty into bit 17.
// M=128/131; output counter C=32/35; N remains 1 and fractional K is unused.
assign cfg_writedata=state==WRITE_M ? (target_crt ? 32'h00024241 : 32'h00004040) :
    state==WRITE_C ? (target_crt ? 32'h00021211 : 32'h00001010) : 32'd1;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg warm_done_meta=0,warm_done_sync=0;
reg [1:0] warm_frames=0;
always @(posedge clk_sys) begin
    warm_done_meta<=warm_frames==2; warm_done_sync<=warm_done_meta;
    if(management_reset) begin
        state<=BOOT_LOCK; settle_count<=0; target_crt<=0;
        selected_crt<=0; transport_reset<=1;
    end else case(state)
        BOOT_LOCK: if(clocks_ready && !cfg_waitrequest) begin
            target_crt<=request_crt; settle_count<=0; state<=BLANK_WAIT;
            transport_reset<=1;
        end
        BLANK_WAIT: if(settle_count==63) begin settle_count<=0;state<=WRITE_M;end
            else settle_count<=settle_count+10'd1;
        // pll_cfg does not promise waitrequest pulses for M/C staging writes.
        // Allow its internal DPRIO write sequencer to finish before next word.
        WRITE_M: if(!cfg_waitrequest) begin settle_count<=0;state<=GAP_M;end
        GAP_M: if(settle_count==255) begin settle_count<=0;state<=WRITE_C;end
            else settle_count<=settle_count+10'd1;
        WRITE_C: if(!cfg_waitrequest) begin settle_count<=0;state<=GAP_C;end
        GAP_C: if(settle_count==255) begin settle_count<=0;state<=WRITE_START;end
            else settle_count<=settle_count+10'd1;
        WRITE_START: if(!cfg_waitrequest) state<=START_BUSY;
        START_BUSY: if(cfg_waitrequest) state<=START_DONE;
        START_DONE: if(!cfg_waitrequest && clocks_ready) begin
            settle_count<=0;state<=LOCK_GUARD;
        end
        LOCK_GUARD: if(!clocks_ready || cfg_waitrequest) settle_count<=0;
            else if(settle_count==1023) begin
                selected_crt<=target_crt;settle_count<=0;state<=RELEASE;
            end else settle_count<=settle_count+10'd1;
        RELEASE: if(!clocks_ready || cfg_waitrequest) begin state<=LOCK_GUARD;settle_count<=0;end
            else if(settle_count==63) begin transport_reset<=0;state<=WARMUP;end
            else settle_count<=settle_count+10'd1;
        WARMUP: if(!clocks_ready) begin transport_reset<=1;settle_count<=0;state<=LOCK_GUARD;end
            else if(!user_reset && warm_done_sync) state<=IDLE;
        IDLE: if(!clocks_ready) begin transport_reset<=1;settle_count<=0;state<=LOCK_GUARD;end
            else if(!user_reset && native_frame && request_crt!=selected_crt) begin
                target_crt<=request_crt;transport_reset<=1;settle_count<=0;state<=BLANK_WAIT;
            end
        default: begin state<=BOOT_LOCK;transport_reset<=1;settle_count<=0;end
    endcase
end
wire pipeline_hold=transport_reset || user_reset || !output_locked;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *)
reg [1:0] warm_reset_pipe=2'b11;
always @(posedge clk_output or posedge pipeline_hold)
    if(pipeline_hold) warm_reset_pipe<=2'b11;
    else warm_reset_pipe<={warm_reset_pipe[0],1'b0};
always @(posedge clk_output)
    if(warm_reset_pipe[1]) warm_frames<=0;
    else if(output_frame && warm_frames<2) warm_frames<=warm_frames+2'd1;
assign blank_output=warm_reset_pipe[1] || warm_frames!=2;
endmodule
