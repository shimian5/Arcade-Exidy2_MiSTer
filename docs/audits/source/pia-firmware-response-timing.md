# PIA firmware response and read timing

This capture samples real MAME CPU bus activity at both 6821 PIA interfaces for Venture, Pepper II, Hard Hat, and Mouse Trap. It shows sustained firmware polling/response traffic in Venture and Mouse Trap, with only one returned byte observed in Pepper II and Hard Hat during the tested interval. The evidence supports a software-level response-hold margin for the exercised bytes; it does not establish the FPGA synchronizer’s setup/hold margin or certify every game state.

## Source mapping and clocks

The local pinned MAME snapshot defines the main board crystal as 11.289 MHz and its 6502 clock as `EXIDY_MASTER_CLOCK / 16` (`simulation/reference_sources/exidy.cpp:169-170,1511`). Venture, Pepper II, and Mouse Trap map the main PIA at `$5200-$520f` (`exidy.cpp:575,584,589-592`). Hard Hat’s game declaration selects the Pepper II machine configuration (`exidy.cpp:2614`), which inherits the same PIA mapping. On the sound board, the audio CPU maps its PIA at `$1000-$1003`, mirrored through `$17ff` (`simulation/reference_sources/exidysound.cpp:562-568`); its CPU runs at 3.579545 MHz / 4 (`exidysound.cpp:582-586`).

The source callback cross-wiring confirms the byte direction: sound-board PB output calls `porta_w` on the main PIA, so sound `$1002` writes feed main `$5200` reads; the reverse port callbacks carry main PB to sound PA (`simulation/reference_sources/exidy.cpp:1614-1622,1653-1661`). The PIA CA2/CB2 signals also cross-connect to the other PIA’s CA1/CB1 inputs, as in `rtl/audio_board.v:118-176`.

The Exidy core accepts `master_clock` and `audio_clk` at its top-level ports. `PH_1` is generated once per 64 `master_clock` cycles and enables the main T65 (`rtl/Exidy2.v:16,105,187-188`); the main-side PIA itself clocks from `master_clock` (`rtl/audio_board.v:118-120`). The audio-side PIA clocks from `audio_clk` (`audio_board.v:149-153`), while `auPH0` enables its T65 once per 16 audio-clock cycles (`audio_board.v:36-54`). The instantiated PLL IP declares 45.153061 MHz output 0 and 14.366883 MHz output 2 (`rtl/pll/pll_0002.v:28,34`); these are generated-IP source settings, not a fitter or hardware measurement. They imply approximately 705.5166 kHz main-CPU enable and 897.9302 kHz audio-CPU enable. MAME’s corresponding source clocks imply 705.5625 kHz and 894.8863 kHz. MAME and FPGA nominal audio rates therefore differ by about 0.34%; elapsed MAME seconds are useful for software sequencing and scale, not an exact model of the FPGA clock phase.

## Capture method and provenance

`tools/pia_firmware_timing/mame_pia_capture.lua` installs passive read/write taps on the main PIA range `$5200-$520f` and mirrored sound PIA range `$1000-$17ff`. It does not change memory, register values, or PIA signals. CSV timestamps are MAME emulation time in seconds. Register 0/2 accesses are classified as DDR or data according to the most recent write to CRA/CRB bit 2; control-register data and CPU PC are retained. `pia-events.log` records control-register writes and the scripted input times. Status reads remain in the raw CSV: values such as `AC` show bit 7 asserted in the sampled PIA control status; the tap does not directly timestamp the external CA2/CB2 pin edge.

Reproduction command, run from PowerShell with the configured NAS ROM path available:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/pia_firmware_timing/run_capture.ps1 -Run 20261007_03 -Seconds 120
```

The runner verified each ROM set with MAME `-verifyroms`, then ran with `-video none -sound none -nothrottle -nosleep -noplugins -skip_gameinfo`; it wrote configuration, captures, and logs only under ignored `simulation/pia_firmware_timing/20261007_03/`. Lua pressed Coin 1 on frames 1920-1949 and 1 Player Start on frames 2040-2069 (about 32 s and 34 s), when the controls are available in that game’s `:IN0` port. Each run reached frame 7200 / 120.023 seconds and exited successfully. This intentionally avoids the earlier preliminary pass whose coin/start pulses occurred during boot.

Environment and source fingerprints recorded in the ignored run manifest:

- MAME `0.288 (mame0288)`, executable SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`.
- ROM library: `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)`; pinned MAME source commit recorded as `27a8d9e85b58058965907d1d8a7a92f8ed039348`.
- `exidy.cpp` SHA-256 `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486`; `exidysound.cpp` SHA-256 `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660`.
- Lua SHA-256 `DC7134FC43C4FA446E4CC8D27DCBEBC7A0207617643CE42C53FF3DB53FF55EC8`; runner SHA-256 `EE633080250E2AE7D57983BB935C69693CC6157732F7B97E913B00C0E8E2FEE5`.

All four ROM archives passed verification. The archive SHA-256 values and individual exit codes are in `simulation/pia_firmware_timing/20261007_03/manifest.json`.

