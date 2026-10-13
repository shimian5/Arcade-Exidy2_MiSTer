`timescale 1ns/1ps
// Independent coordinate/frame oracle; no hierarchical RAM seeding.
module tb_crt_stream;
reg clk_native=0, clk_crt=0, reset_async=1;
always #10 clk_native=!clk_native;
integer drift_ppm=0, frames_to_check=12;
longint unsigned crt_denominator, crt_remainder=0, crt_delay;
initial begin
	if($value$plusargs("DRIFT_PPM=%d",drift_ppm)) begin end
	if($value$plusargs("FRAMES=%d",frames_to_check)) begin end
	if(frames_to_check<1 || frames_to_check>256) $fatal(1,"Frame count outside oracle capacity");
	if(drift_ppm<-500000 || drift_ppm>500000) $fatal(1,"Clock drift outside fixture range");
	crt_denominator=64'd131*(64'd1000000+64'(drift_ppm));
	forever begin
		crt_delay=64'd1400000000000/crt_denominator;
		crt_remainder+=64'd1400000000000%crt_denominator;
		if(crt_remainder>=crt_denominator) begin crt_delay++; crt_remainder-=crt_denominator; end
		// The checked range bounds each delay above 7,000 ps. Verilator
		// cannot prove that for a rational period read from plusargs.
		/* verilator lint_off ZERODLY */
		#(crt_delay*1ps) clk_crt=!clk_crt;
		/* verilator lint_on ZERODLY */
	end
end

reg [2:0] source_div=0;
reg [8:0] source_x=0, source_y=0;
reg [7:0] source_frame=1;
reg source_stopped=0;
wire source_ce=source_div==7 && !source_stopped;
wire source_hb=source_x>=256, source_vb=source_y>=256;
reg damage_frame=0;
bit pause_case=0,reset_case=0,stop_case=0,fault_only=0;
wire damaging=damage_frame && source_frame==8'd3;
wire [8:0] input_x=damaging && source_x==9'd100 && source_y==9'd60 ? 9'd101 : source_x;
wire [7:0] image_id=pause_case && source_frame>=4 && source_frame<=6 ? 8'd4 : source_frame;
wire [23:0] source_rgb={image_id,source_y[7:0],source_x[7:0]};
// Record the first completed row of each input frame, independently of the
// stream mailbox. A later damaged row invalidates the remainder of that frame.
integer complete_images[0:255],complete_count=0,output_index=0;
realtime source_top_time=0, complete_times[0:255];
real delay_native_clocks, minimum_delay=1.0e9, maximum_delay=0;
always @(posedge clk_native) begin
	if(reset_async) complete_count=0;
	else if(source_ce) begin
		if(source_x==0 && source_y==0) source_top_time=$realtime;
		if(source_x==255 && source_y==0) begin
			complete_images[complete_count]=int'(image_id);
			complete_times[complete_count]=source_top_time;
			complete_count++;
		end
	end
end
always @(posedge clk_native) begin
	if(reset_async) begin source_div<=0; source_x<=0; source_y<=0; source_frame<=1; end
	else if(!source_stopped) begin
		source_div<=source_div+3'd1;
		if(source_ce) begin
			if(source_x==335) begin
				source_x<=0;
				if(source_y==279) begin source_y<=0; source_frame<=source_frame+8'd1; end
				else source_y<=source_y+9'd1;
			end else source_x<=source_x+9'd1;
		end
	end
end
wire ce_out,hs,vs,hb,vb,valid;
wire [23:0] rgb_out;
wire [8:0] x,y;
wire [31:0] skipped,repeated,malformed;
exidy_crt_stream dut (
	.clk_native(clk_native), .clk_crt(clk_crt), .reset_async(reset_async),
	.ce_native(source_ce), .rgb_native(source_rgb), .x_native(input_x), .y_native(source_y),
	.hb_native(source_hb), .vb_native(source_vb),
	.ce_out(ce_out), .rgb_out(rgb_out), .x_out(x), .y_out(y),
	.hs_out(hs), .vs_out(vs), .hb_out(hb), .vb_out(vb), .frame_valid(valid),
	.source_skips(skipped), .stream_faults(repeated), .malformed_frames(malformed)
);

longint unsigned clocks=0,last_ce=0,pixels=0,checked_pixels=0,ownership_checks=0;
integer checked_frames=0,frame_pixels=0,previous_frame=0,displayed_frame=0;
integer expected_x=0,expected_y=0;
bit stream_started=0, image_started=0;
always @(posedge clk_crt) begin
	clocks++;
	// Check every write/read ownership overlap, not just visible output.
	if(!reset_async && dut.reader_valid && dut.write_pixel && dut.row_ready && dut.raster_x<256 && dut.raster_y<256) begin
		ownership_checks++;
		if(source_y[4:0]==dut.raster_y[4:0]) $fatal(1,"Source overwrote the reader row");
	end
	if(reset_async || !valid) begin
		stream_started=0; image_started=0; last_ce=0;
		if(reset_async) begin previous_frame=0; output_index=0; end
	end
	else if(ce_out) begin
		if(stream_started) begin
			if(clocks-last_ce!=8) $fatal(1,"Unequal CRT pixel repetition");
			if(int'(x)!=expected_x || int'(y)!=expected_y) $fatal(1,"Raster order %0d,%0d expected %0d,%0d",x,y,expected_x,expected_y);
		end
		stream_started=1; last_ce=clocks; pixels++;
		expected_x=x==335 ? 0 : int'(x)+1;
		expected_y=x==335 ? (y==261 ? 0 : int'(y)+1) : int'(y);
		if(hb!==(x>=256) || vb!==(y>=256) || hs!==(x>=272 && x<304) || vs!==(y==258))
			$fatal(1,"CRT geometry/sync mismatch");
		if(x==0 && y==0) begin
			image_started=1; displayed_frame=int'(rgb_out[23:16]); frame_pixels=0;
			if(drift_ppm==0) begin
				if(output_index>=complete_count || displayed_frame!=complete_images[output_index])
					$fatal(1,"Nominal output not the next source frame: %0d at index %0d",displayed_frame,output_index);
				delay_native_clocks=($realtime-complete_times[output_index])/20.0;
				if(delay_native_clocks<2048.549 || delay_native_clocks>2074.2)
					$fatal(1,"First-pixel delay %f native clocks violates scheduling proof",delay_native_clocks);
				if(delay_native_clocks<minimum_delay) minimum_delay=delay_native_clocks;
				if(delay_native_clocks>maximum_delay) maximum_delay=delay_native_clocks;
				output_index++;
			end else begin
				bit complete_found;
				complete_found=0;
				for(integer index=0;index<complete_count;index++)
					if(complete_images[index]==displayed_frame) complete_found=1;
				if(displayed_frame<previous_frame || !complete_found)
					$fatal(1,"Drift output reordered or consumed an unfinished frame");
			end
		end
		if(!hb && !vb && image_started) begin
			if(rgb_out!=={8'(displayed_frame),y[7:0],x[7:0]}) $fatal(1,"Torn/stale/reordered pixel at %0d,%0d: %06x",x,y,rgb_out);
			frame_pixels++; checked_pixels++;
		end else if((hb || vb) && rgb_out!==0) $fatal(1,"CRT blank drives image data");
		if(x==255 && y==255 && image_started) begin
			if(frame_pixels!=65536) $fatal(1,"Incomplete image: %0d pixels",frame_pixels);
			previous_frame=displayed_frame; checked_frames++;
			if(checked_frames==frames_to_check) begin
				if(drift_ppm==0 && !damage_frame && !stop_case && (skipped!=0 || repeated!=0 || malformed!=0)) $fatal(1,"Nominal stream recovered unexpectedly");
				if(drift_ppm!=0 && skipped==0 && repeated==0) $fatal(1,"Drift case did not exercise ownership recovery");
				if(damage_frame && malformed==0) $fatal(1,"Malformed capture not rejected");
				$display("PASS: CRT stream %0d complete frames/%0d verified pixels, %0d ownership checks, drift=%0d ppm; skips=%0d faults=%0d malformed=%0d; first-pixel delay %f..%f native clocks",checked_frames,checked_pixels,ownership_checks,drift_ppm,skipped,repeated,malformed,minimum_delay,maximum_delay);
				$finish;
			end
		end
	end
end
initial begin
	damage_frame=$test$plusargs("DAMAGE");
	pause_case=$test$plusargs("PAUSE");
	reset_case=$test$plusargs("RESET");
	stop_case=$test$plusargs("STOP");
	fault_only=$test$plusargs("FAULT_ONLY");
	#137 reset_async=0;
	if(reset_case) begin #50000007 reset_async=1; #59 reset_async=0; end
	if(stop_case) begin
		wait(source_frame==3 && source_y==60 && source_x==0);
		source_stopped=1;
		#2000000 source_stopped=0;
	end
	if(fault_only) begin
		#150000000;
		if(repeated==0 || ownership_checks==0 || checked_pixels==0)
			$fatal(1,"Severe clock mismatch did not exercise checked fault containment");
		$display("PASS: severe mismatch containment, drift=%0d ppm, faults=%0d, checked pixels=%0d, complete frames=%0d",drift_ppm,repeated,checked_pixels,checked_frames);
		$finish;
	end
	// Validated frame bounds make this timeout positive; the tool cannot
	// infer a plusarg-dependent delay's range across initial processes.
	/* verilator lint_off ZERODLY */
	#(64'(frames_to_check)*64'd20000000+64'd200000000) $fatal(1,"Streaming test timed out");
	/* verilator lint_on ZERODLY */
end
endmodule
