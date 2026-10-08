// Candidate asynchronous FIFO for changed PIA return snapshots. Not selected
// by production QIP. This preserves observed source transitions subject to the
// finite depth; it does not require a firmware read/ack for every snapshot.
module exidyPiaReturnFifo (
	input        audio_clk,
	input        master_clk,
	input        audio_reset_n,
	input        master_reset_n,
	input  [7:0] audio_byte,
	input        audio_notify,
	output wire [7:0] main_byte,
	output wire       main_notify,
	output wire       overflow
);
	wire combined_reset_n = audio_reset_n & master_reset_n;

	// Common assertion, independently synchronized release in each domain.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg audio_reset_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg audio_reset_release;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg master_reset_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg master_reset_release;

	always @(posedge audio_clk or negedge combined_reset_n) begin
		if (!combined_reset_n) begin
			audio_reset_meta <= 1'b0;
			audio_reset_release <= 1'b0;
		end else begin
			audio_reset_meta <= 1'b1;
			audio_reset_release <= audio_reset_meta;
		end
	end

	always @(posedge master_clk or negedge combined_reset_n) begin
		if (!combined_reset_n) begin
			master_reset_meta <= 1'b0;
			master_reset_release <= 1'b0;
		end else begin
			master_reset_meta <= 1'b1;
			master_reset_release <= master_reset_meta;
		end
	end

	reg [8:0] fifo_mem [0:3];
	reg [2:0] write_binary;
	(* preserve, dont_merge *) reg [2:0] write_gray;
	reg [2:0] read_binary;
	(* preserve, dont_merge *) reg [2:0] read_gray;

	// Two-flop Gray-pointer synchronizers. The first stage is explicitly marked
	// for Intel synchronizer identification; the second stage is marked as well.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg [2:0] read_gray_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg [2:0] read_gray_sync;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg [2:0] write_gray_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg [2:0] write_gray_sync;

	reg [8:0] previous_snapshot;
	reg overflow_sticky;
	wire [8:0] source_snapshot = {audio_notify, audio_byte};
	wire fifo_full = write_gray == {~read_gray_sync[2:1], read_gray_sync[0]};
	wire fifo_empty = read_gray == write_gray_sync;
	wire [2:0] write_binary_next = write_binary + 3'd1;
	wire [2:0] write_gray_next = (write_binary_next >> 1) ^ write_binary_next;
	wire [2:0] read_binary_next = read_binary + 3'd1;
	wire [2:0] read_gray_next = (read_binary_next >> 1) ^ read_binary_next;

	always @(posedge audio_clk or negedge audio_reset_release) begin
		if (!audio_reset_release) begin
			read_gray_meta <= 3'b000;
			read_gray_sync <= 3'b000;
			write_binary <= 3'b000;
			write_gray <= 3'b000;
			previous_snapshot <= 9'h000;
			overflow_sticky <= 1'b0;
		end else begin
			read_gray_meta <= read_gray;
			read_gray_sync <= read_gray_meta;
			if (audio_reset_release && source_snapshot != previous_snapshot) begin
				if (!fifo_full) begin
					fifo_mem[write_binary[1:0]] <= source_snapshot;
					write_binary <= write_binary_next;
					write_gray <= write_gray_next;
					previous_snapshot <= source_snapshot;
				end else begin
					// Do not advance previous_snapshot when full: the latest stable
					// value will be retried when a slot becomes visible.
					overflow_sticky <= 1'b1;
				end
			end
		end
	end

	reg [7:0] main_byte_data;
	reg main_notify_data;
	reg pending_notify;
	reg pending_notify_value;
	reg pop_cooldown;

	always @(posedge master_clk or negedge master_reset_release) begin
		if (!master_reset_release) begin
			write_gray_meta <= 3'b000;
			write_gray_sync <= 3'b000;
			read_binary <= 3'b000;
			read_gray <= 3'b000;
			main_byte_data <= 8'h00;
			main_notify_data <= 1'b0;
			pending_notify <= 1'b0;
			pending_notify_value <= 1'b0;
			pop_cooldown <= 1'b0;
		end else begin
			write_gray_meta <= write_gray;
			write_gray_sync <= write_gray_meta;
			if (pending_notify) begin
				main_notify_data <= pending_notify_value;
				pending_notify <= 1'b0;
			end

			if (pop_cooldown) begin
				pop_cooldown <= 1'b0;
			end else if (!fifo_empty) begin
				main_byte_data <= fifo_mem[read_binary[1:0]][7:0];
				pending_notify_value <= fifo_mem[read_binary[1:0]][8];
				pending_notify <= 1'b1;
				read_binary <= read_binary_next;
				read_gray <= read_gray_next;
				pop_cooldown <= 1'b1;
			end
		end
	end

	// Local release clears asynchronously on either input reset. Do not bypass
	// it with a raw audio-reset mask in the master-domain data/notification path.
	assign main_byte = master_reset_release ? main_byte_data : 8'h00;
	assign main_notify = master_reset_release ? main_notify_data : 1'b0;
	assign overflow = overflow_sticky;
endmodule
