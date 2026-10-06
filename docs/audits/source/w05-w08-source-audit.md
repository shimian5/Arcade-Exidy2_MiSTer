# W05/W08 offline source audit — RTL vs pinned MAME 0.288

Date 2026-10-06 (cloud, no simulation). Compared `rtl/Exidy2.v` (baseline `bfd1b5c`) and `rtl/audio_board.v` with MAME commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` (`src/mame/exidy/exidy.cpp`, `src/mame/shared/exidysound.cpp`). These are source-reading findings and hypotheses, not proven symptom causes; each lists the test that would confirm or refute it. Line numbers refer to those files.

## Sprites / collision / IRQ (W04–W05)

| # | Finding | Evidence | Confirming test | Related |
| - | --- | --- | --- | --- |
| S1 | **Sprite-1 enable gating is not implemented.** MAME disables sprite 1 (drawing and collision) when `$5101` bit 7 is set and bit 4 is clear, unless the set has collision mask 0 (`sprite_1_enabled`, exidy.cpp:1282). RTL latches `{ADSEL,M2R[4],M1R[4],CPL[4:0]}` from `$5101` (Exidy2.v:161) but `ADSEL` and `CPL` have no consumers; the control PROM address does not include them. Venture/Mouse Trap/Pepper II/FAX/Teeter have non-zero masks, so the gating applies. | grep: no other use of `ADSEL`/`CPL` in `rtl/` | Capture `$5101` writes in MAME Venture around the horizontal-shot/room-entry sequence; check whether bit7=1,bit4=0 occurs while the arrow/Winky appears. Then drive the RTL with the same writes. | I05 hypothesis |
| S2 | **Per-game collision mask/invert absent.** MAME (mask/invert): base/Targ/Spectar/Side Trak 00/00; Venture 04/04; Teeter Torture 0c/0c; Mouse Trap 14/00; Pepper II/Hard Hat 14/04; FAX/FAX2 04/04 (exidy.cpp:1545–1686). RTL builds one `EIR` with M1/char positive in bit 2, M1M2 in bit 4, bit 3 hard 0, regardless of profile. | Exidy2.v:668; increment sprite-fixture README already notes Venture mask/polarity | Existing synthetic probe extended per profile; MAME bus capture of `$5103` reads | I05, I06 |
| S3 | **M2/background collision (bit 3) is tied to 0.** Teeter Torture (0c) needs it; cDET in RTL still raises IRQ for it, so the CPU gets an IRQ whose latched cause lacks the bit. | Exidy2.v:668 vs `check_collision` 1417–1424 | Synthetic M2-only overlap; compare `$5103` | I11 |
| S4 | **`EIR` only updates on the rising edge of `rCPU_IRQ`.** MAME re-latches on every collision timer and at vblank (`latch_condition`), last event wins, each asserting IRQ. If a second cause occurs while the first IRQ is pending, RTL keeps the stale cause bits. | Exidy2.v:665–668; exidy.cpp:1338–1345, 1150–1157 | Back-to-back vblank/collision/coin events in an RTL fixture; compare latch value to a MAME model | I05, I06 |
| S5 | **DIP bits in the interrupt latch are zero.** MAME ORs the `INTSOURCE` port (LNG0/1 bit 0–1, TABLE bit 3 where not collision) into `$5103`; RTL fixes bits 1:0 to 00 and bit 3 to 0. | exidy.cpp:89–91, 1146; Exidy2.v:668 | Check DIP defaults per set (language/cocktail) against MAME `INTSOURCE` | I12 |
| S6 | **`rCPU_IRQ` is one multi-edge always block with blocking assignment and a combinational async clear (`nEIR`, decoded from CPU address).** Glitch/race sensitivity unproven. | Exidy2.v:661 | RTL timing review; gate-level glitch check is a Quartus-side item | W05 |
| S7 | Source comments to test, not assume: `M2R[4]` "not working" (Exidy2.v:381), `hspcnt` stairs crash (Exidy2.v:~628), early-game `1'b0|!pcb[4]` sprite-1 bank bit. | | Part of per-game regressions | W04 |

Existing fixture findings (docs/design/sprite-fixture, sprite-serialization) already cover mask/polarity for Venture and graphic bit order; S1, S3–S6 are new.

### MAME survey of `$5101` writes and `$5103` reads (attract, zero input)

[Data](../../reference_cases/int-latch-survey.json); replay with `tools/reference_cases/survey_int_latch.py` over `exidy_reference.lua` captures. MAME 0.264 (package) was used because 0.288 is not installable here; ROM sets verified good. Venture is not yet captured.

