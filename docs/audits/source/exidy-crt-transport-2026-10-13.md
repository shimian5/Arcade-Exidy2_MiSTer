# Exidy CRT transport candidate — 2026-10-13

## Source and scope

`candidates/video/exidy_crt_stream.sv` reuses the GPL-3.0-or-later Victory rolling-row transport from local Victory commit `987bd51db0b07e95377ee1a68d1acbfc0ec934aa`, with the module renamed. License headers remain intact. The new `exidy_crt_capture.sv` samples the actual registered arcade_video output one native clock after CE, then normalizes active pixels into 256×256 coordinates. Neither candidate is in production QIP.

The source/game clocks remain native. Proposed transport raster is 336×262 with all 256 active rows, at output clock ratio 131/140 of the native raster clock. Exact PLL generation, mode switching, FX interaction, full integration and HDMI/Direct Video/S-Video receiver acceptance remain gates.

## Bounded qualification

- `sim/crt_stream/run.py`: seven independent synthetic image/ownership cases pass. Nominal, damage, pause, reset, stopped source and ±10,000 ppm fault cases cover blanking/recovery. Nominal checks 786,432 pixels and 565,128 ownership events over twelve frames. Severe drift deliberately faults; it does not establish arbitrary-rate support.
- `sim/crt_capture/run.py`: actual production raster and mixer pass eight RGB3 bitplanes, 524,288 active pixels, coordinate/edge checks and a wrong-expected-RGB negative control. Latency is nineteen native clocks.
- `sim/crt_join/run.py`: actual production raster/mixer, capture and dual-clock CRT transport pass the same 524,288 independently queued RGB pixels. First and last rows each retain 256 pixels. No faults or malformed rows occur. Observed latency ranges from 2,072 to 49,303 native clocks. The wrong-expected-RGB negative control fails as intended.

Reports and compiled output stay private under `simulation/crt_stream`, `simulation/crt_capture`, and `simulation/crt_join`. Runners record source hashes. These are synthetic RGB tests; full game colors, gamma table enabled, scandoubling, runtime mode changes, actual PLL lock/recovery and physical display acceptance are not qualified by them.

## Next unit

Fit an exact-ratio output PLL referenced to the existing source PLL, then qualify controller reset/lock/warmup and bind the transport without changing gameplay timing. Preserve the native path and make any FX compatibility behavior explicit. A fresh full-core flow and owner hardware session follow integration.
