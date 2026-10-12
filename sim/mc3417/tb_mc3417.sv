`timescale 1ns/1ps
module tb_mc3417 #(parameter WRONG_EDGE=0);
    reg clk=0, cold_reset_n=0, clock_reset=0, cvsd_clock=0, digit=0;
    wire signed [31:0] sample_q24, integrator_q24;
    wire [31:0] step_q24;
    wire [2:0] history;
    exidyMc3417 #(.SAMPLE_ON_RISING(WRONG_EDGE)) dut(
        .clk(clk), .cold_reset_n(cold_reset_n), .clock_reset(clock_reset),
        .cvsd_clock(cvsd_clock), .digit(digit), .sample_q24(sample_q24),
        .history(history), .step_q24(step_q24), .integrator_q24(integrator_q24));
    always #5 clk=~clk;
    integer file_id, status, rows=0;
    integer cold, warm, clock_value, bit_value, expected_history;
    real expected_step, expected_integrator, expected_sample;
    real error_step, error_integrator, error_sample;
    real maximum_step=0, maximum_integrator=0, maximum_sample=0;
    string reference_path;
    function automatic real abs_value(input real value);
        abs_value=(value<0) ? -value : value;
    endfunction
    initial begin
        if (!$value$plusargs("REFERENCE=%s",reference_path))
            $fatal(1,"REFERENCE path required");
        file_id=$fopen(reference_path,"r");
        if(!file_id) $fatal(1,"could not open pinned-method vectors");
        while(!$feof(file_id)) begin
            status=$fscanf(file_id,"%d %d %d %d %d %f %f %f\n",
                cold,warm,clock_value,bit_value,expected_history,
                expected_step,expected_integrator,expected_sample);
            if(status!=8) $fatal(1,"invalid reference row %0d",rows);
            @(negedge clk);
            cold_reset_n=!cold; clock_reset=warm;
            cvsd_clock=clock_value; digit=bit_value;
            @(posedge clk); #1;
            if(history!==expected_history[2:0])
                $fatal(1,"reference history mismatch row=%0d got=%0d expected=%0d",
                    rows,history,expected_history);
            error_step=abs_value($itor(step_q24)/16777216.0-expected_step);
            error_integrator=abs_value($itor(integrator_q24)/16777216.0-expected_integrator);
            error_sample=abs_value($itor(sample_q24)/16777216.0-expected_sample)*32768.0;
            if(error_step>maximum_step) maximum_step=error_step;
            if(error_integrator>maximum_integrator) maximum_integrator=error_integrator;
            if(error_sample>maximum_sample) maximum_sample=error_sample;
            if(error_step>0.000003 || error_integrator>0.00005 || error_sample>0.5)
                $fatal(1,"reference arithmetic mismatch row=%0d step=%f int=%f PCM_LSB=%f",
                    rows,error_step,error_integrator,error_sample);
            rows=rows+1;
        end
        $fclose(file_id);
        if(rows!=91924) $fatal(1,"reference coverage incomplete: %0d rows",rows);
        $display("PASS MC3417 pinned-method comparison rows=%0d max_step=%f max_integrator=%f max_PCM_LSB=%f",
            rows,maximum_step,maximum_integrator,maximum_sample);
        $finish;
    end
    initial begin #2ms; $fatal(1,"MC3417 reference watchdog"); end
endmodule
