# MC3417 audio filter reference

This note pins the source and arithmetic used to prepare coefficient and sample-vector artifacts for the two cascaded CVSD reconstruction filters in the Exidy sound path.

## Pinned source and board values

The preparation script checks these complete file hashes before generating metadata or vectors:

| File | SHA-256 |
|---|---|
| `flt_biquad.cpp` | `c5c3bfa36c889362313bd4e8c18a27c471e877585fef5059f700ad1384c41190` |
| `flt_biquad.h` | `cda165401b980b05e9bf39e1085c89aa4db595b5657f895508c80ce6845da9e5` |
| `exidysound.cpp` | `57c0edc71e9faf0a37e48eef406586e95a95902ef0f9e53275a7ad3326fad660` |

`exidysound.cpp` configures two cascaded `opamp_mfb_lowpass` filters, each with R1=10 kΩ, R2=3.9 kΩ, R3=18 kΩ, C1=20 nF, and C2=2.2 nF. The MC3417 route into the first filter has gain 0.3086, documented in source as cancelling the pair's nominal 3.24 combined gain.

## Coefficients and C++ oracle

`tools/mc3417_filter/prepare_reference.py` strictly verifies all three hashes above. It transcribes the pinned `opamp_mfb_lowpass_calc()` and `recalc()` equations. The analog helper gives gain -1.8, cutoff approximately 2863.68495155162 Hz, and Q approximately 0.87352215593432. MAME's bilinear low-pass calculation produces normalized `b0,b1,b2,a1,a2`; `recalc()` then multiplies the three numerator terms by the analog gain. The DF-II recurrence is extracted verbatim from pinned `filter_biquad_device::step()`:

```
w0 = (-a1*w1) + (-a2*w2) + input
output = (b0*w0) + (b1*w1) + (b2*w2)
```

The script places that extracted method body in a minimal C++ struct with MAME-compatible `float` input/output samples and `double` state. Its C++ coefficient setup translates the pinned analog helper and LOWPASS recalc equations; the script compares the result with its Python derivation to 1e-14. The compiled C++ method writes expected vectors, so the reference output does not come from a Python recurrence copy. Run on a host with `g++`, `c++`, or `clang++`. `--prepare-only` emits the harness and metadata if no compiler is available, but does not create expected vectors.

For one stage, coefficients in order `b0,b1,b2,a1,a2` are approximately `[-0.00374836551367961, -0.00749673102735922, -0.00374836551367961, -1.88999074936539, 0.898320450506903]`. The two-stage DC gain is approximately 3.24. `coefficients.json` records full double precision and nearest Q28 integers.

## Generated vectors and cadence

Run `python tools/mc3417_filter/prepare_reference.py` from the repository root. Outputs are placed under ignored `simulation/reference_sources/mc3417_filter_generated/`. `vectors.csv` contains Q24 input, expected Q24 output, and expected float output; headerless `vectors.tsv` carries integer fields for simulation fixtures. Cases reset both stages independently: positive and negative half-scale impulses, positive and negative quarter-scale steps, an 8192-sample quarter-scale DC settling run, 1 kHz and 10 kHz quarter-scale tones, and deterministic quarter-scale random input.

The matched candidate cadence is 192 kHz. MAME creates this filter stream with `SAMPLE_RATE_OUTPUT_ADAPTIVE`, so 192 kHz is not asserted as the native final MAME stream rate; these coefficients and vectors establish parity at this explicit cadence. A native MAME WAV comparison with its final stream rate and resampling is a separate follow-up. The C++ oracle applies route gain 0.3086 to the pre-route MC3417 Q24 input before stage 1. Each stage output is stored as a 32-bit `sound_stream::sample_t` float, and stage 1's rounded output feeds stage 2. Output Q24 values are rounded to nearest integer. Default vectors are synthetic, including over-full-scale positive/negative steps. Optional `--firmware-pcm <pcm.csv>` adds an ignored renderer-trace replay; no vectors or private audio are committed.

Official source: [pinned MAME biquad](https://raw.githubusercontent.com/mamedev/mame/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/devices/sound/flt_biquad.cpp). Final candidate results and reproduction are in [qualification](mc3417-filter-qualification-2026-10-12.md).
