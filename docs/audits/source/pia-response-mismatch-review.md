# Venture PIA response mismatch review

## Finding

The seven mismatches are all the same bus-visible sequence: the sound CPU reads PB as `0x40`, writes PB data `0x00`, then the main CPU sees CA1 IRQ status and reads PA as `0x40` about 0.34 ms later. At those events, audio CRB is `0x2C` (PB data selected), audio DDRB is `0xFF`, main CRA is `0x2C` (PA data selected), and main DDRA is `0x00`. Thus the source write and destination read are fully selected byte accesses. The `0x40` result cannot be explained by DDR masking: `0x00 & 0xFF` is `0x00`, and an all-input PA read uses the external PA input byte.

The trace shows the sound CPU acknowledging/clearing a previously held `0x40` on PB, while the main CPU later reads that same byte after its CA1 status flag appears. It does **not** record the PIA callback argument, CA1/CB1 pin transitions, or the main PIA's internal input latch at each bus edge. Therefore the captures establish a real bus-level stale-response mismatch against the analyzer's immediate byte-forwarding expectation, but do not identify whether the discrepancy is in the MAME Exidy callback path, the intended hardware inter-PIA behavior, or the intended handshake semantics. The evidence does not support dismissing it as an analyzer DDR qualification error.

## Repeated mismatch instances

All rows below come from the frozen Venture trace, using the existing analyzer's first-main-PA-read-before-next-audio-PB-write rule. `Δt` is relative to the audio PB write of `0x00`.

| Frame | Audio PB write `00` | Main PA read `40` | Latency |
|---:|---:|---:|---:|
| 3074 | 51.251248762 s | 51.251590930 s | 342.168 µs |
| 3101 | 51.689292267 s | 51.689645984 s | 353.717 µs |
| 3127 | 52.126394870 s | 52.126734433 s | 339.563 µs |
| 3153 | 52.564272991 s | 52.564633583 s | 360.592 µs |
| 3179 | 53.001505220 s | 53.001845337 s | 340.117 µs |
| 4162 | 69.374110222 s | 69.374449021 s | 338.799 µs |
| 4212 | 70.217368469 s | 70.217705886 s | 337.417 µs |

Each instance has the same nearby event order:

1. Audio reads CRB=`0xAC` (the CRB IRQ1 status bit is set), then reads PB data=`0x40`.
2. Audio writes PB data=`0x00` at PC `0x5C33` (`$1002`). The captured CRB is `0x2C`, DDRB=`0xFF`.
3. Main CPU polls CRA at PC `0xC966` (`$5201`), repeatedly sees `0x2C`, then sees `0xAC` with the IRQ1 status bit set.
4. Main reads PA data=`0x40` at PC `0xC983` (`$5200`), with CRA=`0x2C`, DDRA=`0x00`.

The status reads are consistent with a PIA handshake: CR reads expose the IRQ flag in bit 7; a port data read clears its side's IRQ flags. The sound-side PB data read returns the currently driven `0x40` because DDRB is all outputs. The main-side PA data read is all inputs, so its byte is supplied from the paired external input path rather than its output latch.

## 6821 byte semantics and wiring

The capture uses MAME 0.288 (binary SHA256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`) and records pinned MAME source commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`. The local pinned source snapshot contains `exidy.cpp` and `exidysound.cpp` but not `src/devices/machine/6821pia.cpp`; the 6821 details below are checked against MAME's upstream 6821 implementation. The exact-commit URL is provided so it can be verified against the pinned revision.

- A PIA data-register write updates the raw output latch, then the output callback receives the DDR-qualified value. On PB, the driven callback byte is `out_b & ddr_b`; with DDRB=`0xFF`, the `0x00` write drives `0x00`.
- A PIA port-A read combines output-latch bits for DDR outputs and input-pin bits for DDR inputs. With DDRA=`0x00`, PA returns the external input byte without output-latch bits.
- The PIA wiring in the pinned Exidy configuration connects soundboard PB callback to main PIA `porta_w`, and main PIA PB writes into soundboard PA input. The sound PIA registers are mapped at `$1000-$1003`.

References: [pinned MAME 6821 source](https://github.com/mamedev/mame/blob/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/devices/machine/6821pia.cpp), [pinned Venture PIA wiring](../../../simulation/reference_sources/exidy.cpp#L1614), and [pinned audio PIA map/output binding](../../../simulation/reference_sources/exidysound.cpp#L567).

## Provenance and limits

- Trace: `simulation/pia_firmware_timing/20261007_03/venture/pia-bus.csv`, SHA256 `777A84E05FAD450EF18C6C1768FB220AC09603ABF0F161919BDDD9C773CA64AA` (ignored runtime capture; not added to source control).
- Existing analysis: `simulation/pia_firmware_timing/analysis/20261007_03.json`; it reports 5,790 audio PB writes, 5,795 main PA reads, 5,133 first reads before overwrite, 5,126 matches, 7 mismatches, and 657 writes overwritten before a read.
- The PIA CSV logs CPU register accesses and sampled CR values, not pin-level callback activity or internal latches. It cannot prove the voltage/value on PA at the exact sampling edge, nor explain the source of the old byte.
- No new MAME capture, Quartus build, FPGA change, or ROM-derived artifact was made for this review.

The next discriminating test should record the sound PIA PB output callback value and the main PIA PA input value/CA1 edge at each event, then compare those with the main CPU read. If the callback sees `0x00` before CA1 but PA still reads `0x40`, first investigate MAME's input-latch/handshake ordering; no FPGA trace was captured in this unit; if the callback remains `0x40`, inspect the MAME device callback semantics and the adapter's raw-write handling.
