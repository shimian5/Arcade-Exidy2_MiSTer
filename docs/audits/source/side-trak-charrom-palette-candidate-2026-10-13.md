# Side Trak character ROM and palette candidate

The isolated candidate in `candidates/side_trak/exidy_sidetrak_charrom.sv` provides an immutable, download-only character PROM and the palette function derived from pinned MAME 0.288. It is not bound to production RTL, and its `profile == 8'h00` guard remains a proposal; the wider 28-set profile matrix is untouched.

The staged `sidetrac.zip` was verified by MAME 0.288. Its `stl9c-1` member has size 0x400, CRC32 `08710a84`, and SHA-256 `ebdd8a4d3f36537220da7c997c904a43e4b65ff873ea2c19ef18e44574b0c415`. A separate MAME Lua probe read the mapped ROM window `$4800-$4fff` through the ROM-only program-space mapping. The first 0x400 bytes exactly match that archive member; the unpopulated `$4c00-$4fff` tail reads as all zero. This establishes the MAME region fill used for glyphs 128-255 without guessing a hardware byte policy.

Pinned MAME `draw_background` reads `cram[(code << 3) | row]`, tests bit 7 for the leftmost pixel, then shifts left as x advances. For a set bit it selects pen `4 + ((code >> 6) & 3)`; a clear bit selects pen 0. The candidate returns the immutable row byte after one synchronous read edge and exposes the MSB-first selected pixel/pen/RGB while `read_valid` is asserted. CPU writes have no path to the character array; only an ordered 1024-byte download can populate it. A reset, malformed address sequence, or partial transfer withholds readiness; a complete new transfer restores it.

MAME `init_sidetrac` sets RGB latch bytes to `{f8, dc, b8}`. Its `set_colors` pen order produces this independent `{R,G,B}` table:

| Pen | RGB |
|---:|:---:|
| 0 | `000` |
| 1 | `111` |
| 2 | `000` |
| 3 | `110` |
| 4 | `111` |
| 5 | `111` |
| 6 | `010` |
| 7 | `000` |

`tools/side_trak/build_char_vectors.py` verifies the actual archive CRC, confirms the MAME-mapped window against the verified member, parses the source glyph/palette methods, and writes only ignored ROM-derived inputs under `simulation/side_trak/character_path/`. `tools/side_trak/run_charrom_palette.ps1 -Run <unique-name>` runs ROM verification, the safe ROM-window probe, then the isolated Verilator regression. The `probe-004` run passed all 16,384 combinations of 256 codes × 8 rows × 8 x positions, all eight palette pens, synchronous read-valid timing, reset and reload, incomplete/out-of-order load rejection, and invalid-profile gating.

This checks source interpretation and the isolated candidate's load/read contract. It does not prove the physical board's monochrome jumpers, sprite scheduling, actual video-path alignment, full memory-map integration, fitted timing, or gameplay acceptance. See [the source-backed map audit](side-trak-integration-2026-10-13.md) and [the separate direct-map candidate](side-trak-direct-map-candidate-2026-10-13.md).
