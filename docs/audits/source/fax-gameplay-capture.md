# FAX startup-to-gameplay reference capture

Date: 2026-10-07. This is a separate 7,200-frame passive MAME capture for FAX and FAX 2. It extends the accepted bank capture with longer delayed input holds and screen snapshots. The Lua observer does not modify program memory, banking, or emulated input state beyond the declared MAME control fields. ROMs and all outputs remain below ignored `simulation/` directories.

## Reproduction

The capture uses `C:\MiSTerDev\mame\mame.exe` (MAME 0.288, SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`) with the staged archives documented in [fax-bank-prom-capture.md](fax-bank-prom-capture.md). The new source is `tools/reference_cases/fax_gameplay_capture.lua`. It taps actual CPU reads at `$1a00`, `$1c00`, and `$5101`, as well as writes at `$2000` and reads in `$2000-$3fff`. For each set it checks every scripted press/release against the corresponding active-low MAME input bit on the following frame, saves snapshots, and exits at frame 7200.

From PowerShell, with the ROM archives staged under `simulation\fax_bank_capture\roms`:

```powershell
$root = 'C:\MiSTerDev\Arcade-Exidy2_MiSTer'
$base = Join-Path $root 'simulation\fax_gameplay_longhold'
$romdir = Join-Path $root 'simulation\fax_bank_capture\roms'
$script = Join-Path $root 'tools\reference_cases\fax_gameplay_capture.lua'
foreach ($set in @('fax', 'fax2')) {
    $run = Join-Path $base $set
    New-Item -ItemType Directory -Force -Path $run, (Join-Path $run 'cfg'), (Join-Path $run 'nvram') | Out-Null
    $env:FAX_BANK_OUT = Join-Path $run 'bank_writes.csv'
    $env:FAX_BUS_OUT = Join-Path $run 'bus_events.csv'
    $env:FAX_EVENT_OUT = Join-Path $run 'events.log'
    $env:FAX_CAPTURE_FRAMES = '7200'
    Push-Location $run
    try {
        & 'C:\MiSTerDev\mame\mame.exe' $set -noreadconfig `
            -rompath "$romdir;C:\MiSTerDev\mame\roms" `
            -cfg_directory (Join-Path $run 'cfg') `
            -nvram_directory (Join-Path $run 'nvram') `
            -video none -sound auto -volume -32 -nothrottle -nosleep -noplugins -skip_gameinfo `
            -autoboot_script $script *> (Join-Path $run 'mame.out')
        if ($LASTEXITCODE -ne 0) { throw "MAME $set exited $LASTEXITCODE" }
    } finally { Pop-Location }
}
```

Both runs exited 0, completed frame 7200, and passed all 18 active-low press/release checks. The scripted sequence leaves the first 3,600 frames untouched, then holds coin for 200 frames, one-player start for 500 frames, and each P1 answer for 200 frames. It repeats coin/start later in the run. Snapshots are under `simulation/fax_gameplay_longhold/{fax,fax2}/snap/`; event logs and bus traces are beside them.

## Observation and limits

Snapshots at intermediate frames show the stand-by/title presentation or a mostly black transition. The frame-7200 snapshots are predominantly black with only top-edge glyphs visible (FAX: “7 E”; FAX 2: “B 6”); neither shows a question or gameplay screen after the delayed long-hold sequence.

The initial 7,200-frame run used `-sound none`. Because another Exidy startup trace advanced only with sound enabled, I repeated the identical Lua driver, frame limit, per-frame input sequence, and ROM archives using `-sound auto -volume -32 -nothrottle -nosleep -noplugins`, with separate configuration/state/output directories under ignored `simulation/fax_gameplay_sound/{fax,fax2}/`. Both sound-enabled runs exited 0, reached frame 7200, and passed the same 18 input checks. For both sets, the bank-write CSV, bus-event CSV, and frame-7200 snapshot are byte-identical to the `-sound none` run. FAX hashes: bank writes `3c30a8f176a4a34f5b8336ff8b7d29c20227515326c2772cfa3871a9246ff7c8`, bus events `99a16044df3b9766ab9a8cf8cafc50a58efcf116c8e9086539fbf72f1c36af6b`, final snapshot `9b33907d7be0ae1d1d909c608f77a96a93516fa43636bd7a172e28089f83d36d`. FAX 2 hashes: bank writes `57c2cbc7b9ce6d9b50254115fe5d981c5b0980b30f8e8f4f3101a78548a0b2d0`, bus events `0ae87ec8be27bf6622d43de7fffffcaf27d31da8094f718d639f63a012998bfe`, final snapshot `65097d75dfd379070eda1d601d06d946f517a6625b2b3e12bd20efeef9c10cf4`. Thus enabling sound did not change the observed title state, input polling, or question-window accesses in this capture. The repeated sound-enabled invocation used the same PowerShell loop above with these additional per-run paths and options:

```powershell
$run = Join-Path $base $set
New-Item -ItemType Directory -Force -Path $run, (Join-Path $run 'cfg'), (Join-Path $run 'nvram'), (Join-Path $run 'input'), (Join-Path $run 'sta'), (Join-Path $run 'home') | Out-Null
& 'C:\MiSTerDev\mame\mame.exe' $set -noreadconfig -nowriteconfig -skip_gameinfo `
    -rompath "$romdir;C:\MiSTerDev\mame\roms" `
    -cfg_directory (Join-Path $run 'cfg') -nvram_directory (Join-Path $run 'nvram') `
    -input_directory (Join-Path $run 'input') -state_directory (Join-Path $run 'sta') `
    -homepath (Join-Path $run 'home') -snapshot_directory $run `
    -video none -sound auto -volume -32 -nothrottle -nosleep -noplugins -autoboot_delay 0 `
    -autoboot_script $script
```

The repeated screen snapshots and bus traces are retained under the separate ignored sound-enabled directories; the prior `-sound none` evidence remains intact for comparison.

The long-hold capture records only three direct `$5101` reads in each set, all during the first 97 frames. Pinned MAME source routes coin 1 through the interrupt-source path: `intsource_coins_r` derives a status bit from active-low IN0 bit 7; vblank latches the source condition; `$5103` returns the latched condition while clearing the IRQ. The FAX2 ISR at `$9456` reads `$5103` and folds status bits into RAM. The initial long-hold capture did not tap `$5103`; the Free Play follow-up below added that tap. See [`exidy.cpp`](../../../simulation/reference_sources/exidy.cpp), functions `intsource_coins_r`, `latch_condition`, `exidy_vblank_interrupt`, and `exidy_interrupt_r`, plus the FAX map and IN0 declaration.

The Free Play follow-up uses the declared MAME Lua DIP API rather than injecting raw port bits. It sets `field.user_value = 0` on the `Bonus Time`, `Game/Bonus Times`, and `Coinage` fields after verifying setting zero is available. The pinned FAX input comment says switches 2–8 ON select Free Play; the CPU later reads `$5100` as `$00`, matching DSW bits 1–7 zero with Coin 2 inactive. The Lua setter is a write to MAME's documented `field.user_value` property; the pinned 0.288 reference also exposes `field.settings[]` indexed by legal DIP value ([MAME Lua input reference](https://github.com/mamedev/mame/blob/mame0288/docs/source/luascript/ref-input.rst#L381-L385)). The setter's immediate port read still showed the pre-frame `$dc`; at frame 1 the effective port was `$00`, and the CPU read `$5100=$00` at frame 17. No unused IN3 bits were set. The separate driver and outputs are `tools/reference_cases/fax_freeplay_capture.lua` and ignored `simulation/fax_gameplay_freeplay_probe2/{fax,fax2}/`.

Reproduce the Free Play capture with the ROM archives staged as above:

```powershell
$root = 'C:\MiSTerDev\Arcade-Exidy2_MiSTer'
$base = Join-Path $root 'simulation\fax_gameplay_freeplay_probe2'
$romdir = Join-Path $root 'simulation\fax_bank_capture\roms'
$script = Join-Path $root 'tools\reference_cases\fax_freeplay_capture.lua'
foreach ($set in @('fax', 'fax2')) {
    $run = Join-Path $base $set
    New-Item -ItemType Directory -Force -Path $run, (Join-Path $run 'cfg'), (Join-Path $run 'nvram'), (Join-Path $run 'input'), (Join-Path $run 'sta'), (Join-Path $run 'home') | Out-Null
    $env:FAX_BANK_OUT = Join-Path $run 'bank_writes.csv'
    $env:FAX_BUS_OUT = Join-Path $run 'bus_events.csv'
    $env:FAX_EVENT_OUT = Join-Path $run 'events.log'
    $env:FAX_CAPTURE_FRAMES = '7200'
    Push-Location $run
    try {
        & 'C:\MiSTerDev\mame\mame.exe' $set -noreadconfig -nowriteconfig -skip_gameinfo `
            -rompath "$romdir;C:\MiSTerDev\mame\roms" `
            -cfg_directory (Join-Path $run 'cfg') -nvram_directory (Join-Path $run 'nvram') `
            -input_directory (Join-Path $run 'input') -state_directory (Join-Path $run 'sta') `
            -homepath (Join-Path $run 'home') -snapshot_directory $run `
            -video none -sound auto -volume -32 -nothrottle -nosleep -noplugins -autoboot_delay 0 `
            -autoboot_script $script *> (Join-Path $run 'mame.out')
        if ($LASTEXITCODE -ne 0) { throw "MAME $set exited $LASTEXITCODE" }
    } finally { Pop-Location }
}
```

Both Free Play runs exited 0 at frame 7200 with 18/18 input checks passing. Their `$5103` taps each observed exactly one CPU read, frame 17 value `$04`, and no later interrupt-status reads during delayed coin holds. The CPU therefore did not service the latched coin-status port again in this interval; this capture alone cannot tell whether the coin event was masked, unneeded in Free Play, or part of a different state path. The final FAX and FAX 2 snapshots were predominantly black with only top-edge glyphs and showed no question/gameplay state. Free Play removes the default coin-credit requirement from the DSW, but the captured start flow still does not enter gameplay.

In FAX 2, `$1c00` reads at PC `$c6aa` during delayed start holds return `$fd`, so active-low start-1 bit 1 was present on the bus. The pinned ROM disassembly shows `$c69f` first reading `$1c00` and masking bit 2 (`AND #$04`); only when that result is zero does it read again and mask bit 1 (`AND #$02`). The MAME input declaration assigns start 1 to bit 1 and marks bits 3:2 unused. The caller at `$8bad` branches on the helper result: a zero result enters `$8d20`, sets RAM flag `$b3`, and proceeds through the initialization/state path; a nonzero result continues at `$8bb5`. Therefore bit 2 is an actual ROM control-flow gate: with the MAME-default high bit 2, `$c69f` skips the start-1 test; with bit 2 low and start 1 low, the helper returns zero and selects the alternate path. A later `$c6aa` call at `$8dbf` also branches on bit 2. This establishes a special two-bit branch in the ROM, but the disassembly does not identify whether it is a start/test prerequisite, a hidden control, or a mismatch in MAME's `IPT_UNUSED` declaration. The capture cannot classify its intended user-facing meaning, and no unused input was forced. Disassembly is retained only under ignored `simulation/fax_gameplay_sound/fax2/`; no ROM bytes are included in tracked files.

The FAX 2 bank-24 write at frame 3444 is followed immediately by the next selector write at frame 3450, with zero question-window reads between them. FAX does not select bank 24 in this run. No out-of-range question-ROM read was observed, and the capture does not establish bank-24 behavior beyond the prior startup observation. Bank selection alone is not evidence of gameplay coverage.

This remains a reference capture, not a full game-support or production-RTL validation. No production RTL, MRA, QIP, or Quartus work was performed.

Independent root checks confirm both long-hold/sound-enabled trace pairs match and their 18 input checks complete without errors. The root also replayed FAX2 Free Play in fresh ignored `simulation/fax_freeplay_root/fax2/`: 18 checks pass, completion at7200, CPU DSW reads return00, and the only IRQ-status read is frame17/value04. A zero MAME process exit alone is insufficient: each reproduction must also require `complete frame=7200`, no `ERROR` in its event log and all18 input checks, because a Lua failure can request a normal emulator exit.