| Set | `$5103` values read (count) | `$5101` values written | Reading |
| --- | --- | --- | --- |
| targ, spectar | 00 | none | mask 0; no latch information in attract |
| sidetrac | 63 | none | bits 0–1 (DIP) are 1 and coin bits 5–6 high; RTL ties bits 1:0 to 0 (S5) |
| mtrap (14/00) | 00, 84 | 5c | 84 = bit7 + bit2 collision, positive polarity |
| pepper2, hardhat (14/04) | 04 (vblank), 80 (collision) | 1c 5c 7c (+ff once hardhat) | bit 2 is **high at vblank, low on collision**; RTL gives the opposite (S2) |
| venture (04/04), startup + coin/start/right(+fire) | 04 (vblank), 80 (collision), 44 once | f0 (1677), 00 (195) | same polarity as pepper2: vblank 04, collision 80; RTL reversed (S2). `$5101` is only f0/00 so bit 7 set implies bit 4 set |
| teetert (0c/0c) | 0c (vblank), 84, 88 | 00 08 14 1c 34 3c | collisions clear bit 2 or bit 3 separately; RTL cannot produce the bit-3 case (S3) |

No capture, including Venture's startup-to-maze sequence, writes `$5101` with bit 7 set and bit 4 clear, so MAME's sprite-1 gating never fires in them: **S1 is not supported as the cause of the Venture arrow in this sequence.** It remains reachable only in situations not yet captured (room entry/other stages); a deliberate write test is the other option.

## Shared audio (W08–W09)

| # | Finding | Evidence | Confirming test | Related |
| - | --- | --- | --- | --- |
| A1 | **Outputs are not mixed.** `audio_l` carries only the 8253 channels and `audio_r` only the 6840 channels (non-CPU boards: `MUSIC` left, `TONE_out` right). MAME mixes everything to one mono speaker (gain 0.5). Each ear therefore misses roughly half the effects on CPU-board games. | audio_board.v:241–259 (filters), 261–263; top level passes them straight to `AUDIO_L/R` (Arcade-Exidy2.sv:473) | Listen/measure: play a sound that uses both chips; sum check in an isolated mixer sim. Reference needs MAME WAV capture. | I07–I10 (very likely a main contributor) |
| A2 | **Sound RAM differs from the 6532 map.** MAME maps 128 bytes of RAM mirrored through `0x0000–0x07FF` (Venture; Mouse Trap `0x0f00` mirror plus separate RAM at `0x80–0xff`). RTL instantiates a distinct 2 KB RAM ("expanded ram for a test"), so zero-page/stack aliasing and mirrored reads behave differently. | audio_board.v:74–83 vs exidysound.cpp:565, 843–844 | Replay audio-CPU programs; compare RAM reads/writes at aliased addresses | I08, I09 |
| A3 | **No `filter_w`/`sfxctrl_w` model.** MAME decodes `$2000` (filter control) and `$3000` (SFX control); RTL has enable nets `io20_27` unused and `io30_37` only gates 6840 `vs`. | exidysound.cpp:569, 571; audio_board.v:196–199 | Count writes to these ports in a MAME run per game | I08, I09 |
| A4 | **6840 is a Berzerk module.** `berzerk_sound_fx` is borrowed; MAME models SH6840 with Exidy-specific clocks/noise. Accuracy unproven. | audio_board.v:135–147 | Register-write replay vs MAME `sh6840` output | I08, I09 |
| A5 | **8253 gate tied high and clocks shared.** | audio_board.v:166–180 | Compare to exidysound.cpp sh8253 clocks | I08 |
| A6 | **Mouse Trap CVSD path absent** (already audited: no Z80/CVSD ROMs loaded). | docs/audits/mra | W09 | I07 |
| A7 | Targ/Spectar tone uses a hand-built counter chain; crash/noise path from the discrete board missing. | audio_board.v:204–232 | MAME trigger semantics/sample references | I10 |

## Applied after this audit
- **A1** — `rtl/audio_mix.v` (`exidyAudioMix`) now sums the two groups to a mono signal on both outputs (each input halved, no overflow). Unit test `sim/audio_mix/tb_audio_mix.sv` passes (corner cases + 2,000 random vectors; baseline-style mixing fails it). Production edit only in `rtl/audio_board.v` output assigns and `rtl/index.qip`; not compiled in Quartus and not listened to. Gain/balance versus MAME is still unverified; this is the first change to production RTL since the baseline.

## Proposed order
1. A1 mixer (cheap, isolated, testable): isolated saturating mono mixer with unit test; wiring needs owner listening check.
2. S1 sprite-1 enable gating: needs one MAME `$5101` trace; RTL change is small once confirmed.
3. S2–S5 interrupt latch rework as one profile-driven module, tested against a Python model of MAME's latch.
4. A2/A3 audio map accuracy, replayed against a MAME audio-CPU trace.
