library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.T65_Pack.all;

entity tb_t65_write_strobes is
end entity;

architecture test of tb_t65_write_strobes is
	type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
	constant memory : memory_t := (
		16#8000# => x"A9", 16#8001# => x"11", -- LDA #$11
		16#8002# => x"8D", 16#8003# => x"00", 16#8004# => x"50", -- STA $5000
		16#8005# => x"8D", 16#8006# => x"40", 16#8007# => x"50", -- STA $5040
		16#8008# => x"8D", 16#8009# => x"80", 16#800A# => x"50", -- STA $5080
		16#800B# => x"8D", 16#800C# => x"C0", 16#800D# => x"50", -- STA $50C0
		16#800E# => x"8D", 16#800F# => x"00", 16#8010# => x"51", -- STA $5100
		16#8011# => x"8D", 16#8012# => x"01", 16#8013# => x"51", -- STA $5101
		16#8014# => x"8D", 16#8015# => x"00", 16#8016# => x"52", -- STA $5200
		16#8017# => x"8D", 16#8018# => x"01", 16#8019# => x"52", -- STA $5201
		16#801A# => x"4C", 16#801B# => x"05", 16#801C# => x"80", -- loop: JMP $8005
		16#FFFC# => x"00", 16#FFFD# => x"80",
		others => x"EA"
	);
	type addresses_t is array (0 to 7) of std_logic_vector(15 downto 0);
	type counts_t is array (0 to 7) of natural;
	constant expected_addresses : addresses_t := (x"5000", x"5040", x"5080", x"50C0", x"5100", x"5101", x"5200", x"5201");
	signal clk : std_logic := '0';
	signal reset_n : std_logic := '0';
	signal rdy : std_logic := '1';
	signal enable : std_logic := '0';
	signal phase_count : natural range 0 to 63 := 0;
	signal rw_n, sync, ef, mf, xf, ml_n, vp_n, vda, vpa, ph3 : std_logic;
	signal address : std_logic_vector(23 downto 0);
	signal di, do_bus : std_logic_vector(7 downto 0);
	signal regs : std_logic_vector(63 downto 0);
	signal debug : T_t65_dbg;
	signal nmi_ack : std_logic;
	signal io_sel, ab_sel : std_logic;
	signal nwm1h, nwm1v, nwm2h, nwm2v, nwmol, nwcpl, weven, wodd : std_logic;