## Results

For each sound PB data write, the analysis finds the first subsequent main PA data read before a later sound PB data write, then compares the byte values. A write with no such read is counted as overwritten before read. This captures bus-level firmware behavior rather than assuming that every output write requires an acknowledgement.

The reusable analyzer is `tools/pia_firmware_timing/analyze_capture.py`. It reconstructs the written CRA/CRB and DDRA/DDRB state from the CSV; only PB writes with PB data selected and DDRB=`0xff`, and PA reads with PA data selected and DDRA=`0x00`, qualify as full-byte transfers. It preserves raw read-before-overwrite, byte-match, and mismatch counts separately. Recreate the report JSON and compare run 3 with the prior identical-input capture using:

```powershell
python tools/pia_firmware_timing/analyze_capture.py `
  --run-dir simulation/pia_firmware_timing/20261007_03 `
  --compare-run-dir simulation/pia_firmware_timing/20261007_02 `
  --output simulation/pia_firmware_timing/analysis/20261007_03.json
```

The comparison finds all four bus CSV hashes identical, all ROM archive hashes identical, and matching MAME version/binary, pinned source, source hashes, run duration, inputs, and ROM root. The Lua script hashes differ because the repeated capture reduced only auxiliary event-log verbosity; the byte-identical bus CSVs confirm no change in captured bus behavior. The output JSON is generated under ignored `simulation/` and is not part of the source changes.

| Game | Sound PB data writes | Main PA reads | Read before overwrite | Matching first reads | Differing first reads | Writes overwritten first |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Venture | 5,790 | 5,795 | 5,133 | 5,126 | 7 | 657 |
| Pepper II | 1 | 3 | 1 | 1 | 0 | 0 |
| Hard Hat | 1 | 3 | 1 | 1 | 0 | 0 |
| Mouse Trap | 88 | 89 | 88 | 88 | 0 | 0 |

Matching first-read delay from the output PB write was 11.572 µs minimum, 457.130 µs median, and 769.536 µs at the 95th percentile in Venture. Mouse Trap’s corresponding delays were 17.009 µs minimum and 43.512 µs median; its long tail reflects sparse output changes (one read followed the last write after about 1.86 s). The single Pepper II and Hard Hat matches occurred 1.181 ms and 12.120 ms after the output writes. Their 120-second captures show startup/limited exchange only, not sustained game-response coverage.

The raw trace records repeated control-status polling and data reads in the active cases. In Venture, main/audio control reads with bit 7 set (`AC`) occurred 11,661/11,660 times; Mouse Trap had 271/263 such sampled status reads. The byte-level trace shows the response and read in order. For example, Venture writes `0x47` at sound `$1002` at 36.737333023 s, reads status `0xAC` at main `$5201` at 36.737402241 s, then reads `0x47` at main `$5200` at 36.737412162 s: a 79.139 µs write-to-read interval. This status evidence reflects latched PIA IRQ/status as observed by firmware, not a direct logic-analyzer measurement of pin transitions.

Venture’s seven differing first reads returned `0x40` after a sound PB write of `0x00`; these are retained as mismatches, not normalized away. The 657 writes followed by another PB write before a main PA data read also remain visible. Mouse Trap’s 88 returned PB values were all `0x00`, so it validates read-after-write timing for that value but not diverse payloads. Pepper II and Hard Hat each produced one matching zero byte only. These results do not prove complete command coverage for those games.

The candidate two-register return path is estimated at about 92 ns additional latency. That is roughly 126 times smaller than Venture’s shortest measured matching MAME write-to-read delay. This is a useful protocol-scale observation, not a timing signoff: MAME’s 6821 model is not the FPGA RTL, its nominal audio clock differs slightly, the observed trace contains exceptions and overwritten writes, and no physical setup/hold or metastability behavior is represented.

## Trace fingerprints and limits

Run 3 bus CSV SHA-256 values:

| Game | SHA-256 |
| --- | --- |
| Venture | `777A84E05FAD450EF18C6C1768FB220AC09603ABF0F161919BDDD9C773CA64AA` |
| Pepper II | `D06E94909FDE58AE7D384F3ACC06D62ECFD67C054F03B96A01E6F84D74530650` |
| Hard Hat | `A89423EA86B1578AADF40DCBC895255F48B3E438A2FCD639120EB2D0A61B3823` |
| Mouse Trap | `741FAAC45DDCDDA841D4C6AE60B69B0301B612175347C4FB0A227EB7A6DD8055` |

An independent repeated capture with identical 120-second input schedule produced byte-identical bus CSVs for all four sets. Only the auxiliary event log was reduced to control writes to keep it small; the raw bus trace and measured results were unchanged.

The taps observe CPU accesses and latched status returned by MAME. They do not expose exact PIA output pin transition times, guarantee a particular attract/gameplay path, or test the proposed two-stage RTL. The Venture mismatch/overwrite cases and limited Pepper II/Hard Hat traffic are explicit follow-up limits. No Quartus build, ROM modification, or production RTL edit was part of this audit.
