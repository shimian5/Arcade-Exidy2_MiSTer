// Candidate bundled-data PIA return mailbox. Not selected by production QIP.
// The source byte/notify bundle is captured once while idle and remains stable
// until the synchronized destination acknowledgment returns.
module exidyPiaReturnMailbox (
	input        audio_clk,
	input        master_clk,
	input        audio_reset_n,
	input        master_reset_n,
	input  [7:0] audio_byte,
	input        audio_notify,
	output wire [7:0] main_byte,
	output wire       main_notify
);
	wire combined_reset_n = audio_reset_n & master_reset_n;

	// Independent async-assert/sync-release chains for each clock domain.
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

	// Source mailbox. Each synchronizer's first stage is explicitly identified;
	// the held nine-bit bundle is intentionally not independently synchronized.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg ack_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg ack_sync;
	reg acknowledge_toggle;
	reg [7:0] held_byte;
	reg held_notify;
	reg [8:0] previous_snapshot;
	reg request_toggle;
	wire [8:0] source_snapshot = {audio_notify, audio_byte};

	always @(posedge audio_clk or negedge combined_reset_n) begin
		if (!combined_reset_n) begin
			ack_meta <= 1'b0;
			ack_sync <= 1'b0;
			held_byte <= 8'h00;
			held_notify <= 1'b0;
			previous_snapshot <= 9'h000;
			request_toggle <= 1'b0;
		end else begin
			ack_meta <= acknowledge_toggle;
			ack_sync <= ack_meta;
			if (audio_reset_release && request_toggle == ack_sync &&
			    source_snapshot != previous_snapshot) begin
				held_notify <= audio_notify;
				held_byte <= audio_byte;
				previous_snapshot <= source_snapshot;
				request_toggle <= ~request_toggle;
			end
		end
	end

	// Destination mailbox. The byte captures on the synchronized request edge;
	// notification is intentionally delivered on the following master edge.
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg request_meta;
	(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg request_sync;
	reg [7:0] main_byte_data;
	reg main_notify_data;
	reg pending_notify;
	reg pending_notify_value;

	always @(posedge master_clk or negedge combined_reset_n) begin
		if (!combined_reset_n) begin
			request_meta <= 1'b0;
			request_sync <= 1'b0;
			acknowledge_toggle <= 1'b0;
			main_byte_data <= 8'h00;
			main_notify_data <= 1'b0;
			pending_notify <= 1'b0;
			pending_notify_value <= 1'b0;
		end else begin
			request_meta <= request_toggle;
			request_sync <= request_meta;
			if (!master_reset_release) begin
				// Keep state/output quiescent until this domain's reset has released.
				main_byte_data <= 8'h00;
				main_notify_data <= 1'b0;
				pending_notify <= 1'b0;
				pending_notify_value <= 1'b0;
			end else if (request_sync != acknowledge_toggle) begin
				main_byte_data <= held_byte;
				pending_notify_value <= held_notify;
				pending_notify <= 1'b1;
				acknowledge_toggle <= request_sync;
			end else if (pending_notify) begin
				main_notify_data <= pending_notify_value;
				pending_notify <= 1'b0;
			end
		end
	end

	// Mask immediately when either reset asserts, and keep outputs zero through
	// independently synchronized release so no retained pre-reset value leaks.
	assign main_byte = (combined_reset_n && master_reset_release) ? main_byte_data : 8'h00;
	assign main_notify = (combined_reset_n && master_reset_release) ? main_notify_data : 1'b0;
endmodule
