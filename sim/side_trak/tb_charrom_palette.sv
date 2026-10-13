module tb_charrom_palette;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic reset_n;
    logic [7:0] profile;
    logic load_begin, load_write, load_end;
    logic [9:0] load_addr;
    logic [7:0] load_data;
    logic read_request;
    logic [7:0] char_code;
    logic [2:0] char_row, pixel_x;
    logic image_ready, load_fault, read_valid;
    logic [7:0] read_data;
    logic pixel_on;
    logic [2:0] pixel_pen, pixel_rgb;
    logic [2:0] palette_pen, palette_rgb;
    integer rom_file, vector_file, palette_file, rc;
    integer i, code_i, row_i, x_i, byte_i, on_i, pen_i, rgb_i;
    integer cases, reload_byte, reload_on;
    reg [8*1024-1:0] rom_path, vector_path, palette_path;
    reg [7:0] rom_image [0:1023];

    exidySideTrakCharRom dut(
        .clk(clk), .reset_n(reset_n), .profile(profile),
        .load_begin(load_begin), .load_write(load_write), .load_addr(load_addr),
        .load_data(load_data), .load_end(load_end),
        .read_request(read_request), .char_code(char_code), .char_row(char_row), .pixel_x(pixel_x),
        .image_ready(image_ready), .load_fault(load_fault), .read_valid(read_valid), .read_data(read_data),
        .pixel_on(pixel_on), .pixel_pen(pixel_pen), .pixel_rgb(pixel_rgb)
    );
    sideTrakPalette palette_check(.pen(palette_pen), .rgb(palette_rgb));

    task automatic expect_no_read;
        begin
            @(posedge clk); #1;
            if (read_valid) $fatal(1, "unexpected read_valid while request is blocked");
        end
    endtask

    task automatic query_pixel(input integer c, input integer r, input integer x,
                               input integer exp_byte, input integer exp_on,
                               input integer exp_pen, input integer exp_rgb);
        begin
            @(negedge clk);
            read_request = 1'b0;
            @(posedge clk); #1;
            if (read_valid) $fatal(1, "read_valid did not clear after one cycle");
            @(negedge clk);
            char_code = c[7:0]; char_row = r[2:0]; pixel_x = x[2:0]; read_request = 1'b1;
            if (read_valid) $fatal(1, "read_valid asserted before synchronous read edge");
            @(posedge clk); #1;
            if (!read_valid) $fatal(1, "missing one-cycle character response c=%0d r=%0d x=%0d", c, r, x);
            if (read_data !== exp_byte[7:0] || pixel_on !== exp_on[0] ||
                pixel_pen !== exp_pen[2:0] || pixel_rgb !== exp_rgb[2:0]) begin
                $display("glyph mismatch c=%02x r=%0d x=%0d byte=%02x/%02x on=%0d/%0d pen=%0d/%0d rgb=%03b/%03b",
                         c, r, x, read_data, exp_byte[7:0], pixel_on, exp_on[0],
                         pixel_pen, exp_pen[2:0], pixel_rgb, exp_rgb[2:0]);
                $fatal(1, "MAME-derived glyph/palette mismatch");
            end
            cases = cases + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("ROM=%s", rom_path) || !$value$plusargs("VECTORS=%s", vector_path) ||
            !$value$plusargs("PALETTE=%s", palette_path)) $fatal(1, "ROM/VECTORS/PALETTE plusargs required");
        $readmemh(rom_path, rom_image);
        reset_n = 1'b0; profile = 8'h00;
        load_begin = 0; load_write = 0; load_end = 0; load_addr = 0; load_data = 0;
        read_request = 0; char_code = 0; char_row = 0; pixel_x = 0;
        palette_pen = 0; cases = 0;
        repeat (2) @(posedge clk);
        #1;
        if (image_ready || read_valid) $fatal(1, "reset must quarantine character reads");
        reset_n = 1'b1;

        // No data is visible before a full, ordered 1KiB archive load.
        @(negedge clk); read_request = 1; char_code = 0; char_row = 0; pixel_x = 0;
        expect_no_read();
        @(negedge clk); read_request = 0; load_begin = 1;
        @(negedge clk); load_begin = 0; load_write = 1;
        for (i = 0; i < 1024; i = i + 1) begin
            load_addr = i[9:0]; load_data = rom_image[i];
            @(negedge clk);
        end
        load_write = 0; load_end = 1;
        @(negedge clk); load_end = 0;
        @(posedge clk); #1;
        if (!image_ready || load_fault) $fatal(1, "valid ordered 1KiB load was not accepted");

        vector_file = $fopen(vector_path, "r");
        if (vector_file == 0) $fatal(1, "cannot open glyph vector file");
        while (!$feof(vector_file)) begin
            rc = $fscanf(vector_file, "%h %h %h %h %h %h %h\n",
                         code_i, row_i, x_i, byte_i, on_i, pen_i, rgb_i);
            if (rc == 7) begin
                query_pixel(code_i, row_i, x_i, byte_i, on_i, pen_i, rgb_i);
            end else if (rc != -1) begin
                $fatal(1, "malformed glyph vector row rc=%0d", rc);
            end
        end
        $fclose(vector_file);
        if (cases != 16384) $fatal(1, "expected 256*8*8=16384 pixel cases, got %0d", cases);

        // Independently check all eight indexed MAME palette pens.
        palette_file = $fopen(palette_path, "r");
        if (palette_file == 0) $fatal(1, "cannot open palette vectors");
        i = 0;
        while (!$feof(palette_file)) begin
            rc = $fscanf(palette_file, "%h %h\n", pen_i, rgb_i);
            if (rc == 2) begin
                palette_pen = pen_i[2:0]; #1;
                if (palette_rgb !== rgb_i[2:0]) $fatal(1, "palette pen %0d got %03b expected %03b", pen_i, palette_rgb, rgb_i[2:0]);
                i = i + 1;
            end else if (rc != -1) $fatal(1, "malformed palette vector row");
        end
        $fclose(palette_file);
        if (i != 8) $fatal(1, "expected eight palette pen checks, got %0d", i);

        // The candidate stays profile-gated while the loaded bytes remain valid.
        profile = 8'h01;
        @(negedge clk); read_request = 1;
        expect_no_read();
        @(negedge clk); read_request = 0; profile = 8'h00;

        // Reset invalidates ready state; stale RAM cannot be read until reloaded.
        reset_n = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (image_ready || read_valid) $fatal(1, "reset left stale character image visible");
        reset_n = 1'b1;

        // A non-contiguous write faults and does not expose partial contents.
        @(negedge clk); load_begin = 1;
        @(negedge clk); load_begin = 0; load_write = 1; load_addr = 10'd1; load_data = rom_image[1];
        @(negedge clk); load_write = 0; load_end = 1;
        @(negedge clk); load_end = 0;
        @(posedge clk); #1;
        if (image_ready || !load_fault) $fatal(1, "out-of-order load was not rejected");

        // A full new generation recovers from reset/fault and preserves deterministic data.
        @(negedge clk); load_begin = 1;
        @(negedge clk); load_begin = 0; load_write = 1;
        for (i = 0; i < 1024; i = i + 1) begin
            load_addr = i[9:0]; load_data = rom_image[i];
            @(negedge clk);
        end
        load_write = 0; load_end = 1;
        @(negedge clk); load_end = 0;
        @(posedge clk); #1;
        if (!image_ready || load_fault) $fatal(1, "full reload did not recover character image");
        reload_byte = {24'b0, rom_image[0]};
        reload_on = {31'b0, rom_image[0][7]};
        query_pixel(0, 0, 0, reload_byte, reload_on, (reload_on != 0) ? 4 : 0, (reload_on != 0) ? 7 : 0);
        $display("PASS: 16384 exhaustive glyph pixels plus reload sample, eight palette pens, ordered load/read latency, reset/reload and invalid-profile/fault controls");
        $finish;
    end
endmodule
