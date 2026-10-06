# Integration gates for the third block

These gates separate a design recommendation from authorization to treat it as working hardware. They guide integrator review before assigning production edits.

| Contract | Evidence required before wiring | Later acceptance |
| --- | --- | --- |
| Reference cases | Actual bounded MAME runs with pinned executable, set/ROM hashes, fresh configuration, identical input timelines, observed register events and two-run comparison. Reading an interrupt register for observation must not acknowledge it. | Compare equivalent RTL execution and complete frames at the first divergence; MAME-only output does not reproduce a core defect. |
| Expansion loader | No changed legacy stream interpretation; explicit new-region lengths, offsets, bank masks, download completion/readiness, profile checks, address-boundary tests and memory budget. | Full ROM byte equality through the runtime CPU path, FAX populated/unpopulated bank behavior, CVSD command execution and fitted memory/timing. |
| CRT transport | Explicit RGB-valid tap and coordinate normalization, source completion/consumer ownership margins, drift and startup bounds, fault behavior and clock implementation proposal. | Full-image orientation/pixel equality, RTL CDC and pipeline checks, fitted clocks/timing, mode/reset/FX/OSD/DV tests and physical receiver acceptance. |

Current source/reference findings to preserve:

- Exidy2's `core_pix_clk` is a one-master-cycle pulse every eight cycles. The existing `arcade_video` wrapper detects its rising edge, latches vertical sync at horizontal sync, and latches vertical blank at the horizontal blank falling edge. The raw raster frame boundary is therefore not automatically the RGB pipeline's row-zero boundary.
- The current source clock also runs CPU/video logic, and the PLL has other audio outputs. Reconfiguring it solely for CRT transport would require proving all game/audio clocks remain unchanged. Prefer a separate output transport clock with a reviewed frequency relationship.
- The separate-clock candidate references original PLL output 1 with downstream integer dividers. Verify the original outputs' actual 4:1 counter relationship, legal cascade routing/bandwidth, lock and fitted timing before treating the modeled exact rate as physical evidence. Prove Native transport separately.
- Mouse Trap's available voice ROMs total 16 KiB. The legacy fallback selector has no instantiated storage consumer; appending bytes alone cannot provide speech execution.
- Download indices 0 (legacy ROM), 1 (PCB), 2 (raster), 3 (high-score configuration), 4 (high-score dump) and 254 (DIPs) are already in use. New regions must avoid these reservations. The top currently resets on any download but sends only index-0 writes to core ROM storage; sequential expansion regions need an explicit ready/reset contract.
- MAME configures 32 FAX question-bank entries from offset `0x10000`, each `0x2000` bytes, while its declared main region is `0x40000`. Entries 24–31 lie outside that region. A safe new-core fill policy must be explicit and distinguished from confirmed PCB or MAME behavior.
- Full-range geometry controls must document edge visibility and receiver overscan limitations; stable timing does not guarantee all pixels are visible at every position setting.

Pinned reference source: official MAME `mame0288`, commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`. Ignored local copies in `simulation/reference_sources/` were fetched read-only from the official repository. SHA-256: `exidy.cpp` = `0f58186ad90f0592454c505ff10fbca948eba14e7815704b2d24b13f69327486`; `exidysound.cpp` = `57c0edc71e9faf0a37e48eef406586e95a95902ef0f9e53275a7ad3326fad660`.

Source links: [board driver](https://github.com/mamedev/mame/blob/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/mame/exidy/exidy.cpp), [sound board](https://github.com/mamedev/mame/blob/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/mame/shared/exidysound.cpp). Source pinning does not prove byte-for-byte reproducibility of the installed MAME executable.
