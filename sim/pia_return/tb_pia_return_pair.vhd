library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_pia_return_pair is
	generic (PHASE_NS : natural := 0);
end entity;

architecture test of tb_pia_return_pair is
	signal cpu_sample : std_logic_vector(7 downto 0) := x"00";
	signal master_clk : std_logic := '0';
	signal audio_clk  : std_logic := '0';
	signal reset_m   : std_logic := '1';
	signal reset_a   : std_logic := '1';
	signal audio_stage_byte : std_logic_vector(7 downto 0) := x"00";
	signal main_data_q : std_logic_vector(7 downto 0) := x"00";
	signal main_byte_valid : std_logic := '0';
	signal stage_byte : std_logic_vector(7 downto 0) := x"00";
	signal cpu_databus : std_logic_vector(7 downto 0) := x"00";
	signal cpu_enable : std_logic := '0';
	signal cpu_cycle_count : natural range 0 to 63 := 0;
	signal progress : natural := 0;

	signal a_cs, a_rw : std_logic := '0';
	signal a_addr : std_logic_vector(1 downto 0) := "00";
	signal a_din, a_dout : std_logic_vector(7 downto 0) := x"00";
	signal a_irq_a, a_irq_b : std_logic;
	signal a_pa_i, a_pa_o, a_pa_oe : std_logic_vector(7 downto 0) := x"00";
	signal a_pb_i, a_pb_o, a_pb_oe : std_logic_vector(7 downto 0) := x"00";
	signal a_ca1, a_ca2_i, a_ca2_o, a_ca2_oe : std_logic := '0';
	signal a_cb1, a_cb2_i, a_cb2_o, a_cb2_oe : std_logic := '0';

	signal m_cs, m_rw : std_logic := '0';
	signal m_addr : std_logic_vector(1 downto 0) := "00";
	signal m_din, m_dout : std_logic_vector(7 downto 0) := x"00";
	signal m_irq_a, m_irq_b : std_logic;
	signal m_pa_i, m_pa_o, m_pa_oe : std_logic_vector(7 downto 0) := x"00";
	signal m_pb_i, m_pb_o, m_pb_oe : std_logic_vector(7 downto 0) := x"00";
	signal m_ca1, m_ca2_i, m_ca2_o, m_ca2_oe : std_logic := '0';
	signal m_cb1, m_cb2_i, m_cb2_o, m_cb2_oe : std_logic := '0';

