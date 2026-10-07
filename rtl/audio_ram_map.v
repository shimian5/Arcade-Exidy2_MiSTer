// Audio-CPU RAM address for the CPU-based sound boards (Venture family, Mouse
// Trap). MAME maps one 128-byte 6532 RAM at 0x0000-0x007F mirrored through
// 0x07FF, and the firmware relies on the aliases (zero page, stack page,
// polled flags such as Mouse Trap's 0x0178). The 2 KB RAM is therefore
// addressed with the low seven bits only.
module exidyAudioRamAddr (
	input  [15:0] cpu_addr,
	output [10:0] ram_addr
);
	assign ram_addr = {4'b0000, cpu_addr[6:0]};
endmodule
