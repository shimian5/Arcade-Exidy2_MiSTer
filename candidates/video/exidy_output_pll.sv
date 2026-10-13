// SPDX-License-Identifier: GPL-3.0-or-later
// Unbound exact-ratio, reconfigurable output PLL. Source PLL outclk1 = master/4.
// Multiplication 131/35 therefore gives master*131/140.
module exidy_output_pll #(parameter INITIAL_CRT=0)(
 input wire refclk, reset, input wire [63:0] reconfig_to_pll,
 output wire [63:0] reconfig_from_pll, output wire clk_output, locked);
 altera_pll #(
  .fractional_vco_multiplier("false"),
  .reference_clock_frequency("11.288265 MHz"), .operation_mode("direct"),
  .number_of_clocks(1), .output_clock_frequency0(INITIAL_CRT ? "42.250364 MHz" : "45.153061 MHz"),
  .phase_shift0("0 ps"), .duty_cycle0(50),
  .pll_type("Cyclone V"), .pll_subtype("Reconfigurable"),
  .pll_cp_current(20), .pll_bwctrl(4000), .pll_vco_div(1),
  .pll_output_clk_frequency(INITIAL_CRT ? "1478.762735 MHz" : "1444.897959 MHz"),
  .m_cnt_hi_div(INITIAL_CRT ? 66 : 64), .m_cnt_lo_div(INITIAL_CRT ? 65 : 64),
  .m_cnt_bypass_en("false"), .m_cnt_odd_div_duty_en(INITIAL_CRT ? "true" : "false"),
  .n_cnt_hi_div(1), .n_cnt_lo_div(1), .n_cnt_bypass_en("true"),
  .n_cnt_odd_div_duty_en("false"),
  .c_cnt_hi_div0(INITIAL_CRT ? 18 : 16), .c_cnt_lo_div0(INITIAL_CRT ? 17 : 16),
  .c_cnt_bypass_en0("false"), .c_cnt_odd_div_duty_en0(INITIAL_CRT ? "true" : "false")
 ) pll_i(.refclk(refclk), .rst(reset), .outclk(clk_output), .locked(locked),
  .fbclk(1'b0), .fboutclk(), .reconfig_to_pll(reconfig_to_pll), .reconfig_from_pll(reconfig_from_pll));
endmodule
