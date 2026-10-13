module tb_direct_map;
    logic [7:0] profile;
    logic [15:0] cpu_addr;
    logic cpu_read, cpu_write;
    logic [18:0] select;
    logic [15:0] program_rom_addr;
    logic [7:0] interrupt_fixed_bits;
    integer fd, rc, cases, exp_mask, exp_rom_addr;
    integer addr_i, read_i, write_i;
    reg [8*1024-1:0] vectors_path;

    exidySideTrakDirectMap dut(.*);

    initial begin
        if (!$value$plusargs("VECTORS=%s", vectors_path)) $fatal(1, "missing +VECTORS=<path>");
        fd = $fopen(vectors_path, "r");
        if (fd == 0) $fatal(1, "cannot open vector file");
        profile = 8'h00;
        cases = 0;
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %d %d %h %h\n", addr_i, read_i, write_i, exp_mask, exp_rom_addr);
            if (rc == 5) begin
                cpu_addr = addr_i[15:0];
                cpu_read = read_i[0];
                cpu_write = write_i[0];
                #1;
                if (select !== exp_mask[18:0] || program_rom_addr !== exp_rom_addr[15:0]) begin
                    $display("MISMATCH addr=%04x read=%0d write=%0d select=%05x expected=%05x rom=%04x expected_rom=%04x",
                             cpu_addr, cpu_read, cpu_write, select, exp_mask[18:0], program_rom_addr, exp_rom_addr[15:0]);
                    $fatal(1, "MAME direct-map oracle mismatch");
                end
                if (interrupt_fixed_bits !== 8'h63) $fatal(1, "Side Trak fixed status source bits changed");
                cases = cases + 1;
            end else if (rc != -1) begin
                $fatal(1, "malformed oracle row rc=%0d", rc);
            end
        end
        $fclose(fd);
        if (cases != 131072) $fatal(1, "expected 131072 exhaustive read/write cases, got %0d", cases);

        // The proposed profile byte is exact-match gated; nearby legacy profiles
        // must not acquire the Side Trak map accidentally.
        profile = 8'h01;
        cpu_addr = 16'hffff;
        cpu_read = 1'b1;
        cpu_write = 1'b0;
        #1;
        if (select !== 19'b0 || program_rom_addr !== 16'b0) $fatal(1, "profile 01 leaked Side Trak selects");
        profile = 8'h80;
        cpu_addr = 16'h5101;
        cpu_read = 1'b1;
        cpu_write = 1'b1;
        #1;
        if (select !== 19'b0 || program_rom_addr !== 16'b0) $fatal(1, "extended marker leaked Side Trak selects");

        $display("PASS: %0d exhaustive MAME-derived read/write cases, vector alias and profile negative controls", cases);
        $finish;
    end
endmodule
