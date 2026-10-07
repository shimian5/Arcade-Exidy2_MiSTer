// Isolated candidate for phase testing only; production rtl/pia_return.v is unchanged.
module exidyPiaReturnNegedgeCandidate (
    input  wire       audio_clk,
    input  wire       master_clk,
    input  wire       audio_reset_n,
    input  wire       master_reset_n,
    input  wire [7:0] audio_byte,
    output wire [7:0] main_byte
);
    reg [7:0] audio_byte_stage;
    reg [7:0] main_byte_data;
    reg main_byte_valid;

    always @(posedge audio_clk) begin
        if (!audio_reset_n)
            audio_byte_stage <= 8'h00;
        else
            audio_byte_stage <= audio_byte;
    end

    // Candidate moves only the full-byte destination capture to the opposite
    // master edge. Validity releases on that same edge to avoid exposing a
    // retained byte before the new phase capture has occurred.
    always @(negedge master_clk) begin
        main_byte_data <= audio_byte_stage;
    end

    always @(negedge master_clk or negedge master_reset_n) begin
        if (!master_reset_n)
            main_byte_valid <= 1'b0;
        else
            main_byte_valid <= 1'b1;
    end

    assign main_byte = main_byte_valid ? main_byte_data : 8'h00;
endmodule

// Negative control: data capture moves to the falling edge but validity keeps
// the production rising-edge behavior. The bench proves this leaks the retained
// pre-reset byte at the first rising edge after reset release.
module exidyPiaReturnNegedgeDataOnlyControl (
    input  wire       audio_clk,
    input  wire       master_clk,
    input  wire       audio_reset_n,
    input  wire       master_reset_n,
    input  wire [7:0] audio_byte,
    output wire [7:0] main_byte
);
    reg [7:0] audio_byte_stage;
    reg [7:0] main_byte_data;
    reg main_byte_valid;

    always @(posedge audio_clk) begin
        if (!audio_reset_n) audio_byte_stage <= 8'h00;
        else audio_byte_stage <= audio_byte;
    end
    always @(negedge master_clk)
        main_byte_data <= audio_byte_stage;
    always @(posedge master_clk or negedge master_reset_n) begin
        if (!master_reset_n) main_byte_valid <= 1'b0;
        else main_byte_valid <= 1'b1;
    end
    assign main_byte = main_byte_valid ? main_byte_data : 8'h00;
endmodule