begin
	clk <= not clk after 5 ns;
	di <= memory(to_integer(unsigned(address(15 downto 0))));

	phase_gen : process(clk, reset_n)
	begin
		if reset_n = '0' then
			phase_count <= 0;
			enable <= '0';
		elsif rising_edge(clk) then
			if phase_count = 31 then enable <= '1'; else enable <= '0'; end if;
			if phase_count = 63 then phase_count <= 0;
			else phase_count <= phase_count + 1;
			end if;
		end if;
	end process;

	-- Decode equations mirror rtl/Exidy2.v. ABSEL models the selected board
	-- address window; the source guard pins the production WEVEN/WODD equations.
	io_sel <= '1' when address(15 downto 2) = std_logic_vector(to_unsigned(16#1440#, 14)) else '0';
	-- For this isolated synthetic bus, IOSEL is asserted only for $5100-$5103.
	-- The exact four addresses below are the only IO accesses in the program.
	ab_sel <= '1' when address(15 downto 4) = x"520" else '0';
	nwm1h <= '1' when address(15 downto 0) = x"5000" and rw_n = '0' else '0';
	nwm1v <= '1' when address(15 downto 0) = x"5040" and rw_n = '0' else '0';
	nwm2h <= '1' when address(15 downto 0) = x"5080" and rw_n = '0' else '0';
	nwm2v <= '1' when address(15 downto 0) = x"50C0" and rw_n = '0' else '0';
	nwmol <= '0' when io_sel = '1' and address(1 downto 0) = "00" and rw_n = '0' else '1';
	nwcpl <= '0' when io_sel = '1' and address(1 downto 0) = "01" and rw_n = '0' else '1';
	weven <= '1' when ab_sel = '1' and rw_n = '0' and address(0) = '0' else '0';
	wodd <= '1' when ab_sel = '1' and rw_n = '0' and address(0) = '1' else '0';

	dut : entity work.T65
	port map (
		Mode => "00", BCD_en => '1', Res_n => reset_n, Enable => enable,
		Clk => clk, Rdy => rdy, Abort_n => '1', IRQ_n => '1', NMI_n => '1',
		SO_n => '1', R_W_n => rw_n, Sync => sync, EF => ef, MF => mf,
		XF => xf, ML_n => ml_n, VP_n => vp_n, VDA => vda, VPA => vpa,
		PH3 => ph3, A => address, DI => di, DO => do_bus, Regs => regs,
		DEBUG => debug, NMI_ack => nmi_ack
	);

	watchdog : process
	begin
		wait for 300 us;
		assert false report "watchdog: T65 write-strobe test timed out" severity failure;
		wait;
	end process;

	monitor : process
		variable last_address : std_logic_vector(15 downto 0) := (others => '0');
		variable last_rw : std_logic := '1';
		variable last_data : std_logic_vector(7 downto 0) := (others => '0');
		variable active_write : boolean := false;
		variable stable_ticks : natural := 0;
		variable write_index : natural range 0 to 8 := 0;
		variable seen_ph1 : boolean := false;
		variable rising_counts : counts_t := (others => 0);
		variable falling_counts : counts_t := (others => 0);
		variable nwm_vec : std_logic_vector(3 downto 0);
		variable old_nwm_vec : std_logic_vector(3 downto 0) := (others => '0');
		variable old_nwmol, old_nwcpl : std_logic := '1';
		variable old_weven, old_wodd : std_logic := '0';
		variable paused : boolean := false;
		variable paused_ph1_edges : natural := 0;
		variable pause_bus_advanced : boolean := false;
		variable pause_address : std_logic_vector(15 downto 0) := (others => '0');
		variable pause_rw : std_logic := '1';
		variable pause_next_address : std_logic_vector(15 downto 0) := (others => '0');
		variable pause_next_rw : std_logic := '1';
	begin
		loop
			wait until rising_edge(clk);
			if reset_n = '1' then
			wait for 1 ns;
			nwm_vec := nwm2v & nwm2h & nwm1v & nwm1h;
			for i in 0 to 3 loop
				if old_nwm_vec(i) = '0' and nwm_vec(i) = '1' then rising_counts(i) := rising_counts(i) + 1; end if;
				if old_nwm_vec(i) = '1' and nwm_vec(i) = '0' then falling_counts(i) := falling_counts(i) + 1; end if;
			end loop;
			if old_nwmol = '1' and nwmol = '0' then rising_counts(4) := rising_counts(4) + 1; end if;
			if old_nwmol = '0' and nwmol = '1' then falling_counts(4) := falling_counts(4) + 1; end if;
			if old_nwcpl = '1' and nwcpl = '0' then rising_counts(5) := rising_counts(5) + 1; end if;
			if old_nwcpl = '0' and nwcpl = '1' then falling_counts(5) := falling_counts(5) + 1; end if;
			if old_weven = '0' and weven = '1' then rising_counts(6) := rising_counts(6) + 1; end if;
			if old_weven = '1' and weven = '0' then falling_counts(6) := falling_counts(6) + 1; end if;
			if old_wodd = '0' and wodd = '1' then rising_counts(7) := rising_counts(7) + 1; end if;
			if old_wodd = '1' and wodd = '0' then falling_counts(7) := falling_counts(7) + 1; end if;
			old_nwm_vec := nwm_vec; old_nwmol := nwmol; old_nwcpl := nwcpl; old_weven := weven; old_wodd := wodd;
			if paused and (address(15 downto 0) /= pause_address or rw_n /= pause_rw) and not pause_bus_advanced then
				pause_bus_advanced := true;
				pause_next_address := address(15 downto 0); pause_next_rw := rw_n;
				report "RDY-low bus advanced before second PH_1: address=$" & to_hstring(address(15 downto 0)) &
					" rw_n=" & std_logic'image(rw_n) severity note;
			elsif paused and pause_bus_advanced then
				assert address(15 downto 0) = pause_next_address and rw_n = pause_next_rw
					report "T65 bus did not hold its read request while RDY was low" severity failure;
			end if;
			if paused and enable = '1' then
				paused_ph1_edges := paused_ph1_edges + 1;
				report "RDY-low PH_1 enable observed, count=" & natural'image(paused_ph1_edges) severity note;
				if paused_ph1_edges = 2 then
					rdy <= '1'; paused := false;
					report "RDY resumed after two PH_1 enables" severity note;
				end if;
			end if;

			if rw_n = '0' and address(15 downto 0) /= last_address then
				if active_write then
					assert stable_ticks >= 2 report "write address/data did not remain stable across master edges" severity failure;
				end if;
				assert write_index < 8 report "unexpected extra bus write before loop" severity failure;
				assert address(15 downto 0) = expected_addresses(write_index) report "unexpected write order/address" severity failure;
				assert do_bus = x"11" report "unexpected synthetic write data" severity failure;
				report "BUS_WRITE t=" & time'image(now) & " address=$" & to_hstring(address(15 downto 0)) &
					" data=$" & to_hstring(do_bus) & " rw_n=" & std_logic'image(rw_n) severity note;
				write_index := write_index + 1;
				active_write := true; stable_ticks := 1; seen_ph1 := false;
				last_address := address(15 downto 0); last_data := do_bus; last_rw := rw_n;
				if write_index = 1 then
					rdy <= '0'; paused := true; paused_ph1_edges := 0;
					pause_address := address(15 downto 0); pause_rw := rw_n;
				end if;
			elsif active_write and rw_n = '0' and address(15 downto 0) = last_address then
				assert do_bus = last_data and rw_n = last_rw report "write bus changed while address held" severity failure;
				stable_ticks := stable_ticks + 1;
				if enable = '1' then seen_ph1 := true; end if;
			elsif active_write and rw_n = '1' then
				assert seen_ph1 report "T65 did not present write through a PH_1 enable" severity failure;
				active_write := false;
			end if;

			if write_index = 8 and address(15 downto 0) = x"801A" and rw_n = '1' then
				assert rising_counts(0) = 1 and falling_counts(0) = 1 report "nWM1H transition count mismatch" severity failure;
				assert rising_counts(1) = 1 and falling_counts(1) = 1 report "nWM1V transition count mismatch" severity failure;
				assert rising_counts(2) = 1 and falling_counts(2) = 1 report "nWM2H transition count mismatch" severity failure;
				assert rising_counts(3) = 1 and falling_counts(3) = 1 report "nWM2V transition count mismatch" severity failure;
				assert rising_counts(4) = 1 and falling_counts(4) = 1 report "nWMOL active-low transition count mismatch" severity failure;
				assert rising_counts(5) = 1 and falling_counts(5) = 1 report "nWCPL active-low transition count mismatch" severity failure;
				assert rising_counts(6) = 1 and falling_counts(6) = 1 report "WEVEN transition count mismatch" severity failure;
				assert rising_counts(7) = 1 and falling_counts(7) = 1 report "WODD transition count mismatch" severity failure;
				report "PASS T65 writes all eight decoded registers with stable bus and pause/resume" severity note;
				stop;
				exit;
			end if;
			end if;
		end loop;
	end process;

	-- These event-driven assertions sample decode edges directly, including the
	-- nWMOL/nWCPL end-of-write capture edge that a master-clock monitor can miss.
	strobe_edge_capture : process
	begin
		wait until reset_n = '1';
		loop
			wait on nwm1h, nwm1v, nwm2h, nwm2v, nwmol, nwcpl, weven, wodd;
			if nwm1h'event then
				assert do_bus = x"11" report "nWM1H edge data mismatch" severity failure;
				if nwm1h = '1' then assert address(15 downto 0) = x"5000" report "nWM1H start address mismatch" severity failure; end if;
			end if;
			if nwm1v'event then
				assert do_bus = x"11" report "nWM1V edge data mismatch" severity failure;
				if nwm1v = '1' then assert address(15 downto 0) = x"5040" report "nWM1V start address mismatch" severity failure; end if;
			end if;
			if nwm2h'event then
				assert do_bus = x"11" report "nWM2H edge data mismatch" severity failure;
				if nwm2h = '1' then assert address(15 downto 0) = x"5080" report "nWM2H start address mismatch" severity failure; end if;
			end if;
			if nwm2v'event then
				assert do_bus = x"11" report "nWM2V edge data mismatch" severity failure;
				if nwm2v = '1' then assert address(15 downto 0) = x"50C0" report "nWM2V start address mismatch" severity failure; end if;
			end if;
			if nwmol'event then
				assert do_bus = x"11" report "nWMOL edge data mismatch" severity failure;
				if nwmol = '0' then assert address(15 downto 0) = x"5100" report "nWMOL start address mismatch" severity failure; end if;
				report "nWMOL edge t=" & time'image(now) & " level=" & std_logic'image(nwmol) & " data=$" & to_hstring(do_bus) severity note;
			end if;
			if nwcpl'event then
				assert do_bus = x"11" report "nWCPL edge data mismatch" severity failure;
				if nwcpl = '0' then assert address(15 downto 0) = x"5101" report "nWCPL start address mismatch" severity failure; end if;
				report "nWCPL edge t=" & time'image(now) & " level=" & std_logic'image(nwcpl) & " data=$" & to_hstring(do_bus) severity note;
			end if;
			if weven'event then
				assert do_bus = x"11" report "WEVEN edge data mismatch" severity failure;
				if weven = '1' then assert address(15 downto 0) = x"5200" report "WEVEN start address mismatch" severity failure; end if;
			end if;
			if wodd'event then
				assert do_bus = x"11" report "WODD edge data mismatch" severity failure;
				if wodd = '1' then assert address(15 downto 0) = x"5201" report "WODD start address mismatch" severity failure; end if;
			end if;
		end loop;
	end process;

	stimulus : process
	begin
		wait for 40 ns;
		reset_n <= '1';
		wait;
	end process;
end architecture;
