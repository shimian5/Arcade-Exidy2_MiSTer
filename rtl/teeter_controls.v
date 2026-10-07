`timescale 1ns/1ps
// Candidate Teeter Torture relative-dial controls and IN0 read adapter.
// This module is intentionally not wired into the production core yet.
module teeterControls #(
    parameter DIAL_REVERSE = 1,
    parameter [7:0] ANALOG_DEADZONE = 8'd8
)(
    input             clk_sys,
    input             reset,
    input             paused,
    input             ce_frame,
    input             dpad_position_mode,
    input      [8:0]  spinner,       // hps_io spinner: [8] toggle, [7:0] signed delta
    input signed [7:0] analog_x,
    input             dpad_left,
    input             dpad_right,
    input             cpu_read_strobe, // pulse when T65 consumes the registered $5101 byte
    input      [7:0]  cpu_read_data,   // byte sampled by T65 from the prior CPU_databus_in register
    input      [7:0]  in0_other,      // existing IN0 input byte; bits 6/2 are replaced
    output     [7:0]  dial_position,  // wrapping target position
    output     [7:0]  dial_consumed,  // saved position advanced once per read
    output     [7:0]  in0_value
);

    localparam signed [8:0] RAMP_STEP = 9'sd16;
    localparam signed [8:0] VEL_MAX   = 9'sd16;
    localparam signed [8:0] POS_MAX   = 9'sd127;

    reg signed [8:0] velocity;
    reg signed [8:0] deflect;
    reg [7:0] accum;
    reg spinner_toggle_d;
    reg [7:0] last_dial;
    reg cpu_read_strobe_d;

    wire signed [8:0] dpad_dir = dpad_right ? 9'sd1 : (dpad_left ? -9'sd1 : 9'sd0);
    wire signed [8:0] analog_ext = $signed({analog_x[7], analog_x});
    wire signed [8:0] analog_mag = analog_x[7] ? -analog_ext : analog_ext;
    wire signed [8:0] analog_contribution = (analog_mag > $signed({1'b0, ANALOG_DEADZONE}))
        ? (analog_ext >>> 3) : 9'sd0;
    wire signed [8:0] dpad_contribution = dpad_position_mode ? (deflect >>> 3) : velocity;

    // MiSTer's spinner delta and frame sources are accumulated into a single
    // modulo-256 position. Reverse defaults on to match MAME PORT_REVERSE.
    wire [7:0] spin_delta = (spinner[8] != spinner_toggle_d) ? spinner[7:0] : 8'h00;
    wire [7:0] frame_delta = ce_frame ? (dpad_contribution[7:0] + analog_contribution[7:0]) : 8'h00;
    wire [7:0] spin_delta_mapped = DIAL_REVERSE ? -spin_delta : spin_delta;
    wire [7:0] frame_delta_mapped = DIAL_REVERSE ? -frame_delta : frame_delta;

    always @(posedge clk_sys) begin
        if (reset) begin
            velocity         <= 9'sd0;
            deflect          <= 9'sd0;
            accum            <= 8'h00;
            spinner_toggle_d <= spinner[8];
        end else begin
            // Always consume a new toggle. Motion received during pause is
            // discarded, so unpausing cannot produce a deferred jump.
            spinner_toggle_d <= spinner[8];
            if (!paused)
                accum <= accum + spin_delta_mapped + frame_delta_mapped;

            if (!paused && ce_frame) begin
                if (dpad_dir > 0)      velocity <= (velocity + RAMP_STEP > VEL_MAX) ? VEL_MAX : velocity + RAMP_STEP;
                else if (dpad_dir < 0) velocity <= (velocity - RAMP_STEP < -VEL_MAX) ? -VEL_MAX : velocity - RAMP_STEP;
                else if (velocity > 0) velocity <= (velocity - RAMP_STEP < 0) ? 9'sd0 : velocity - RAMP_STEP;
                else if (velocity < 0) velocity <= (velocity + RAMP_STEP > 0) ? 9'sd0 : velocity + RAMP_STEP;

                if (dpad_dir > 0)      deflect <= (deflect + RAMP_STEP > POS_MAX) ? POS_MAX : deflect + RAMP_STEP;
                else if (dpad_dir < 0) deflect <= (deflect - RAMP_STEP < -POS_MAX) ? -POS_MAX : deflect - RAMP_STEP;
                else if (deflect > 0)  deflect <= (deflect - RAMP_STEP < 0) ? 9'sd0 : deflect - RAMP_STEP;
                else if (deflect < 0)  deflect <= (deflect + RAMP_STEP > 0) ? 9'sd0 : deflect + RAMP_STEP;
            end
        end
    end

    wire [7:0] dial_delta = accum - last_dial;
    wire dial_moving = (dial_delta != 8'h00);
    wire dial_positive = (dial_delta < 8'h80);
    wire consume_read = cpu_read_strobe & ~cpu_read_strobe_d;

    always @(posedge clk_sys) begin
        if (reset) begin
            last_dial          <= 8'h00;
            cpu_read_strobe_d <= 1'b0;
        end else begin
            cpu_read_strobe_d <= cpu_read_strobe;
            // Commit the exact event byte that T65 sampled from its registered
            // bus input. Do not recompute direction from a possibly newer dial
            // target at PH_1. MAME consumes one count per input read, not tick.
            if (consume_read && cpu_read_data[6])
                last_dial <= cpu_read_data[2] ? (last_dial + 8'd1) : (last_dial - 8'd1);
        end
    end

    assign dial_position = accum;
    assign dial_consumed = last_dial;
    // MAME's callback result bits 4/0 are shifted two places into mask 0x44:
    // event at bit 6, positive/increment direction at bit 2.
    assign in0_value = (in0_other & 8'hbb) | (dial_moving ? 8'h40 : 8'h00) |
                       ((dial_moving && dial_positive) ? 8'h04 : 8'h00);

endmodule
