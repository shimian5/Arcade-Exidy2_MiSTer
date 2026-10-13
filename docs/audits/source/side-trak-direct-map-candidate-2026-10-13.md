# Side Trak direct-map candidate

This isolated candidate expresses pinned MAME 0.288 `exidy_map` plus `sidetrac_map` address and read/write selects without requiring absent PROM data. It is intentionally unbound: `candidates/side_trak/exidy_sidetrak_direct_map.sv` is not referenced by production RTL, no MRA or shared RTL was changed, and the source audit's character video timing, sprite scheduling, and discrete audio gaps remain open.

## Candidate behavior

The candidate is enabled only by exact index-1 profile byte `8'h00`. That value is a proposal based on the existing core's `pcb[1:0]==00` Side Trak/monochrome decode, not a hardware strap proof. The 28-set MAME availability manifest contains one Side Trak set. The six existing release MRA profile bytes are `01`, `02`, `10`, and `30`; the current candidate MRA bytes use `50`, `90`, `B0`, `D0`, `F4`, and `F8`. None is zero. This is only a collision check against the current release/candidate MRA inventory; the remaining 28-set profile matrix is not assigned by this unit.

For profile `00`, the candidate describes these MAME-visible selects:

| Addresses | Read select | Write select | MAME rule |
|---|---|---|---|
| `$0000-$03ff` | work RAM | work RAM | base RAM |
| `$0800-$3fff` | program ROM | none | Side Trak ROM window, even where image bytes are empty |
| `$4000-$47ff` | video RAM | video RAM | `$4000-$43ff`, mirror `$0400` |
| `$4800-$4fff` | character ROM | none | ROM map; only `$4800-$4bff` has the declared 0x400-byte character PROM |
| `$5000-$503f`, `$5040-$507f`, `$5080-$50bf`, `$50c0-$50ff` | none | four sprite coordinate registers | each base register mirrors `$003f` |
| `$5100-$51ff`, `A[1:0]=00` | DIP | sprite number | base DSW read/write-only sprite latch, mirror `$00fc` |
| `$5100-$51ff`, `A[1:0]=01` | IN0 | sprite enable | mirror `$00fc` |
| `$5100-$51ff`, `A[1:0]=11` | interrupt status | none | mirror `$00fc` |
| `$5200`, `$5201` | none | audio/control 1, 2 | Side Trak handlers |
| `$5210-$5212` | none | color latches | write-only base map |
| `$5213` | IN2 | none | base map |
| `$ff00-$ffff` | program ROM at `$3f00-$3fff` | none | explicit MAME vector mirror |

The candidate exports a fixed IRQ/status base value of `$63`, matching pinned MAME's `INTSOURCE` fixed bits and all 3536 observed live `$5103` reads in the native 0.288 capture. It does not model collision timing or vblank IRQ generation; Side Trak's MAME collision mask is zero. Keep the capture and source limitations from [the broader Side Trak audit](side-trak-integration-2026-10-13.md) in view.

## Exhaustive source-derived check

`tools/side_trak/build_map_vectors.py` parses all 13 declarations in `exidy_state::exidy_map` and all 5 additions in `spectar_state::sidetrac_map`; it fails if the declaration count or syntax changes. It expands the declared mirror masks into an expected read/write select for every 16-bit address. The generated oracle compares both read and write modes for all 65,536 addresses (131,072 cases), including the `$ff00` vector-region offset. Two exact-profile negative controls verify that `$01` and `$80` produce no Side Trak selects. The expected vectors and build output live only in ignored `simulation/side_trak/direct_map/`.

Reproduce under WSL with Verilator 5.052:

```sh
bash tools/side_trak/run_direct_map.sh
```

Result on 2026-10-13: `PASS: 131072 exhaustive MAME-derived read/write cases, vector alias and profile negative controls`. This verifies the standalone decoder against the parsed MAME map declarations; it does not validate PROM/video timing, storage latency, a loaded MRA, production binding, fitting, or gameplay.
