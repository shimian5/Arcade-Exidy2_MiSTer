-- Replays timestamped 6840/sfxctrl writes into the production berzerk_sound_fx (VHDL) and
-- logs "cycle xor-mask" for output toggles of the three timer outputs. VHDL-2008 external names.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.textio.all;
entity tb_sfx_vhdl is
  generic (STIM : string := "stim.txt"; OUTF : string := "toggles.txt"; CYCLES : integer := 1000000; CLK_DIV : integer := 4);
end entity;
architecture sim of tb_sfx_vhdl is
  signal clock : std_logic := '0'; signal reset : std_logic := '1';
  signal cs, vs : std_logic := '0'; signal addr : std_logic_vector(2 downto 0) := "000";
  signal di : std_logic_vector(7 downto 0) := (others => '0');
  signal sample : std_logic_vector(11 downto 0);
  signal s1, s2, s3 : signed(8 downto 0);
begin
  dut : entity work.berzerk_sound_fx generic map (CLK_DIV => CLK_DIV) port map (clock, reset, cs, vs, addr, di, sample, s1, s2, s3);
  process
    file fs : text open read_mode is STIM; file fo : text open write_mode is OUTF;
    variable l : line; variable nc, nk, nr, nd, cyc : integer := 0; variable have : boolean := true;
    variable qp, qn, x : std_logic_vector(2 downto 0) := "000"; variable ol : line; variable xi : integer;
    alias q1 is << signal .tb_sfx_vhdl.dut.ptm6840_q1 : std_logic >>;
    alias q2 is << signal .tb_sfx_vhdl.dut.ptm6840_q2 : std_logic >>;
    alias q3 is << signal .tb_sfx_vhdl.dut.ptm6840_q3 : std_logic >>;
    procedure nextline is begin
      if endfile(fs) then have := false; else readline(fs, l); read(l, nc); read(l, nk); read(l, nr); read(l, nd); end if; end procedure;
  begin
    nextline; wait for 20 ns; reset <= '0';
    for i in 0 to CYCLES loop
      cyc := i; clock <= '1'; cs <= '0'; vs <= '0';
      if have and nc <= cyc then
        addr <= std_logic_vector(to_unsigned(nr, 3)); di <= std_logic_vector(to_unsigned(nd, 8));
        if nk = 0 then cs <= '1'; else vs <= '1'; end if;
        nextline;
      end if;
      wait for 5 ns;
      qn := q3 & q2 & q1;
      if qn /= qp then
        x := qn xor qp; xi := to_integer(unsigned(x));
        write(ol, integer'image(cyc) & " " & integer'image(xi)); writeline(fo, ol); qp := qn;
      end if;
      clock <= '0'; wait for 5 ns;
    end loop;
    wait;
  end process;
end architecture;
