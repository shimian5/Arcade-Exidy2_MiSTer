`timescale 1ns/1ps
// Mouse Trap speech subsystem. All logic is synchronous to clk. Production
// binding and dependencies are managed by the project integration files.
module mousetrapSpeechSubsystem #(
    parameter integer CLK_HZ = 14366883
) (
    input wire clk,
    input wire state_reset_n,
    input wire decoder_reset_n,
    input wire global_reset,
    input wire pause,
    input wire speech_enable,
    input wire image_ready,
    input wire command_commit,
    input wire [7:0] command_data,
    output wire rom_read,
    output wire [13:0] rom_addr,
    input wire rom_ready,
    input wire [7:0] rom_data,
    input wire signed [15:0] audio_base,
    output wire signed [15:0] mono,
    output wire busyPB0,
    output wire overflow
);
    // The speech processor runs at half the 3.579545 MHz board crystal.
    // Fractional phase accumulation avoids assuming an exact integer divider.
    localparam integer SAMPLE_HZ = 192000;
    localparam integer CPU_PHASE_W = $clog2(2 * CLK_HZ);
    localparam integer RC_PHASE_W = $clog2(64'd1000 * CLK_HZ);
    localparam integer SAMPLE_PHASE_W = $clog2(CLK_HZ);
    reg [CPU_PHASE_W-1:0] cpu_phase;
    reg [RC_PHASE_W-1:0] rc_phase;
    reg [SAMPLE_PHASE_W-1:0] sample_phase;
    reg cvsd_clock_state;
    wire cpu_ce;
    wire rc_toggle;
    wire sample_ce;
    wire cpu_reset;

    // Phase storage is sized to the corresponding threshold; the extra sum
    // bit carries a threshold crossing without building 64-bit adders.
    localparam [CPU_PHASE_W:0] CPU_RATE_X2 = 3579545;
    localparam [RC_PHASE_W:0] RC_RATE_MILLI = 30939140;
    localparam [SAMPLE_PHASE_W:0] SAMPLE_RATE = SAMPLE_HZ;
    localparam [CPU_PHASE_W:0] CLK_RATE_X2 = 2 * CLK_HZ;
    localparam [RC_PHASE_W:0] RC_CLOCK_RATE_MILLI = 64'd1000 * CLK_HZ;
    localparam [SAMPLE_PHASE_W:0] SAMPLE_CLOCK_RATE = CLK_HZ;

    // Twice the master clock threshold gives half-Hz resolution for Z80.
    wire [CPU_PHASE_W:0] cpu_sum = {1'b0,cpu_phase} + CPU_RATE_X2;
    wire [RC_PHASE_W:0] rc_sum = {1'b0,rc_phase} + RC_RATE_MILLI;
    wire [SAMPLE_PHASE_W:0] sample_sum = {1'b0,sample_phase} + SAMPLE_RATE;
    assign cpu_ce = !pause && (cpu_sum >= CLK_RATE_X2);
    assign rc_toggle = !pause && (rc_sum >= RC_CLOCK_RATE_MILLI);
    assign sample_ce = !pause && (sample_sum >= SAMPLE_CLOCK_RATE);

    always @(posedge clk or negedge state_reset_n) begin
        if (!state_reset_n) begin
            cpu_phase <= 0;
            rc_phase <= 0;
            sample_phase <= 0;
            cvsd_clock_state <= 0;
        end else if (!pause) begin
            cpu_phase <= cpu_ce ? cpu_sum - CLK_RATE_X2 : cpu_sum;
            rc_phase <= rc_toggle ? rc_sum - RC_CLOCK_RATE_MILLI : rc_sum;
            sample_phase <= sample_ce ? sample_sum - SAMPLE_CLOCK_RATE : sample_sum;
            if (rc_toggle) cvsd_clock_state <= ~cvsd_clock_state;
        end
    end

    wire [15:0] cpu_addr;
    wire [7:0] cpu_data_out;
    wire cpu_m1, cpu_mem_rd, cpu_mem_wr, cpu_io_rd, cpu_io_wr, cpu_intack;
    wire cpu_wait_n;
    wire [7:0] speech_io_data;
    wire [7:0] cvsd_command;
    wire cvsd_decoder_reset_n;
    wire cvsd_digit;
    wire riot_pb0_in;
    wire [7:0] adapter_data;

    mousetrapVoiceIo voice_io (
        .clk(clk),
        .state_reset_n(state_reset_n),
        .decoder_reset_n(decoder_reset_n),
        .z80_global_reset(global_reset || !speech_enable || !image_ready),
        .io_addr(cpu_addr[7:0]),
        .io_data_in(cpu_data_out),
        .io_wr(cpu_io_wr),
        .cvsd_clock_state(cvsd_clock_state),
        .io_data_out(speech_io_data),
        .riot_pa_write_commit(command_commit),
        .riot_pa_write_data(command_data),
        .cvsd_data(cvsd_command),
        .z80_reset(cpu_reset),
        .cvsd_decoder_reset_n(cvsd_decoder_reset_n),
        .cvsd_digit(cvsd_digit),
        .riot_pb0_in(riot_pb0_in)
    );
    assign busyPB0 = riot_pb0_in;

    speechRomBus rom_bus (
        .clk(clk),
        .reset(cpu_reset),
        .cpu_addr(cpu_addr),
        .mem_rd(cpu_mem_rd),
        .io_rd(cpu_io_rd),
        .rom_ready(rom_ready),
        .rom_data(rom_data),
        .rom_read(rom_read),
        .rom_addr(rom_addr),
        .wait_n(cpu_wait_n),
        .cpu_data(adapter_data)
    );

    // Keep the T80 interrupt acknowledge vector ahead of normal memory data.
    Z80 cpu (
        .clk(clk), .clk_en(cpu_ce), .reset(cpu_reset),
        .addr(cpu_addr),
        .datai(cpu_intack ? 8'hff : cpu_io_rd ? speech_io_data : adapter_data),
        .datao(cpu_data_out), .m1(cpu_m1), .mem_rd(cpu_mem_rd),
        .mem_wr(cpu_mem_wr), .io_rd(cpu_io_rd), .io_wr(cpu_io_wr),
        .wait_n(cpu_wait_n), .busrq_n(1'b1), .intreq(1'b0),
        .intvec(8'hff), .intack(cpu_intack), .nmi(1'b0)
    );

    wire signed [31:0] decoder_sample_q24;
    wire [2:0] decoder_history;
    wire [31:0] decoder_step_q24;
    wire signed [31:0] decoder_integrator_q24;
    reg cvsd_clock_d;
    reg decoder_event_d;
    reg sample_ce_d;
    wire decoder_clock_transition = cvsd_clock_state ^ cvsd_clock_d;
    always @(posedge clk or negedge state_reset_n) begin
        if (!state_reset_n) begin
            cvsd_clock_d <= 1'b0;
            decoder_event_d <= 1'b0;
            sample_ce_d <= 1'b0;
        end else begin
            cvsd_clock_d <= cvsd_clock_state;
            // Retiming lets the decoder's registered endpoint settle before
            // the renderer consumes it on the following audio-clock edge.
            decoder_event_d <= decoder_clock_transition && !cvsd_clock_state;
            sample_ce_d <= sample_ce;
        end
    end

    exidyMc3417 #(.SAMPLE_ON_RISING(1'b0)) decoder (
        .clk(clk), .cold_reset_n(state_reset_n),
        .clock_reset(!cvsd_decoder_reset_n), .cvsd_clock(cvsd_clock_state),
        .digit(cvsd_digit), .sample_q24(decoder_sample_q24),
        .history(decoder_history), .step_q24(decoder_step_q24),
        .integrator_q24(decoder_integrator_q24)
    );

    wire signed [31:0] stream_q24;
    wire stream_idle;
    exidyMc3417Stream renderer (
        .clk(clk), .cold_reset_n(state_reset_n),
        .sample_ce(sample_ce), .clock_transition(decoder_clock_transition),
        .sample_valid(decoder_event_d), .sample_q24(decoder_sample_q24),
        .pcm_q24(stream_q24), .idle(stream_idle)
    );

    wire signed [31:0] filtered_q24;
    wire signed [15:0] speech_pcm;
    wire signed [15:0] filtered_mono;
    wire pcm_valid, filter_overrun, clipped;
    exidyMc3417Filter filter_mix (
        .clk(clk), .cold_reset_n(state_reset_n), .sample_ce(sample_ce_d),
        .sample_q24(stream_q24), .audio_base(audio_base),
        .mute(pause),
        .filtered_q24(filtered_q24), .pcm(speech_pcm),
        .pcm_valid(pcm_valid), .overrun(filter_overrun),
        .mono(filtered_mono), .clipped(clipped)
    );
    // A disabled or unavailable speech block contributes no signal while
    // the existing base audio continues unchanged.
    assign mono = pause ? 16'sd0 :
                  (!speech_enable || !image_ready) ? audio_base : filtered_mono;
    assign overflow = speech_enable && image_ready && (filter_overrun || clipped);
endmodule
