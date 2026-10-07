# FAX / FAX 2 passive bank-select capture

Date: 2026-10-07. This audit includes an initial 900-frame check and a separate 3,600-frame follow-up using pinned MAME 0.288 and the local FAX/FAX 2 ROM archives staged under ignored `simulation/fax_bank_capture/roms/`. The Lua taps observe actual CPU accesses and never write memory or change bank state. No ROM bytes or capture output are tracked.

## Method and reproducibility

`tools/reference_cases/fax_bank_capture.lua` installs a write tap at `$2000`, read taps over the question window `$2000-$3fff`, and read taps at answer inputs `$1a00`/`$1c00`. The 3,600-frame run schedules repeated coin/player-start events and each of the four answer controls for both players. It checks each scheduled press and release against the expected active-low input bit on the following frame, and saves startup/progress/end snapshots. Captures, snapshots, per-input events, and bank-write CSVs are emitted only below ignored `simulation/fax_bank_capture_long/{fax,fax2}/`.

The field setter behavior is verified against the pinned official MAME `ioport_field::set_value` implementation: it stores `value != 0` as the digital assertion; `ioport_field::frame_update` merges asserted fields into the digital port state, and `ioport_port::read` applies the active-high/low polarity. Thus the script passes `1` for asserted and `0` for released, then checks that the relevant active-low port bit is low/high respectively. The FAX input declarations in pinned `exidy.cpp` use IN3 bits 1/0 for starts and bits 7:4 for P1 answers, with bits 7:4 of IN4 for P2 answers. The 38 scheduled press/release checks in each long run passed. Source references: [MAME 0.288 `ioport.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/emu/ioport.cpp#L1143-L1244) and [`ioport_port::read`](https://github.com/mamedev/mame/blob/mame0288/src/emu/ioport.cpp#L1484-L1507).

The executable is `C:\MiSTerDev\mame\mame.exe`, SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182` (MAME 0.288; source commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`). Staged `fax.zip` SHA-256 is `BE81EC792198E7DF52B828F2DD5668B856225F43BCAE445D5D5795856FD49EDF`; `fax2.zip` is `E744B648D497F38CDAFA19B58B6DBFD67347A22C02B83B29E7866BC14F667C68`.

From PowerShell, with the two archives staged in the ignored directory:

```powershell
$root = 'C:\MiSTerDev\Arcade-Exidy2_MiSTer'
$base = Join-Path $root 'simulation\fax_bank_capture_long'
$romdir = Join-Path $root 'simulation\fax_bank_capture\roms'
$script = Join-Path $root 'tools\reference_cases\fax_bank_capture.lua'
foreach ($set in @('fax', 'fax2')) {
    $run = Join-Path $base $set
    New-Item -ItemType Directory -Force -Path $run, (Join-Path $run 'cfg'), (Join-Path $run 'nvram') | Out-Null
    $env:FAX_BANK_OUT = Join-Path $run 'bank_writes.csv'
    $env:FAX_BUS_OUT = Join-Path $run 'bus_events.csv'
    $env:FAX_EVENT_OUT = Join-Path $run 'events.log'
    $env:FAX_CAPTURE_FRAMES = '3600'
    Push-Location $run
    try {
        & 'C:\MiSTerDev\mame\mame.exe' $set -noreadconfig `
            -rompath "$romdir;C:\MiSTerDev\mame\roms" `
            -video none -sound none -nothrottle -skip_gameinfo `
            -autoboot_script $script
        if ($LASTEXITCODE -ne 0) { throw "MAME $set exited $LASTEXITCODE" }
    } finally { Pop-Location }
}
```

The initial 900-frame run exited 0 for each set and observed no `$2000` writes. Its snapshots were not saved, so that first zero-write observation is superseded by the longer capture below.

Both 3,600-frame invocations exited 0 and reached the requested final frame. FAX produced 82,266 bank-select writes across banks `$00-$16` (decimal 0–22). FAX 2 produced 45,230 writes across banks `$00-$18` (decimal 0–24), including one actual selection of `$18` (24) at frame 3444 (57.421 s, PC `$f9fd`). It therefore exercises one bank value beyond the populated `$00-$17` interval in the 5-bit MAME selector; it is the `$18` case described in the MAME driver's warning condition. Banks `$19-$1f` (25–31) were not observed in these runs. Question-window read counts were 231,666 for FAX and 228,542 for FAX 2. Each run logged 38 passing active-low input checks.

An independent FAX 2 3,600-frame repeat reproduced the 45,230 writes, the bank-24 selector at frame 3444 / 57.421010485 s / PC `$f9fd`, 38 passing input checks, and completion at frame 3600. An independent row-order check also confirmed the bank-24 write at bus row 205,087 is immediately followed by bank 0 at row 205,088, with no intervening question-window reads.

The initial snapshots are black; final snapshots show the FAX title/stand-by screen (“Stand by / FAX Game / Ver 8 / Exidy Inc.”) in both sets. The run did not visibly enter answer/gameplay, so its bank selections establish a startup/title-state observation, not full play-state coverage. Captures and snapshots remain under ignored `simulation/fax_bank_capture_long/{fax,fax2}/`; bank-write CSVs preserve the write timestamps, PCs, raw data, and masked selector values.

## Interpretation

The longer capture demonstrates bank 24 is selected by FAX 2 during the observed startup/title-state sequence. Row order in `bus_events.csv` is the event order: the bank-24 write is row 205,087 (frame 3444, PC `$f9fd`, data `$18`); row 205,088 is the next selector write (frame 3450, PC `$f9bc`, data `$00`). There are **zero question-window reads between those two writes**. Immediately before the bank-24 write, the last eight reads were `$3ff8-$3fff`, all returned `$00` at PC `$f9e7`. These match the final eight bytes of verified in-region ROM member `fxdb1-8a.bin` at offset `$3e000` (CRC32 `1d055bea`, SHA-1 `96531db0a3a36319bc0a28096e601302eb2eb115`). No out-of-region read value is observed or inferred from those bytes.

The ignored MAME disassembly is retained in `simulation/fax_bank_capture_long/fax2/disasm/`. At `$f9e5`, the reader executes `LDA ($0e),Y`, increments `$0e`, and on low-byte wrap increments `$0f`; when `$0f` reaches `$40`, it resets `$0f` to `$20`, increments `$0d`, and writes `$0d` to `$2000` at `$f9fd`. The preceding `$f9e7` reads therefore align with a bank-window stream cursor, and the `$18` write follows the read at `$3fff` as a one-past-end rollover. This is source-backed interpretation of the routine and event sequence; the exact dynamic caller/semantic role is not established by this passive bus capture. In this specific observed path the CPU does not read from bank 24 before selecting bank 0 again, so the adapter's zero result for bank 24 does not affect the captured accesses. That does not establish global MAME parity for any later read of bank 24.

Banks `$19-$1f` (25–31) were not observed, but their absence in this bounded run is **not evidence that they are unreachable**. FAX also selects bank 22, which lies in the in-region but unpopulated hole identified by the archive audit.

This capture therefore establishes observed selector values only; it does not resolve the out-of-region read contents or complete gameplay coverage. The remaining out-of-range behavior is as described in `fax-bank-prom-contract.md`. No production RTL, MRA, QIP, or Quartus work was performed.
