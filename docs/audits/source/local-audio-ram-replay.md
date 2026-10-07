# Local audio RAM mirror replay — 2026-10-07

Generated fresh ordered audio-CPU RAM-window traces using the repository's `tools/reference_cases/audio_ram_seq.lua`, then replayed them through the checked audio RAM map and its flat-map negative control. All ROM archives, traces, private MAME configuration/NVRAM, and command logs are under ignored `simulation/a2-local/`; no ROMs, captures, or test output are tracked.

## Inputs and reproducibility

- MAME: `C:\MiSTerDev\mame\mame.exe`, version `0.288 (mame0288)`, SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`.
- ROM source: NAS split set directory `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)`. Each archive was copied read-only to ignored `simulation/a2-local/roms/` and verified against its source SHA-256. The 0.257 ROM sets are older than the 0.288 emulator; MAME `-verifyroms venture pepper2 mtrap` reported all three sets good.
- Each game ran from its own ignored working directory with its own `cfg` and `nvram` directories. The launch used `-video none -sound none -nothrottle -skip_gameinfo -noreadconfig`, the staged ROM path, and `-autoboot_script` pointing to the repository Lua script. `AUD_FRAMES=900` and `AUD_OUT=simulation/a2-local/seq_<game>.csv` were set for each invocation. The script closes the trace and calls `machine:exit()` when its frame counter reaches 900; all three MAME processes exited 0 and produced nonempty traces.

ROM SHA-256 values (NAS source and staged copy matched exactly):

| ROM | SHA-256 |
| --- | --- |
| `venture.zip` | `AF340219D7FA4BF9D0A2A9FFABA7053189A6A2542D63B8CF2D3B74358DB72BCD` |
| `pepper2.zip` | `CFD6A4B2A2DEBB10229DA36BAD4370B6CCAFF9B6C5EEE413FEFC8012B5633C6B` |
| `mtrap.zip` | `4F87B2C49FCEE00B2A4B7ACD4227EA50229C622F8ADBD4F840B8630EFB55EEE6` |

Trace SHA-256 values:

| Trace | SHA-256 |
| --- | --- |
| `seq_venture.csv` | `C996FB3FDA1B1A1D728DFB50FA2D1E3B7C94D47726967C6BD49395C855DE076B` |
| `seq_pepper2.csv` | `9BD55FF468AEB93F0E170323CB182922F27AAE5F65A8EC37CE03206EE77B86DC` |
| `seq_mtrap.csv` | `621CE10D0A48ADC751E47FD020859A82CD40636A0D93B132157FDB763CFAD009` |

## Trace coverage and replay result

| Game | Rows | Reads | Writes | Read addresses | Write addresses | Address range | Mirror mismatches |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Venture | 3,158,349 | 1,830,000 | 1,328,349 | 269 | 265 | `$0000`–`$01FF` | 0 |
| Pepper II | 3,201,660 | 1,926,530 | 1,275,130 | 269 | 265 | `$0000`–`$01FF` | 0 |
| Mouse Trap | 3,254,348 | 1,969,769 | 1,284,579 | 269 | 265 | `$0000`–`$01FF` | 0 |

All three traces contain substantial nonzero reads and writes and touch addresses above `$007F`, so these runs exercise aliases in the first `$0200` bytes of the audio CPU's RAM window. The map uses `cpu_addr[6:0]` to implement the 128-byte 6532 RAM mirror. These finite traces do not exercise the full `$0000`–`$07FF` window, every address or write/read ordering, all firmware/game states, or prove game-wide correctness.

Mouse Trap's flat-map negative control produced 6,188 read mismatches, while the mirror map produced none. This confirms the sampled Mouse Trap accesses distinguish the mirror behavior from a flat 2 KB address map.

Runner command, run inside WSL Arch Linux:

```sh
python3 -u tools/run_tests.py --traces /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/a2-local
```

Verilator was 5.052. Exit status was 0; the runner reported 11 results: 11 PASS, 0 FAIL, 0 SKIP. This included the three RAM mirror replays and the expected Mouse Trap flat-map failure control. No production RTL or harness changes were needed, and no Quartus run was part of this replay.
