// Isolated Side Trak character PROM and palette candidate.
// Not connected to the production Exidy2 core.
module exidySideTrakCharRom (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [7:0]  profile,
    input  logic        load_begin,
    input  logic        load_write,
    input  logic [9:0]  load_addr,
    input  logic [7:0]  load_data,
    input  logic        load_end,
    input  logic        read_request,
    input  logic [7:0]  char_code,
    input  logic [2:0]  char_row,
    input  logic [2:0]  pixel_x,
    output logic        image_ready,
    output logic        load_fault,
    output logic        read_valid,
    output logic [7:0]  read_data,
    output logic        pixel_on,
    output logic [2:0]  pixel_pen,
    output logic [2:0]  pixel_rgb
);
    logic [7:0] char_rom [0:1023];
    logic load_active;
    logic [10:0] received_count;
    logic [7:0] read_char_code;
    logic [2:0] read_pixel_x;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            load_active    <= 1'b0;
            received_count <= 11'd0;
            image_ready    <= 1'b0;
            load_fault     <= 1'b0;
            read_valid     <= 1'b0;
            read_data      <= 8'd0;
            read_char_code <= 8'd0;
            read_pixel_x   <= 3'd0;
        end else begin
            read_valid <= 1'b0;
            if (load_begin) begin
                load_active    <= 1'b1;
                received_count <= 11'd0;
                image_ready    <= 1'b0;
                load_fault     <= 1'b0;
            end else begin
                if (load_write) begin
                    if (load_active && !load_fault && received_count < 11'd1024 &&
                        load_addr == received_count[9:0]) begin
                        char_rom[load_addr] <= load_data;
                        received_count <= received_count + 11'd1;
                    end else begin
                        load_fault  <= 1'b1;
                        image_ready <= 1'b0;
                    end
                end
                if (load_end) begin
                    load_active <= 1'b0;
                    image_ready <= load_active && !load_fault && !load_write &&
                                   received_count == 11'd1024;
                    if (!load_active || load_fault || load_write || received_count != 11'd1024)
                        load_fault <= 1'b1;
                end
            end

            if (read_request && image_ready && !load_active && profile == 8'h00 &&
                !load_begin && !load_write && !load_end) begin
                // The archive carries 128 8x8 glyphs. MAME's 0x800-byte
                // mapped character window has zero-filled bytes 0x400-0x7ff.
                read_data <= char_code[7] ? 8'h00 : char_rom[{char_code[6:0], char_row}];
                read_char_code <= char_code;
                read_pixel_x <= pixel_x;
                read_valid <= 1'b1;
            end
        end
    end

    always_comb begin
        pixel_on = read_data[3'd7 - read_pixel_x];
        pixel_pen = pixel_on ? (3'd4 + read_char_code[7:6]) : 3'd0;
    end

    sideTrakPalette palette(.pen(pixel_pen), .rgb(pixel_rgb));
endmodule

module sideTrakPalette (
    input  logic [2:0] pen,
    output logic [2:0] rgb
);
    // Component order is {red,green,blue}; directly derived from the pinned
    // MAME init_sidetrac() latch values and set_1_color() bit selection.
    always_comb begin
        case (pen)
            3'd0: rgb = 3'b000;
            3'd1: rgb = 3'b111;
            3'd2: rgb = 3'b000;
            3'd3: rgb = 3'b110;
            3'd4: rgb = 3'b111;
            3'd5: rgb = 3'b111;
            3'd6: rgb = 3'b010;
            3'd7: rgb = 3'b000;
        endcase
    end
endmodule
