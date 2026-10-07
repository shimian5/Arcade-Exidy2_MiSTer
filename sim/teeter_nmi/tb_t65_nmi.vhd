library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.T65_Pack.all;

entity tb_t65_nmi is
end entity;

architecture test of tb_t65_nmi is
	type memory_t is array (0 to 65535) of std_logic_vector(7 downto 0);
	constant memory : memory_t := (
		16#8000# => x"4C", -- JMP $8000: synthetic idle loop
		16#8001# => x"00",
		16#8002# => x"80",
		16#9000# => x"40", -- RTI: synthetic NMI handler
		16#FFFA# => x"00", -- NMI vector $9000
		16#FFFB# => x"90",
		16#FFFC# => x"00", -- reset vector $8000
		16#FFFD# => x"80",
		others => x"EA"
	);
	signal clk : std_logic := '0';
	signal reset_n : std_logic := '0';
	signal enable : std_logic := '0';
	signal phase_count : natural range 0 to 63 := 0;
	signal rdy : std_logic := '1';
	signal nmi_n : std_logic := '1';
	signal rw_n, sync, ef, mf, xf, ml_n, vp_n, vda, vpa, ph3 : std_logic;
	signal address : std_logic_vector(23 downto 0);
	signal di, do_bus : std_logic_vector(7 downto 0);
	signal regs : std_logic_vector(63 downto 0);
	signal debug : T_t65_dbg;
	signal nmi_ack : std_logic;
begin
	clk <= not clk after 5 ns;
	di <= memory(to_integer(unsigned(address(15 downto 0))));

	-- Source-matched PH_1: one master-clock enable every 64 ticks, generated
	-- from the same compare cadence used by rtl/Exidy2.v.
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

	dut : entity work.T65
	port map (
		Mode => "00", BCD_en => '1', Res_n => reset_n, Enable => enable,
		Clk => clk, Rdy => rdy, Abort_n => '1', IRQ_n => '1', NMI_n => nmi_n,
		SO_n => '1', R_W_n => rw_n, Sync => sync, EF => ef, MF => mf,
		XF => xf, ML_n => ml_n, VP_n => vp_n, VDA => vda, VPA => vpa,
		PH3 => ph3, A => address, DI => di, DO => do_bus, Regs => regs,
		DEBUG => debug, NMI_ack => nmi_ack
	);

	watchdog : process
	begin
		wait for 100 us;
		assert false report "watchdog: T65 NMI test timed out" severity failure;
		wait;
	end process;

	stimulus : process
		variable found_reset_pc : boolean := false;
		variable found_nmi_pc : boolean := false;
		variable held_address : std_logic_vector(23 downto 0);
	begin
		wait for 40 ns;
		reset_n <= '1';
		for i in 0 to 3000 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			if address(15 downto 0) = x"8000" and rw_n = '1' then
				found_reset_pc := true;
				exit;
			end if;
		end loop;
		assert found_reset_pc report "T65 did not fetch synthetic reset program" severity failure;

		-- T65 samples the NMI edge on Enable edges even while Rdy='0'.
		wait until falling_edge(clk);
		rdy <= '0';
		held_address := address;
		nmi_n <= '0';
		for i in 0 to 70 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			exit when nmi_ack = '1';
		end loop;
		assert nmi_ack = '1' report "T65 did not latch NMI at PH_1 while RDY was low" severity failure;
		for i in 0 to 70 loop
			exit when i = 70;
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert nmi_ack = '1' report "latched NMI was lost while paused" severity failure;
		assert address = held_address report "T65 advanced bus state while RDY was low" severity failure;

		wait until falling_edge(clk);
		nmi_n <= '1';
		rdy <= '1';
		for i in 0 to 3000 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			if address(15 downto 0) = x"9000" and rw_n = '1' then
				found_nmi_pc := true;
				exit;
			end if;
		end loop;
		assert found_nmi_pc report "T65 did not fetch synthetic NMI vector target" severity failure;
		report "PASS selected T65 captures paused NMI and vectors after RDY resumes" severity note;
		stop;
		wait;
	end process;
end architecture;
