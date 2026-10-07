# Local Venture 6840 replay (2026-10-07)

## Result

The bounded Venture timer replay passed for all three modeled 6840 channels. MAME 0.288 captured a 59.96-second run with scripted coin/start/right/button input. A contiguous two-million-module-cycle window containing the first timer programming and subsequent reloads was replayed through a simulation-only copy of the selected VHDL. `compare_pitch.py` measured/expected half-period median ratios of 0.997 on channels 1, 2, and 3. Channel 3's expected period includes the CR3 divide-by-eight prescaler. This verifies the timer-toggle periods against the documented MAME formula for this window; it does not compare a WAV or establish audible waveform/level equivalence.

Correction: the initial readiness note incorrectly concluded that MAME and GHDL were unavailable after checking only PATH and an unprivileged WSL distro listing. The recorded paths in `docs/audits/simulation/w03-smoke.md` and the local reference manifests were the correct discovery route. MAME 0.288 is at `C:\MiSTerDev\mame\mame.exe`; the portable GHDL 6.0.0 package runs in Arch WSL with its bundled `lib` directory in `LD_LIBRARY_PATH`. The ROM at `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)\venture.zip` was read-only on the NAS and copied into the ignored private run directory for reproducibility; its SHA-256 matched after staging. The NAS source was not modified.

## Capture and replay evidence

Private run directory: `simulation/a4-local/venture_20261007_01/` (ignored). MAME exited with status 0 and its log reports average speed 2124.52% over 59 seconds. The capture contains 4,932 raw writes; the converter selected 3,840 timer (`$2800-$2fff`) and effect-control (`$3000-$37ff`) events. The stimulus ends at module cycle 50,787,549. The full capture and full unshifted stimulus remain in the run directory.

The raw capture also includes 1,073 writes to `$1800-$1fff`, which the existing converter intentionally excludes from this 6840 replay. This address range maps to the 8253 and MAME forwards the decoded offset/data to the PIT (`simulation/reference_sources/exidysound.cpp:368-376,568-569`). Of those writes, offsets 0/1/2/3 received 190/146/160/577 writes. Decoding the 577 offset-3 control words using the 8253 layout (bits 7:6 channel, 5:4 access mode, 3:1 mode, bit 0 BCD) gives channel selects 0/1/2 at 213/185/179 writes, all access mode `11` (LSB then MSB), BCD=0, and effective modes 0/3 at 329/248 writes. Raw mode `111` aliases mode 3; no other mode or read-back/latch command was observed. This is a capture inventory only; the 8253 was not replayed or validated in this task.

The bounded GHDL run used a contiguous window beginning at original stimulus cycle 31,447,331, the first timer-programming event. The checked-in `tools/audio_6840/window_stimulus.py` retains events from that cycle through the following 2,000,000 cycles, subtracts the common start value, and preserves all inter-event spacing. It verifies against the complete stimulus history that the window starts before any 6840 period/MSB write and that the timer control/MSB/period state reconstructed from reset matches the full-history state at the first period load (cycle 31,449,257, register 3): control `(130,130,130)`, MSB `0`, periods `(0,0,0)`. Ten earlier events are omitted; they do not program those timer registers. This is a quiet-prefix reset assumption for timer-period replay, not a claim that omitted noise-generator phase or all prior board state is reproduced. The resulting `stim_window_guarded.txt` has 947 events and ends at relative cycle 1,965,273. The testbench simulated cycles 0 through 2,000,000 with `CLK_DIV=1`; GHDL exited 0 and wrote 36,752 complete output-toggle records.

Measured results from `tools/audio_6840/compare_pitch.py`:

| Channel | Comparable half-periods | Measured / expected median | Min–max |
|---|---:|---:|---:|
| 1 | 3,443 | 0.997 | 0.997–1.027 |
| 2 | 2,410 | 0.997 | 0.997–1.001 |
| 3 | 8,057 | 0.997 | 0.997–1.001 |

The scale is consistent with the documented source-clock difference: the RTL module input is nominally 14.366883 MHz / 16, while the comparison formula uses MAME's 3.579545 MHz / 4 E clock. The exact measured ratio comes from captured integer-cycle spacings and the comparator's nominal module period.

An initial unwindowed 50,787,549-cycle attempt was not used: its output ended mid-record at cycle 11,573,878 and did not reach the requested capture end. The partial file is preserved as `toggles.txt` for audit; `toggles_replay.txt` is the complete accepted replay result.

## Simulation-only model initialization

The production `modules/6840/berzerk_sound_fx.vhd` was left unchanged. Checked-in `tools/audio_6840/prepare_sim_model.py` generates a private copy only if the source SHA-256 and exact text anchors match, then initializes 16 state declarations otherwise uninitialized in simulation. `hdiv`, load strobes, prescaler, and noise shift register already have source initializers. Reset initializes the control and volume registers before replay. This prevents GHDL's `'U'` startup behavior from contaminating the first timer interval. It is a guarded simulation startup aid, not a production RTL change or a Quartus/silicon claim.

## Exact commands

PowerShell MAME capture (environment variables are set immediately before the invocation; outputs and all MAME writable directories are under the ignored run directory):

