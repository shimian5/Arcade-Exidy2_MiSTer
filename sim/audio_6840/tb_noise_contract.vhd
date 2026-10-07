library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_noise_contract is end;
architecture sim of tb_noise_contract is
  signal clock : std_logic := '0';
  signal reset : std_logic := '1';
  signal sample : std_logic_vector(11 downto 0);
  signal s1, s2, s3 : signed(8 downto 0);
  signal noise_debug : std_logic_vector(127 downto 0);
  signal external_debug : std_logic;
begin
  dut : entity work.berzerk_sound_fx
    generic map (CLK_DIV => 1)
    port map (clock, reset, '0', '0', "000", x"00", sample, s1, s2, s3, noise_debug, external_debug);
  process
    variable w0, w1, w2, w3 : unsigned(31 downto 0) := (others => '1');
    variable oldxor, newxor : std_logic := '0';
    variable prev95, last_sample95 : std_logic := '1';
    variable expected_external, mame_event : std_logic;
    variable mame_count, rtl_count, pulse_mismatches : natural := 0;
    variable rtl_rise_now : std_logic;
  begin
    wait for 30 ns;
    reset <= '0';
    wait for 1 ns;
    for i in 1 to 513 loop
      clock <= '1';
      wait for 1 ns;
      if i = 1 then
        -- The production enable itself is registered; the first parent edge only establishes it.
        assert noise_debug = (noise_debug'range => '1') severity failure;
      else
        -- Independent literal MAME word-array step. Use old values for all carries.
        newxor := (w3(31) xor w2(31));
        w3 := shift_left(w3, 1); w3(0) := w2(31);
        w2 := shift_left(w2, 1); w2(0) := w1(31);
        w1 := shift_left(w1, 1); w1(0) := w0(31);
        w0 := shift_left(w0, 1); w0(0) := newxor xor oldxor;
        oldxor := newxor;
        mame_event := '0';
        if w2(1 downto 0) = "01" then mame_event := '1'; mame_count := mame_count + 1; end if;
        assert noise_debug = std_logic_vector(w3 & w2 & w1 & w0)
          report "production VHDL LFSR state differs at step " & integer'image(i-1) & " rtl=" & to_hstring(noise_debug) & " ref=" & to_hstring(std_logic_vector(w3 & w2 & w1 & w0))
          severity failure;
        -- RTL detects a rising edge of vector bit 95, then registers that detection for the next clock.
        expected_external := '0';
        if prev95 = '0' and last_sample95 = '1' then expected_external := '1'; end if;
        assert external_debug = expected_external
          report "RTL registered bit-95 pulse timing differs from its source-level edge detector" severity failure;
        if expected_external = '1' then rtl_count := rtl_count + 1; end if;
        rtl_rise_now := '0';
        if last_sample95 = '0' and noise_debug(95) = '1' then rtl_rise_now := '1'; end if;
        if rtl_rise_now /= mame_event then pulse_mismatches := pulse_mismatches + 1; end if;
        prev95 := last_sample95;
        last_sample95 := noise_debug(95);
      end if;
      clock <= '0'; wait for 1 ns;
    end loop;
    assert pulse_mismatches > 0
      report "negative control expected distinct MAME tap and RTL bit-95 event positions" severity failure;
    report "RESULT steps=512 mame_postshift_low2_events=" & integer'image(mame_count) &
      " rtl_registered_bit95_pulses=" & integer'image(rtl_count) &
      " event_position_mismatches=" & integer'image(pulse_mismatches) &
      " prescale_div8_aggregate_mame=" & integer'image(mame_count / 8) &
      " prescale_div8_aggregate_rtl=" & integer'image(rtl_count / 8) severity note;
    report "PASS noise recurrence; MAME and RTL tap events counted and compared by step" severity note;
    wait;
  end process;
  watchdog : process
  begin
    wait for 2 us;
    assert false report "watchdog" severity failure;
  end process;
end architecture;
