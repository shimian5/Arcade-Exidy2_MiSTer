library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_timer3_event_order is end;

architecture sim of tb_timer3_event_order is
  signal clock : std_logic := '0';
  signal reset : std_logic := '1';
  signal cs : std_logic := '1';
  signal vs : std_logic := '0';
  signal addr : std_logic_vector(2 downto 0) := (others => '0');
  signal di : std_logic_vector(7 downto 0) := (others => '0');
  signal sample : std_logic_vector(11 downto 0);
  signal snd1, snd2, snd3 : signed(8 downto 0);
  signal noise_debug : std_logic_vector(127 downto 0);
  signal external_debug, raw3_debug, tick3_debug, q3_debug : std_logic;
  signal pre3_debug : std_logic_vector(2 downto 0);
  signal cnt3_debug : std_logic_vector(15 downto 0);
begin
  clock <= not clock after 5 ns;

  dut : entity work.berzerk_sound_fx
    generic map (CLK_DIV => 1)
    port map (
      clock, reset, cs, vs, addr, di, sample, snd1, snd2, snd3,
      noise_debug, external_debug, pre3_debug, raw3_debug,
      tick3_debug, cnt3_debug, q3_debug
    );

  stimulus : process
    procedure write_reg(constant a : in natural; constant d : in natural) is
    begin
      wait until falling_edge(clock);
      addr <= std_logic_vector(to_unsigned(a, addr'length));
      di <= std_logic_vector(to_unsigned(d, di'length));
      wait until rising_edge(clock);
      wait for 2 ns;
      -- Keep the board clock enable asserted while avoiding repeated writes
      -- to a control or period register between programmed transactions.
      addr <= "010";
    end procedure;
  begin
    wait for 25 ns;
    wait until falling_edge(clock);
    reset <= '0';

    -- MAME write semantics: CR2 bit 0 selects CR0 versus CR2 at offset 0.
    -- CR0=02 enables timer 0 on E; CR1=00 keeps another timer external so
    -- MAME's `noisy` optimization advances the LFSR; CR2=81 selects external
    -- noise plus timer-3 /8 and enables the output. Timer period is 1.
    write_reg(1, 1);
    write_reg(0, 2);
    write_reg(1, 0);
    write_reg(0, 16#81#);
    write_reg(6, 0);
    write_reg(7, 1);
    for i in 1 to 5000 loop
      wait until rising_edge(clock);
      wait for 2 ns;
    end loop;
    report "PASS timer3 external-event ordering fixture completed" severity note;
    wait;
  end process;

  mame_reference : process
    variable w0, w1, w2, w3 : unsigned(31 downto 0) := (others => '1');
    variable oldxor, newxor : std_logic := '0';
    variable cr0, cr1, cr2 : std_logic_vector(7 downto 0) := (others => '0');
    variable msb_latch : natural := 0;
    variable timer3, counter3 : natural := 0;
    variable state3 : std_logic := '0';
    variable leftovers3 : natural range 0 to 7 := 0;
    variable clocks, events : natural;
    variable mame_event : std_logic;
    variable old_raw, old_tick : std_logic := '0';
    variable modeled_pre : natural range 0 to 7 := 0;
    variable modeled_count : natural := 0;
    variable modeled_q : std_logic := '0';
    variable observed_q, prior_q : std_logic := '0';
    variable previous_mame_q : std_logic := '0';
    variable expected_tick : std_logic;
    variable model_ready : boolean := false;
    variable load_wait : natural := 0;
    variable mame_events, rtl_pulses, mame_toggles, rtl_toggles : natural := 0;
    variable divergence_count : natural := 0;
    variable first_divergence_cycle : integer := -1;
    variable first_mame_toggle_cycle, first_rtl_toggle_cycle : integer := -1;
    variable first_divergence_mame, first_divergence_rtl : std_logic := '0';
    variable cycles : natural := 0;
    variable active_cycles : natural := 0;
    variable noisy : boolean;
  begin
    loop
      wait until rising_edge(clock);
      cycles := cycles + 1;
      if reset = '1' then
        w0 := (others => '1'); w1 := (others => '1');
        w2 := (others => '1'); w3 := (others => '1'); oldxor := '0';
        cr0 := (others => '0'); cr1 := (others => '0'); cr2 := (others => '0');
        timer3 := 0; counter3 := 0; state3 := '0'; leftovers3 := 0;
        modeled_pre := 0; modeled_count := 0; modeled_q := '0';
        old_raw := '0'; old_tick := '0'; prior_q := '0'; previous_mame_q := '0';
        model_ready := false; load_wait := 0;
        active_cycles := 0;
        mame_events := 0; rtl_pulses := 0; mame_toggles := 0; rtl_toggles := 0;
        divergence_count := 0; first_divergence_cycle := -1;
        first_mame_toggle_cycle := -1; first_rtl_toggle_cycle := -1;
      else
        active_cycles := active_cycles + 1;
        -- MAME calls stream->update() before each register write, so first
        -- compute this sample's LFSR and timer event using the old controls.
        noisy := not (cr0(1) = '1' and cr1(1) = '1' and cr2(1) = '1');
        events := 0;
        if cr0(0) = '0' and noisy then
          newxor := w3(31) xor w2(31);
          w3 := shift_left(w3, 1); w3(0) := w2(31);
          w2 := shift_left(w2, 1); w2(0) := w1(31);
          w1 := shift_left(w1, 1); w1(0) := w0(31);
          w0 := shift_left(w0, 1); w0(0) := newxor xor oldxor;
          oldxor := newxor;
          if w2(1 downto 0) = "01" then events := 1; mame_events := mame_events + 1; end if;
        end if;

        -- Exidy's third timer takes the external noise-event count when CR3
        -- bit 1 is clear, then accumulates leftovers before divide-by-eight.
        if cr2(1) = '1' then clocks := 1; else clocks := events; end if;
        if cr2(0) = '1' then
          clocks := clocks + leftovers3;
          leftovers3 := clocks mod 8;
          clocks := clocks / 8;
        end if;
        while clocks > counter3 loop
          clocks := clocks - counter3 - 1;
          state3 := not state3;
          counter3 := timer3;
        end loop;
        counter3 := counter3 - clocks;
        if state3 /= previous_mame_q then
          mame_toggles := mame_toggles + 1;
          if first_mame_toggle_cycle = -1 then first_mame_toggle_cycle := integer(active_cycles); end if;
        end if;
        previous_mame_q := state3;

        -- VHDL synchronous process ordering: the timer sees the previous
        -- registered tick3/raw3; prescale advances on previous raw3.
        if old_tick = '1' then
          if modeled_count = 0 then
            modeled_q := not modeled_q;
            modeled_count := 1; -- programmed period 1
          else
            modeled_count := modeled_count - 1;
          end if;
        end if;
        if old_raw = '1' and cr2(0) = '1' then modeled_pre := (modeled_pre + 1) mod 8; end if;

        -- Apply the bus write after the current source sample, matching the
        -- MAME handler's stream update before register mutation.
        if cs = '1' then
          case to_integer(unsigned(addr)) is
            when 0 => if cr1(0) = '1' then cr0 := di; else cr2 := di; end if;
            when 1 => cr1 := di;
            when 6 => msb_latch := to_integer(unsigned(di));
            when 7 =>
              timer3 := msb_latch * 256 + to_integer(unsigned(di));
              if cr2(4) = '0' then counter3 := timer3; load_wait := 2; end if;
            when others => null;
          end case;
        end if;

        wait for 2 ns;
        assert noise_debug = std_logic_vector(w3 & w2 & w1 & w0)
          report "MAME and RTL LFSR states diverged at cycle " & integer'image(active_cycles)
          severity failure;
        observed_q := q3_debug;
        if external_debug = '1' then rtl_pulses := rtl_pulses + 1; end if;
        if observed_q /= prior_q then
          rtl_toggles := rtl_toggles + 1;
          if first_rtl_toggle_cycle = -1 then first_rtl_toggle_cycle := integer(active_cycles); end if;
        end if;
        prior_q := observed_q;

        if load_wait > 0 then
          load_wait := load_wait - 1;
          if load_wait = 0 then
            modeled_count := timer3;
            model_ready := true;
          end if;
        end if;
        if model_ready then
          assert unsigned(pre3_debug) = modeled_pre
            report "timer-3 prescale phase differs from previous-cycle raw3 event sequence at cycle " & integer'image(cycles)
            severity failure;
          assert unsigned(cnt3_debug) = modeled_count
            report "timer-3 counter differs from previous-cycle tick3 event sequence at cycle " & integer'image(cycles)
            severity failure;
          assert q3_debug = modeled_q
            report "timer-3 output differs from previous-cycle tick3 event sequence at cycle " & integer'image(cycles)
            severity failure;
        end if;

        expected_tick := raw3_debug;
        if cr2(0) = '1' and unsigned(pre3_debug) /= 7 then expected_tick := '0'; end if;
        assert tick3_debug = expected_tick
          report "raw3/pre3 to tick3 combinational phase differs at cycle " & integer'image(cycles)
          severity failure;
        old_raw := raw3_debug;
        old_tick := tick3_debug;

        if observed_q /= state3 then
          divergence_count := divergence_count + 1;
          if first_divergence_cycle = -1 then
            first_divergence_cycle := integer(active_cycles);
            first_divergence_mame := state3;
            first_divergence_rtl := observed_q;
          end if;
        end if;
        if active_cycles = 5006 then
          assert model_ready report "timer-3 model never reached loaded state" severity failure;
          assert mame_events > 0 and rtl_pulses > 0 report "fixture did not observe external clock pulses" severity failure;
          assert divergence_count > 0 report "expected source-event phase divergence was not observed" severity failure;
          report "RESULT cycles=" & integer'image(cycles) &
            " mame_noise_events=" & integer'image(mame_events) &
            " rtl_external_pulses=" & integer'image(rtl_pulses) &
            " mame_timer3_toggles=" & integer'image(mame_toggles) &
            " rtl_timer3_toggles=" & integer'image(rtl_toggles) &
            " first_mame_toggle_cycle=" & integer'image(first_mame_toggle_cycle) &
            " first_rtl_toggle_cycle=" & integer'image(first_rtl_toggle_cycle) &
            " output_phase_divergences=" & integer'image(divergence_count) &
            " first_divergence_cycle=" & integer'image(first_divergence_cycle) &
            " first_mame_q=" & std_logic'image(first_divergence_mame) &
            " first_rtl_q=" & std_logic'image(first_divergence_rtl) severity note;
          report "PASS timer3 output tracked against MAME and RTL event ordering" severity note;
        end if;
      end if;
    end loop;
  end process;

  watchdog : process
  begin
    wait for 60 us;
    assert false report "watchdog" severity failure;
  end process;
end architecture;