begin
	clock_master : process
	begin
		master_clk <= '1'; -- first master positive edge is coincident with audio phase 0
		wait for 3.5 ns;
		master_clk <= '0';
		wait for 3.5 ns;
		loop
			master_clk <= '1';
			wait for 3.5 ns;
			master_clk <= '0';
			wait for 3.5 ns;
		end loop;
	end process;

	clock_audio : process
	begin
		wait for PHASE_NS * 1 ns;
		loop
			audio_clk <= not audio_clk;
			wait for 11 ns;
		end loop;
	end process;

	-- Equivalent to both stages in rtl/pia_return.v. The actual Verilog module is checked in
	-- a separate Verilator bench; this model lets the two production VHDL PIAs
	-- run together under GHDL with the fitted related-clock ratio.
	process(audio_clk)
	begin
		if rising_edge(audio_clk) then
			if reset_a = '1' then audio_stage_byte <= x"00";
			else audio_stage_byte <= a_pb_o;
			end if;
		end if;
	end process;

	process(master_clk)
	begin
		if rising_edge(master_clk) then
			main_data_q <= audio_stage_byte;
		end if;
	end process;

	process(master_clk, reset_m)
	begin
		if reset_m = '1' then
			main_byte_valid <= '0';
		elsif rising_edge(master_clk) then
			main_byte_valid <= '1';
		end if;
	end process;

	stage_byte <= main_data_q when main_byte_valid = '1' else x"00";

	process(master_clk)
	begin
		if rising_edge(master_clk) then
			if reset_m = '1' then
				cpu_databus <= x"00";
				cpu_sample <= x"00";
			else
				cpu_databus <= m_dout;
				if cpu_enable = '1' then
					cpu_sample <= cpu_databus;
				end if;
			end if;
		end if;
	end process;

	-- PH_1 is high for one master edge every 64 ticks. T65 consumes the
	-- previously registered enable, so the sample event is one edge later.
	process(master_clk)
	begin
		if rising_edge(master_clk) then
			if cpu_cycle_count = 31 then cpu_enable <= '1'; else cpu_enable <= '0'; end if;
			if cpu_cycle_count = 63 then cpu_cycle_count <= 0;
			else cpu_cycle_count <= cpu_cycle_count + 1;
			end if;
		end if;
	end process;

	a_pa_i <= x"00";
	a_pb_i <= x"00";
	a_ca1 <= m_cb2_o;
	a_cb1 <= m_ca2_o;
	m_pa_i <= stage_byte;
	m_pb_i <= x"00";
	m_ca1 <= a_cb2_o;
	m_cb1 <= a_ca2_o;

	-- Production PIA instances with the same cross-coupled handshake lines as
	-- audio_board.v: PIA_8B PB/CB2 -> PIA_9B PA/CA1, and CA2 -> CB1.
	audio_pia : entity work.pia6821
	port map (clk=>audio_clk, rst=>reset_a, cs=>a_cs, rw=>a_rw, addr=>a_addr,
		data_in=>a_din, data_out=>a_dout, irqa=>a_irq_a, irqb=>a_irq_b,
		pa_i=>a_pa_i, pa_o=>a_pa_o, pa_oe=>a_pa_oe, pa_ddr_ovrd=>x"00",
		ca1=>a_ca1, ca2_i=>a_ca2_i, ca2_o=>a_ca2_o, ca2_oe=>a_ca2_oe,
		pb_i=>a_pb_i, pb_o=>a_pb_o, pb_oe=>a_pb_oe,
		cb1=>a_cb1, cb2_i=>a_cb2_i, cb2_o=>a_cb2_o, cb2_oe=>a_cb2_oe);

	main_pia : entity work.pia6821
	port map (clk=>master_clk, rst=>reset_m, cs=>m_cs, rw=>m_rw, addr=>m_addr,
		data_in=>m_din, data_out=>m_dout, irqa=>m_irq_a, irqb=>m_irq_b,
		pa_i=>m_pa_i, pa_o=>m_pa_o, pa_oe=>m_pa_oe, pa_ddr_ovrd=>x"00",
		ca1=>m_ca1, ca2_i=>m_ca2_i, ca2_o=>m_ca2_o, ca2_oe=>m_ca2_oe,
		pb_i=>m_pb_i, pb_o=>m_pb_o, pb_oe=>m_pb_oe,
		cb1=>m_cb1, cb2_i=>m_cb2_i, cb2_o=>m_cb2_o, cb2_oe=>m_cb2_oe);

	watchdog : process
	begin
		wait for 100 us;
		assert false report "watchdog: paired PIA handshake stalled at test step " & integer'image(progress) &
			" (IRQ=" & std_logic'image(m_irq_a) & ", audio CB2=" & std_logic'image(a_cb2_o) & ")"
			severity failure;
		wait;
	end process;

	stimulus : process
		procedure write_audio(constant reg_addr : std_logic_vector(1 downto 0);
		                       constant value : std_logic_vector(7 downto 0)) is
		begin
			wait until falling_edge(audio_clk);
			a_addr <= reg_addr;
			a_din <= value;
			a_rw <= '0';
			a_cs <= '1';
			wait until rising_edge(audio_clk);
			wait for 1 ns;
			a_cs <= '0';
			a_rw <= '1';
		end procedure;

		procedure write_main(constant reg_addr : std_logic_vector(1 downto 0);
		                     constant value : std_logic_vector(7 downto 0)) is
		begin
			wait until falling_edge(master_clk);
			m_addr <= reg_addr;
			m_din <= value;
			m_rw <= '0';
			m_cs <= '1';
			wait until rising_edge(master_clk);
			wait for 1 ns;
			m_cs <= '0';
			m_rw <= '1';
		end procedure;

		procedure read_response(constant expected : std_logic_vector(7 downto 0)) is
		begin
			-- Inspect the return data after IRQ without asserting CS; an actual
			-- T65 cannot issue the read until a PH_1 enable. This distinguishes
			-- IRQ visibility from the earliest modeled legal CPU read cycle.
			progress <= progress + 1;
			wait until m_irq_a = '1';
			progress <= progress + 1;
			m_addr <= "00";
			m_rw <= '1';
			m_cs <= '0';
			wait for 1 ns;
			assert m_dout = expected
				report "staged PIA return byte was stale when IRQ became visible"
				severity failure;
			-- The first PH_1 is the IRQ/status boundary. Start the PIA read
			-- immediately after it, then hold it for one CPU bus interval.
			wait until rising_edge(master_clk) and cpu_enable = '1';
			wait for 1 ns;
			progress <= progress + 1;
			m_cs <= '1';
			wait until rising_edge(master_clk) and cpu_enable = '1';
			wait for 1 ns;
			progress <= progress + 1;
			assert cpu_sample = expected
				report "main CPU bus register had stale PIA data at first read PH_1 sample"
				severity failure;
			wait until falling_edge(master_clk); -- PIA PA read clears CA2
			wait for 1 ns;
			m_cs <= '0';
			if a_cb2_o /= '1' then
				wait until a_cb2_o = '1'; -- returned ACK restores audio CB2
			end if;
			wait for 1 ns;
			progress <= progress + 1;
			assert m_dout = expected report "PIA response changed before ACK" severity failure;
		end procedure;

		procedure send_and_check(constant value, expected : std_logic_vector(7 downto 0)) is
		begin
			write_audio("10", value);
			read_response(expected);
		end procedure;
	begin
		wait until rising_edge(master_clk);
		reset_m <= '0';
		wait until rising_edge(audio_clk);
		reset_a <= '0';

		-- Main PIA A is input, PA read clears CA2, and a falling CA1 edge
		-- raises the IRQ/handshake output. Audio PIA B is output; initialize
		-- CB2 high, then select write-PB-clears / CB1-edge-sets mode.
		write_main("00", x"00"); -- PA DDR all inputs
		write_main("01", x"25"); -- CA1 falling IRQ, PA-read CA2 handshake

		write_audio("10", x"FF"); -- audio PB DDR all outputs
		write_audio("11", x"3C"); -- CB2 output set high
		if a_cb2_o /= '1' then wait until a_cb2_o = '1'; end if;
		write_audio("11", x"25"); -- PB data, CB2 handshake mode, CB1 falling edge
		write_audio("11", x"25"); -- re-write to ensure control stable after first update

		send_and_check(x"00", x"00");
		send_and_check(x"FF", x"FF");
		send_and_check(x"A5", x"A5");
		send_and_check(x"5A", x"5A");

		-- A partially driven byte must remain a coherent whole-byte sample;
		-- undriven PIA input pins are tied low in this production wiring.
		write_audio("11", x"21"); -- select PIA B DDR without changing handshake mode
		write_audio("10", x"0F");
		write_audio("11", x"25"); -- return to PB data register
		send_and_check(x"A5", x"05");
		write_audio("11", x"21");
		write_audio("10", x"FF");
		write_audio("11", x"25");

		-- Reset while a response is outstanding; independently reset the source
		-- and destination stages, then prove a fresh response still works.
		write_audio("10", x"C3");
		wait until m_irq_a = '1';
		wait until rising_edge(master_clk);
		reset_a <= '1';
		wait until rising_edge(audio_clk); wait for 1 ns;
		assert audio_stage_byte = x"00" report "audio source stage did not clear during source reset" severity failure;
		-- The destination stage follows PIA_9B's asynchronous active-high reset
		-- immediately, without waiting for the next master edge.
		reset_m <= '1';
		wait for 1 ns;
		assert stage_byte = x"00" report "return register did not clear during reset" severity failure;
		wait until rising_edge(audio_clk); reset_a <= '0';
		wait until rising_edge(master_clk); reset_m <= '0';
		wait until rising_edge(master_clk); wait for 1 ns;
		assert stage_byte = x"00" report "stale response survived reset" severity failure;

		-- Reconfigure after reset and exercise a clean new transaction.
		write_main("00", x"00");
		write_main("01", x"25");
		write_audio("10", x"FF");
		write_audio("11", x"3C");
		if a_cb2_o /= '1' then wait until a_cb2_o = '1'; end if;
		write_audio("11", x"25");
		send_and_check(x"96", x"96");

		-- The masked data FF may retain an old complete byte through reset, but
		-- PIA_9B must see zero immediately and until the next master capture.
		assert stage_byte = x"96" report "expected final response before reset-mask test" severity failure;
		wait until falling_edge(master_clk);
		reset_m <= '1';
		wait for 1 ns;
		assert stage_byte = x"00" report "valid mask did not hide retained data on async reset" severity failure;
		wait until rising_edge(master_clk);
		wait for 1 ns;
		assert main_data_q = x"96" and stage_byte = x"00"
			report "reset mask did not hide stale complete byte while held" severity failure;
		reset_m <= '0';
		wait for 1 ns;
		assert stage_byte = x"00" report "valid mask exposed stale data on reset release" severity failure;
		wait until rising_edge(master_clk);
		wait for 1 ns;
		assert stage_byte = x"96" report "valid mask did not restore byte on first master edge" severity failure;

		report "PASS paired production PIA return byte phase=" & integer'image(PHASE_NS) & "ns" severity note;
		stop;
		wait;
	end process;
end architecture;
