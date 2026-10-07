# Frozen PIA firmware callback-order review

This review uses the frozen passive MAME capture run `simulation/pia_firmware_timing/20261007_03` and a standalone analyzer at `tools/pia_firmware_timing/analyze_status_order.py`. The analyzer preserves the existing pair qualification: audio `PB_DATA` write with CRB bit 2 set and DDRB `FF`; then the first main `PA_DATA` read after that callback row and before the next audio `PB_DATA` write, with main CRA bit 2 set and DDRA `00`. It reads CSV callback row order only; it does not load or use `time_s`.

## Captured response ordering

All qualified source/read pairs matched data, and none of those first reads bypassed a main CRA status-read callback after the paired audio PB write:

| Set | Qualified pairs | Audio source PB-write PCs | CRA status reads after source write, before PA read | CA1 bit 7 set in last status read | Matched PA-read PC | Status-read PC |
|---|---:|---|---:|---:|---|---|
| Venture | 5,790 | `5C33` 5,789; `5C4C` 1 | 5,790 | 5,790 | `C983` | `C966` |
| Mouse Trap | 88 | `6C59` 83; `6C72` 5 | 88 | 88 | `AC1D` | `AC05` |
| Pepper II | 1 | `6C48` 1 | 1 | 1 | `A31A` | `A302` |
| Hard Hat | 1 | `6C48` 1 | 1 | 1 | `B45E` | `B446` |

In these sampled pairs, callback order is audio PB data write → main CRA status read with bit 7 set → main PA data read. The CRA mode on each paired read is `0x2C` (PA data selected); main DDRA is `0x00`. Source audio CRB is `0x2C` and DDRB is `0xFF`. The analyzer observed the CA1 status bit set in the recorded CRA read value before the PA read for every matched pair. This supports that firmware performs a status-register read before consuming the sampled response. Callback rows cannot prove the CPU branches on or otherwise tests bit 7, so this note does not claim a branch-level status check.

The matched first PA-read sites above show no status bypass in the captured response pairs. Additional PA reads were separate callbacks: Venture had four repeats at PC `C936` within a source-byte holding window, each also preceded by a CRA read after that source write, plus one read before any qualified source write. Pepper II had two pre-source PA reads at `A2B3`; Hard Hat had two at `B3F7`; Mouse Trap had one at `ABB6`. These pre-source reads do not establish a bypass for a new reply because there was no corresponding qualified source write in the capture window. No other qualified PA-read site bypassed a post-write CRA read in these captures.

## Request writes and source holding

Every paired source write had a prior main `PB_DATA` write in the callback interval since the prior audio `PB_DATA` write. Those main PB requests used CRB `0x2C` and DDRB `0xFF`; the latest-request PCs were Venture `C9C1` (5,790 paired requests), Mouse Trap `ABF6` (88), Pepper II `A2F3` (1), and Hard Hat `B437` (1). Venture requests were `0x07` for 5,789 pairs and `0x13` once. Mouse Trap requests were `0x07` for 75 pairs, `0x03` for 12, and `0x13` once. Pepper II and Hard Hat each used `0x13` in their one pair. There were no additional main PB requests between paired audio response writes and PA reads in Venture, Pepper II, or Hard Hat. Mouse Trap had such an intervening request on 16 pairs; the paired PA read still occurred before the next audio PB write and matched the held source byte.

For all paired source writes, the first qualified main PA read occurred before the next audio PB data write; no paired response was overwritten first. Callback-row distance from source write to the next audio PB data write (not elapsed time) was broad: Venture PC `5C33` had 5,788 intervals, median 43 rows, range 10–29,203; Mouse Trap PC `6C59` had 83 intervals, median 409 rows, range 10–50,737, and PC `6C72` had four intervals, median 919.5 rows, range 413–14,734. The last captured source write in sets without a subsequent PB data write has no interval. This is callback-order evidence that firmware-visible source values remained stable through the paired reads in these run windows; it is not a hardware timing bound.

## Reproduction and limits

Run:

```powershell
python tools/pia_firmware_timing/analyze_status_order.py `
  --run-dir simulation/pia_firmware_timing/20261007_03 `
  --output simulation/pia_firmware_timing/20261007_03/status-order.json
```

Frozen-run metadata: MAME `0.288 (mame0288)`, MAME binary SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`, pinned source commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`, `exidy.cpp` SHA-256 `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486`, and `exidysound.cpp` SHA-256 `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660`. Captured CSV SHA-256 values: Venture `777A84E05FAD450EF18C6C1768FB220AC09603ABF0F161919BDDD9C773CA64AA`; Mouse Trap `741FAAC45DDCDDA841D4C6AE60B69B0301B612175347C4FB0A227EB7A6DD8055`; Pepper II `D06E94909FDE58AE7D384F3ACC06D62ECFD67C054F03B96A01E6F84D74530650`; Hard Hat `A89423EA86B1578AADF40DCBC895255F48B3E438A2FCD639120EB2D0A61B382`.

The captures are limited to these four sets, this input run, and the observed firmware paths. Row order is only MAME callback order; it cannot establish elapsed cross-CPU setup time, all possible game states, actual FPGA CDC margin, or that every PA read waits for CA1. No ROM bytes, disassembly, or raw capture data are included in this note.

Independent root replay completed against the frozen run and confirmed all 5,880 qualified pairs have a last CRA read with bit 7 set and no bypass. The separate [ROM branch review](pia-rom-status-branch-review.md) establishes the actual conditional branch for these four inspected routines; callback analysis alone does not.
