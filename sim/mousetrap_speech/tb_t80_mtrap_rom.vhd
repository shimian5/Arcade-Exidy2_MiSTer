library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_t80_mtrap_rom is end;

architecture sim of tb_t80_mtrap_rom is
  type rom_t is array (0 to 16#3fff#) of std_logic_vector(7 downto 0);
  impure function load_rom return rom_t is
    file f : text open read_mode is "../expansion_adapter/rom-images/mtrap.hex";
    variable l : line;
    variable b : std_logic_vector(7 downto 0);
    variable m : rom_t;
  begin
    for i in m'range loop
      assert not endfile(f) report "Mouse Trap speech image ended before 16 KiB" severity failure;
      readline(f, l);
      hread(l, b);
      m(i) := b;
    end loop;
    assert endfile(f) report "Mouse Trap speech image contains more than 16 KiB" severity failure;
    return m;
  end function;
  constant rom : rom_t := load_rom;

  signal clk : std_logic := '0';
  signal reset : std_logic := '1';
  signal addr : std_logic_vector(15 downto 0);
  signal datai, datao : std_logic_vector(7 downto 0);
  signal m1, mem_rd, mem_wr, io_rd, io_wr, intack, wait_n : std_logic;
  signal rom_valid : std_logic := '0';
  signal rom_pending : std_logic := '0';
  signal rom_data : std_logic_vector(7 downto 0) := x"FF";
  signal done : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  cpu : entity work.Z80
    port map (
      clk => clk, clk_en => '1', reset => reset,
      addr => addr, datai => datai, datao => datao,
      m1 => m1, mem_rd => mem_rd, mem_wr => mem_wr,
      io_rd => io_rd, io_wr => io_wr, wait_n => wait_n,
      busrq_n => '1', intreq => '0', intvec => x"FF",
      intack => intack, nmi => '0'
    );

  process(clk, reset)
  begin
    if reset = '1' then
      rom_valid <= '0'; rom_pending <= '0'; rom_data <= x"FF";
    elsif rising_edge(clk) then
      if mem_rd = '1' and io_rd = '0' then
        if rom_pending = '0' then
          rom_data <= rom(to_integer(unsigned(addr(13 downto 0))));
          rom_valid <= '1'; rom_pending <= '1';
        end if;
      else
        rom_valid <= '0'; rom_pending <= '0';
      end if;
    end if;
  end process;

  wait_n <= '1' when mem_rd = '0' or io_rd = '1' or rom_valid = '1' else '0';
  datai <= x"FF" when io_rd = '1' else rom_data;

  process
  begin
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    wait until falling_edge(clk); reset <= '0';
    wait until done = '1';
    report "PASS actual T80 initial fetch from verified Mouse Trap speech image" severity note;
    wait;
  end process;

  process
    type address_list_t is array (natural range <>) of natural;
    constant expected_reads : address_list_t := (0, 1, 2, 3, 4, 5);
    variable read_count : natural := 0;
    variable write_count : natural := 0;
    variable held_address : std_logic_vector(13 downto 0) := (others => '0');
    variable previous_io_wr : std_logic := '0';
  begin
    loop
      wait until rising_edge(clk);
      if reset = '1' then
        read_count := 0; write_count := 0; previous_io_wr := '0';
      else
        if mem_rd = '1' and io_rd = '0' then
          if rom_pending = '0' then
            assert read_count < expected_reads'length
              report "ROM fetch advanced beyond first instruction sequence before OUT" severity failure;
            assert addr(13 downto 0) = std_logic_vector(to_unsigned(expected_reads(read_count), 14))
              report "unexpected Mouse Trap initial fetch index=" & integer'image(read_count) &
                " address=$" & to_hstring(addr) severity failure;
            held_address := addr(13 downto 0);
            read_count := read_count + 1;
          else
            assert addr(13 downto 0) = held_address
              report "T80 changed address while actual-ROM response was pending" severity failure;
          end if;
        end if;
        if io_wr = '1' and previous_io_wr = '0' then
          assert read_count = expected_reads'length
            report "first I/O write occurred before the expected initial ROM bytes were fetched" severity failure;
          assert addr = rom(3) & rom(5) and datao = rom(3)
            report "first OUT address/data did not match immediate operands fetched from image" severity failure;
          write_count := write_count + 1;
          done <= '1';
        end if;
        previous_io_wr := io_wr;
      end if;
      wait for 1 ns;
      if done = '1' then wait; end if;
    end loop;
  end process;

  process
  begin
    wait for 20 us;
    assert done = '1' report "actual-ROM T80 initial-fetch fixture timed out" severity failure;
  end process;
end architecture;
