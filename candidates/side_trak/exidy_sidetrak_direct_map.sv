// Isolated Side Trak decode candidate derived from pinned MAME sidetrac_map.
// Not connected to Exidy2 production RTL. profile==8'h00 is only a proposal.
module exidySideTrakDirectMap (
    input  logic [7:0]  profile,
    input  logic [15:0] cpu_addr,
    input  logic        cpu_read,
    input  logic        cpu_write,
    output logic [18:0] select,
    output logic [15:0] program_rom_addr,
    output logic [7:0]  interrupt_fixed_bits
);
    localparam integer S_PROGRAM_ROM = 0;
    localparam integer S_CHARACTER_ROM = 1;
    localparam integer S_WORK_RAM_READ = 2;
    localparam integer S_WORK_RAM_WRITE = 3;
    localparam integer S_VIDEO_RAM_READ = 4;
    localparam integer S_VIDEO_RAM_WRITE = 5;
    localparam integer S_DIP_READ = 6;
    localparam integer S_IN0_READ = 7;
    localparam integer S_IRQ_READ = 8;
    localparam integer S_IN2_READ = 9;
    localparam integer S_SPRITE1_X_WRITE = 10;
    localparam integer S_SPRITE1_Y_WRITE = 11;
    localparam integer S_SPRITE2_X_WRITE = 12;
    localparam integer S_SPRITE2_Y_WRITE = 13;
    localparam integer S_SPRITE_NUMBER_WRITE = 14;
    localparam integer S_SPRITE_ENABLE_WRITE = 15;
    localparam integer S_COLOR_LATCH_WRITE = 16;
    localparam integer S_AUDIO0_WRITE = 17;
    localparam integer S_AUDIO1_WRITE = 18;

    always_comb begin
        select = 19'b0;
        program_rom_addr = 16'b0;
        // Side Trak has no collision mask. MAME's fixed INTSOURCE bits yield
        // 0x63 in the retained live status-read capture.
        interrupt_fixed_bits = 8'h63;

        if (profile == 8'h00) begin
            if (cpu_read && ((cpu_addr >= 16'h0800 && cpu_addr <= 16'h3fff) ||
                             (cpu_addr >= 16'hff00))) begin
                select[S_PROGRAM_ROM] = 1'b1;
                program_rom_addr = (cpu_addr >= 16'hff00) ?
                                   {8'h3f, cpu_addr[7:0]} : cpu_addr;
            end

            if (cpu_read && cpu_addr >= 16'h4800 && cpu_addr <= 16'h4fff) begin
                select[S_CHARACTER_ROM] = 1'b1;
                program_rom_addr = cpu_addr;
            end

            if (cpu_addr <= 16'h03ff) begin
                select[S_WORK_RAM_READ] = cpu_read;
                select[S_WORK_RAM_WRITE] = cpu_write;
            end

            // MAME map(4000,43ff).mirror(0400).ram().
            if (cpu_addr >= 16'h4000 && cpu_addr <= 16'h47ff) begin
                select[S_VIDEO_RAM_READ] = cpu_read;
                select[S_VIDEO_RAM_WRITE] = cpu_write;
            end

            // The 0x00fc mirror ignores address bits 2..7 but preserves A[1:0].
            if (cpu_addr >= 16'h5100 && cpu_addr <= 16'h51ff) begin
                case (cpu_addr[1:0])
                    2'b00: begin
                        select[S_DIP_READ] = cpu_read;
                        select[S_SPRITE_NUMBER_WRITE] = cpu_write;
                    end
                    2'b01: begin
                        select[S_IN0_READ] = cpu_read;
                        select[S_SPRITE_ENABLE_WRITE] = cpu_write;
                    end
                    2'b11: select[S_IRQ_READ] = cpu_read;
                    default: begin end
                endcase
            end

            // Four independently mirrored sprite-position registers.
            if (cpu_write) begin
                if (cpu_addr >= 16'h5000 && cpu_addr <= 16'h503f) select[S_SPRITE1_X_WRITE] = 1'b1;
                if (cpu_addr >= 16'h5040 && cpu_addr <= 16'h507f) select[S_SPRITE1_Y_WRITE] = 1'b1;
                if (cpu_addr >= 16'h5080 && cpu_addr <= 16'h50bf) select[S_SPRITE2_X_WRITE] = 1'b1;
                if (cpu_addr >= 16'h50c0 && cpu_addr <= 16'h50ff) select[S_SPRITE2_Y_WRITE] = 1'b1;
            end

            if (cpu_write && cpu_addr >= 16'h5210 && cpu_addr <= 16'h5212)
                select[S_COLOR_LATCH_WRITE] = 1'b1;
            if (cpu_read && cpu_addr == 16'h5213)
                select[S_IN2_READ] = 1'b1;
            if (cpu_write && cpu_addr == 16'h5200)
                select[S_AUDIO0_WRITE] = 1'b1;
            if (cpu_write && cpu_addr == 16'h5201)
                select[S_AUDIO1_WRITE] = 1'b1;
        end
    end
endmodule
