// SPDX-License-Identifier: GPL-3.0-or-later
// Static, unbound exact-ratio experiment. Source PLL outclk1 = master/4.
// Multiplication 131/35 therefore gives master*131/140.
module exidy_crt_output_pll(input wire refclk, reset, output wire clk_output, locked);
 altera_pll #(
  .fractional_vco_multiplier("false"),
  .reference_clock_frequency("11.288265 MHz"), .operation_mode("direct"),
  .number_of_clocks(1), .output_clock_frequency0("42.250364 MHz"),
  .phase_shift0("0 ps"), .duty_cycle0(50),
  .pll_type("Cyclone V"), .pll_subtype("General"),
  .pll_cp_current(20), .pll_bwctrl(4000), .pll_vco_div(1),
  .pll_output_clk_frequency("1478.762735 MHz"),
  .m_cnt_hi_div(66), .m_cnt_lo_div(65),
  .m_cnt_bypass_en("false"), .m_cnt_odd_div_duty_en("true"),
  .n_cnt_hi_div(1), .n_cnt_lo_div(1), .n_cnt_bypass_en("true"),
  .n_cnt_odd_div_duty_en("false"),
  .c_cnt_hi_div0(18), .c_cnt_lo_div0(17),
  .c_cnt_bypass_en0("false"), .c_cnt_odd_div_duty_en0("true")
 ) pll_i(.refclk(refclk), .rst(reset), .outclk(clk_output), .locked(locked),
  .fbclk(1'b0), .fboutclk(), .reconfig_to_pll(64'd0), .reconfig_from_pll());
endmodule