```powershell
$run = 'C:\MiSTerDev\Arcade-Exidy2_MiSTer\simulation\a4-local\venture_20261007_01'
$env:SFX_OUT = Join-Path $run 'venture_sfx.csv'
$env:SFX_FRAMES = '3600'
$env:SFX_INPUT = '1'
$env:SFX_START = '2100'
& 'C:\MiSTerDev\mame\mame.exe' venture -noreadconfig -nowriteconfig -skip_gameinfo `
  -rompath '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)' `
  -cfg_directory (Join-Path $run 'cfg') -nvram_directory (Join-Path $run 'nvram') `
  -input_directory (Join-Path $run 'input') -state_directory (Join-Path $run 'state') `
  -diff_directory (Join-Path $run 'diff') -comment_directory (Join-Path $run 'comment') `
  -homepath (Join-Path $run 'home') -snapshot_directory $run `
  -video none -sound none -nothrottle -nosleep -noplugins -autoboot_delay 0 `
  -autoboot_script 'C:\MiSTerDev\Arcade-Exidy2_MiSTer\tools\audio_6840\mame_sfx_capture.lua' `
  -seconds_to_run 64 *> (Join-Path $run 'mame.stdout-stderr.log')
```

The remaining Windows-side commands were:

```powershell
python tools/audio_6840/gen_stimulus.py `
  simulation/a4-local/venture_20261007_01/venture_sfx.csv `
  simulation/a4-local/venture_20261007_01/stim.txt
python tools/audio_6840/prepare_sim_model.py `
  --source modules/6840/berzerk_sound_fx.vhd `
  --output simulation/a4-local/venture_20261007_01/berzerk_sound_fx_guarded.vhd
python tools/audio_6840/window_stimulus.py `
  --input simulation/a4-local/venture_20261007_01/stim.txt `
  --output simulation/a4-local/venture_20261007_01/stim_window_guarded.txt `
  --start-cycle 31447331 --span-cycles 2000000
```

The successful GHDL replay and pitch comparison were:

```powershell
Copy-Item sim/audio_6840/tb_sfx_vhdl.vhd simulation/a4-local/venture_20261007_01/tb_sfx_vhdl.vhd
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/a4-local/venture_20261007_01; export LD_LIBRARY_PATH=/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -a --std=08 -fsynopsys -frelaxed berzerk_sound_fx_guarded.vhd tb_sfx_vhdl.vhd'
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/a4-local/venture_20261007_01; export LD_LIBRARY_PATH=/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl --elab-run --std=08 -fsynopsys -frelaxed tb_sfx_vhdl -gSTIM=stim_window_guarded.txt -gOUTF=toggles_replay.txt -gCYCLES=2000000 -gCLK_DIV=1'
python tools/audio_6840/compare_pitch.py `
  simulation/a4-local/venture_20261007_01/stim_window_guarded.txt `
  simulation/a4-local/venture_20261007_01/toggles_replay.txt
```

## Fingerprints and limits

| Item | SHA-256 / version |
|---|---|
| MAME executable | 0.288 (`mame0288`); `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182` |
| GHDL executable | 6.0.0 mcode; `C7D63E138A5F2EDB40C50F523465462D0BD707A8E2FF43C76A72AE5D393EAB55` |
| Staged `rom/venture.zip` (NAS source and staged copy match) | `AF340219D7FA4BF9D0A2A9FFABA7053189A6A2542D63B8CF2D3B74358DB72BCD` |
| Production VHDL source | `CC8A67374B764B4DB58B6FF4509BBA742F2469070F26FFC0E655AC501156BAB7` |
| Simulation-initialized VHDL copy | `B9ED6A4222D5FFC29E9FEF3DB3FFB28BC7E2603800E3CE4115654FD7F1138276` |
| Testbench source/copy | `A14EDC46FF098E397D5BA8B3885EFBC5F3C92CD853A697CA32CC76DE6B4E63CD` |
| Capture Lua | `21EDA73212DDD8C9AFB9C35F2D6D53AE6E8BBD0E0DF9F2070B68E504BC983240` |
| Stimulus converter | `BF4E78DA2AD772D18035EB8431152D0215F5191D3DF1933432B80F75EBE0D865` |
| Pitch comparator | `86A5D8E733FE9A68BBAED32C7DFEB239167F9780A73EB5204634AC452DB1FE88` |
| Captured CSV | `E583557848BA015360C4D545DF2933FB78BAC88AD74DB305091BC6BA88B33AED` |
| Full stimulus | `DCE0E49DA8BD150173A5EF3433318708D04FA9BA9BD85FF0CFA5E87DEF59834A` |
| Window stimulus | `2F63E49F57633489346495669F92185C9FA6E2C9C03B1912F32C1BF567A7CCAB` |
| Window toggle output | `47D4795932B480BCAD044D9123E0D88FC583ACF4F1CE764B60232FF865A13E6E` |
| Guarded simulation-model generator | `119B02EC627265E369461277D2562AA3AFFD3038F35CD6F7DDF528E7E8F64C59` |
| Window-stimulus generator | `71872A907DB90B7EB4CB15AC87A149445702D86C7386168A75D44B5B69C85BD4` |
| Windowed guarded simulation VHDL | `B9ED6A4222D5FFC29E9FEF3DB3FFB28BC7E2603800E3CE4115654FD7F1138276` |
| `exidy.cpp` / `exidysound.cpp` source revision files | `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486` / `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660` |

The source revision files are the pinned MAME 0.288 references already present in `simulation/reference_sources`; the executable version is recorded separately. The two-million-cycle window validates timer output periods only where the comparator has a stable configured period. It does not exercise all 60 seconds of state history, all Exidy profiles, whole-board CPU/PIA transactions, noise equivalence, audio mixing, or sound output quality. MAME was run with sound output disabled for headless capture, and no WAV was generated or compared. Production VHDL, the source testbench, ROM path, and Quartus project were unchanged; two reproducible helper scripts were added under `tools/audio_6840`. No Quartus build was run.
