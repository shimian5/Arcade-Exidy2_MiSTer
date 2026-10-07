library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_t80_sync_rom is end;

architecture sim of tb_t80_sync_rom is
  type rom_t is array (0 to 16#3fff#) of std_logic_vector(7 downto 0);
  function make_rom return rom_t is
    variable m : rom_t := (others => x"00");
  begin
    -- LD A,12; OUT (21),A; IN A,(22); OUT (23),A;
    -- LD A,(0100); LD (2000),A; HALT.
    m(16#0000#) := x"3E"; m(16#0001#) := x"12";
    m(16#0002#) := x"D3"; m(16#0003#) := x"21";
    m(16#0004#) := x"DB"; m(16#0005#) := x"22";
    m(16#0006#) := x"D3"; m(16#0007#) := x"23";
    m(16#0008#) := x"3A"; m(16#0009#) := x"00";
    m(16#000A#) := x"01"; m(16#000B#) := x"32";
    m(16#000C#) := x"00"; m(16#000D#) := x"20";
    m(16#000E#) := x"76";
    m(16#0100#) := x"A5";
    return m;
  end function;
  constant rom : rom_t := make_rom;

  signal clk : std_logic := '0';
  signal clk_en : std_logic := '1';
  signal reset : std_logic := '1';
  signal addr : std_logic_vector(15 downto 0);
  signal datai, datao : std_logic_vector(7 downto 0);
  signal m1, mem_rd, mem_wr, io_rd, io_wr, intack : std_logic;
  signal wait_n : std_logic;
  signal rom_valid : std_logic := '0';
  signal rom_pending : std_logic := '0';
  signal rom_data : std_logic_vector(7 downto 0) := x"FF";
  signal rom_addr_q : std_logic_vector(13 downto 0) := (others => '0');
  signal done : std_logic := '0';
begin
  clk <= not clk after 5 ns;

  cpu : entity work.Z80
    port map (
      clk => clk, clk_en => clk_en, reset => reset,
      addr => addr, datai => datai, datao => datao,
      m1 => m1, mem_rd => mem_rd, mem_wr => mem_wr,
      io_rd => io_rd, io_wr => io_wr, wait_n => wait_n,
      busrq_n => '1', intreq => '0', intvec => x"FF",
      intack => intack, nmi => '0'
    );

  -- A one-edge synchronous ROM. The sampled address and response remain held
  -- until the CPU drops the memory-read strobe after accepting the byte.
  process(clk, reset)
  begin
    if reset = '1' then
      rom_valid <= '0';
      rom_pending <= '0';
      rom_addr_q <= (others => '0');
      rom_data <= x"FF";
    elsif rising_edge(clk) then
      if mem_rd = '1' and io_rd = '0' then
        if rom_pending = '0' then
          rom_addr_q <= addr(13 downto 0);
          rom_data <= rom(to_integer(unsigned(addr(13 downto 0))));
          rom_valid <= '1';
          rom_pending <= '1';
        end if;
      else
        rom_valid <= '0';
        rom_pending <= '0';
      end if;
    end if;
  end process;

  wait_n <= '1' when mem_rd = '0' or io_rd = '1' or rom_valid = '1' else '0';
  datai <= x"5C" when io_rd = '1' else rom_data;

  stimulus : process
  begin
    for i in 1 to 5 loop wait until rising_edge(clk); end loop;
    wait until falling_edge(clk);
    reset <= '0';
    wait until done = '1';
    report "PASS actual T80 reset/fetch/synchronous-ROM/I/O/memory-write sequence" severity note;
    wait;
  end process;

  scoreboard : process
    type address_list_t is array (natural range <>) of natural;
    constant expected_reads : address_list_t := (
      16#0000#, 16#0001#, 16#0002#, 16#0003#, 16#0004#, 16#0005#,
      16#0006#, 16#0007#, 16#0008#, 16#0009#, 16#000A#, 16#0100#,
      16#000B#, 16#000C#, 16#000D#, 16#000E#
    );
    variable read_count, io_read_count, io_write_count, mem_write_count : natural := 0;
    variable wait_samples : natural := 0;
    variable held_address : std_logic_vector(13 downto 0) := (others => '0');
    variable previous_io_rd, previous_io_wr, previous_mem_wr : std_logic := '0';
  begin
    loop
      wait until rising_edge(clk);
      if reset = '1' then
        read_count := 0; io_read_count := 0; io_write_count := 0; mem_write_count := 0;
        wait_samples := 0;
        previous_io_rd := '0'; previous_io_wr := '0'; previous_mem_wr := '0';
      else
        if mem_rd = '1' and io_rd = '0' then
          if rom_pending = '0' then
            if read_count < expected_reads'length then
              assert addr(13 downto 0) = std_logic_vector(to_unsigned(expected_reads(read_count), 14))
                report "unexpected speech ROM fetch address index=" & integer'image(read_count) &
                  " address=$" & to_hstring(addr) severity failure;
            else
              assert addr(13 downto 0) = std_logic_vector(to_unsigned(16#000E#, 14))
                report "unexpected fetch after the program reached HALT" severity failure;
            end if;
            held_address := addr(13 downto 0);
            read_count := read_count + 1;
          else
            assert addr(13 downto 0) = held_address
              report "T80 changed its address while synchronous ROM wait was pending" severity failure;
          end if;
          if rom_valid = '0' then wait_samples := wait_samples + 1; end if;
        end if;

        if io_rd = '1' and previous_io_rd = '0' then
          io_read_count := io_read_count + 1;
          assert wait_n = '1' report "I/O read was incorrectly stalled by ROM wait" severity failure;
          assert addr = x"1222" report "IN A,(n) did not expose expected 16-bit port address" severity failure;
        end if;
        if io_wr = '1' and previous_io_wr = '0' then
          case io_write_count is
            when 0 =>
              assert addr = x"1221" and datao = x"12"
                report "first OUT transaction address/data mismatch" severity failure;
            when 1 =>
              assert addr = x"5C23" and datao = x"5C"
                report "second OUT did not retain the actual T80 I/O read byte" severity failure;
            when others => assert false report "unexpected extra I/O write" severity failure;
          end case;
          io_write_count := io_write_count + 1;
        end if;
        if mem_wr = '1' and previous_mem_wr = '0' then
          assert addr = x"2000" and datao = x"A5"
            report "T80 did not store synchronous-ROM data at $2000" severity failure;
          mem_write_count := mem_write_count + 1;
        end if;

        previous_io_rd := io_rd;
        previous_io_wr := io_wr;
        previous_mem_wr := mem_wr;
        if read_count >= expected_reads'length and io_read_count = 1 and
           io_write_count = 2 and mem_write_count = 1 then
          assert wait_samples > 0 report "synchronous ROM caused no T80 wait sample" severity failure;
          done <= '1';
        end if;
      end if;
      wait for 1 ns;
      if done = '1' then wait; end if;
    end loop;
  end process;

  watchdog : process
  begin
    wait for 100 us;
    assert done = '1' report "T80 synchronous-ROM fixture timed out" severity failure;
  end process;
end architecture;
