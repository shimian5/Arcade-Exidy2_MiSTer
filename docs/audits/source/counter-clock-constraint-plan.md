# Counter-generated pulse clock constraint plan

## Scope and evidence

This is a source-based plan for the five registered divider pulses that Quartus currently reports as clocks: `PH_1`, `BCLK`, `PH_6`, `auPH0`, and `auPH0B`. It is not a constraint change or a claim that fitted timing is complete. The source is `rtl/Exidy2.v` and `rtl/audio_board.v`; the prior warning/source mapping is in [generated-clock-inventory.md](generated-clock-inventory.md). Root is running the full Quartus flow, so all post-fit collection checks and timing reports below remain pending.

The main parent is the core PLL output 0 clock (reported period 22.146 ns); the audio parent is PLL output 2 (reported period 69.604 ns). Both are PLL-derived clocks. Their periods are the fitted timing-model values, not assertions that the physical platform oscillator has those exact periods. The divider counters are initialized to zero in RTL and increment on the parent rising edge. The pulse FFs sample the old counter value in that same edge-triggered process, so the first pulse follows the counter comparison described below.

## Candidate pulse relationships

TimeQuest `-edges` counts alternating rising and falling edges of the source clock, starting with edge 1 as its first rising edge. Each pulse FF produces one parent-period-high pulse. The following edge lists encode rise, fall, and next rise; validate them against fitted clock reports and startup assumptions before applying them.

| Target | RTL condition and consumer | Parent cycles / pulse phase | Candidate source edge list | Period and high time |
|---|---|---:|---:|---:|
| `BCLK` | `cencnt[2:0] == 0`; raster/video and sprite logic | rise on first parent edge, then every 8 cycles | `{1 3 17}` | 8 × 22.146 = 177.168 ns; high 22.146 ns |
| `PH_1` | `cencnt[5:0] == 31`; horizontal counters, shifter logic; also CPU enable | first rise on parent cycle 32, then every 64 | `{63 65 191}` | 64 × 22.146 = 1417.344 ns; high 22.146 ns |
| `PH_6` | `cencnt[5:0] == 0`; shifter/latch phase | first rise on first parent edge, then every 64 | `{1 3 129}` | 64 × 22.146 = 1417.344 ns; high 22.146 ns |
| `auPH0` | `cencnt_au[3:0] == 0`; RIOT phi2; also audio CPU enable | first rise on first audio edge, then every 16 | `{1 3 33}` | 16 × 69.604 = 1113.664 ns; high 69.604 ns |
| `auPH0B` | `cencnt_au[3:0] == 1`; 6840 sound clock | first rise on audio edge 2, then every 16 | `{3 5 35}` | 16 × 69.604 = 1113.664 ns; high 69.604 ns |

Example candidate syntax, **not yet validated against the fitted netlist**, is:

```tcl
create_generated_clock -name BCLK -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -edges {1 3 17} [get_pins {emu:emu|exidy2:ex2|BCLK}]
create_generated_clock -name PH_1 -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -edges {63 65 191} [get_pins {emu:emu|exidy2:ex2|PH_1}]
create_generated_clock -name PH_6 -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -edges {1 3 129} [get_pins {emu:emu|exidy2:ex2|PH_6}]
create_generated_clock -name auPH0 -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -edges {1 3 33} [get_pins {emu:emu|exidy2:ex2|exidyAB:sound_board|auPH0}]
create_generated_clock -name auPH0B -source [get_pins {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}] -edges {3 5 35} [get_pins {emu:emu|exidy2:ex2|exidyAB:sound_board|auPH0B}]
```

The audio edge lists were corrected after checking the sampled RTL waveform: a 16-cycle recurrence is 32 alternating source edges, not 30. This was a planning-document arithmetic error only; no candidate SDC with these lists was applied. The helper `tools/timing/check_counter_pulses.py` guards the source initializer, increment, and comparator expressions before checking the expected pulse waveform; it is not a full HDL simulator.

For post-fit register/Q-pin collection discovery, use [counter-clock-discovery.md](counter-clock-discovery.md) and `tools/timing/discover_counter_clocks.tcl`. That audit also records the unresolved `auPH0B`/T65 same-audio-edge setup contract.

The logical instance names above follow the RTL and current fitted names (`emu:emu|exidy2:ex2`, with `exidyAB:sound_board` for the audio child). The PLL wrapper source instance is `emu|pll|pll_inst` in the RTL hierarchy. These are logical paths, not yet verified fitted Q-pin selectors. The read-only discovery script `tools/timing/discover_counter_clocks.tcl` must resolve one register keeper, one Q pin, one parent PLL source pin, and one source clock per pulse, then write candidate constraints to the ignored report directory without applying them. Missing or ambiguous collections are fatal. If generated clocks are already propagated or duplicated by another assignment, resolve that explicitly before integrating any candidates into the SDC.

## Required timing checks

These are synchronous related-clock domains. Modeling the pulse clocks must keep data paths timed; it must not add asynchronous clock groups or false paths.

1. **Parent to divider registers:** Verify core `master_clock` paths into `cencnt` and the D pins of the PH/BCLK pulse registers, and audio `audio_clk` paths into `cencnt_au` and the auPH pulse registers. Generated-clock declarations do not replace these source-domain paths.
2. **Within each generated domain:** Report setup and hold paths from each pulse clock to its actual consumers. Include `BCLK` to raster state such as `vscnt[*]` and pixel/sprite consumers; `PH_1` to horizontal counter state such as `hscnt[*]` and shifter state; `PH_6` to the mapped shifter/latch endpoint; `auPH0` to RIOT state; and `auPH0B` to 6840 state such as `snd3[*]`.
3. **Between and across domains:** Inspect generated-to-parent, parent-to-generated, and generated-to-generated transfers, especially crossings between main and audio clock trees. Confirm relationships reflect the common PLL and that no path class became unconstrained solely because clock names changed.
4. **Clock reports:** Check `report_clocks` for exact source, period, first edge, pulse width, and phase; inspect `report_clock_transfers`, unconstrained path reports, and targeted `report_timing` paths. Compare object counts to the source query. A positive summary slack is not sufficient if clock transfers are absent or endpoint collections are empty.

Useful existing fitted consumer evidence includes `emu:emu|exidy2:ex2|BCLK` feeding `vscnt[7]`, `PH_1` feeding `hscnt[1]`, `PH_6` feeding an inferred `oLS166` latch, `auPH0` feeding `R6532:A6532_RIOT|s_dout[5]`, and `auPH0B` feeding `berzerk_sound_fx:U3D_6840|snd3[6]`. Confirm these exact fitted names in the new revision before using them as selectors.

## Limits and follow-up

This plan deliberately excludes `PH_6B`, `hscnt[5]`, `COINT`, CPU `AD[0]`, `NINC`, `TC10`/`TNEX`, counter-bit events, and `rst_sync`. Some have deterministic source relationships, but they are data/event-derived or participate in inferred latch/async-control behavior; a simple periodic-divider model is not justified by this plan. In particular, do not create a periodic clock for arbitrary counter/data outputs and do not false-path those paths to remove warnings. Review each event consumer and convert to a clock enable or provide a separately evidenced model.

The reset behavior and generated-clock startup phase need independent review: RTL initialization may not describe every device reset/configuration sequence. STA describes the constrained steady-state edge relationship; it does not prove reset release, metastability behavior, or board-level phase alignment. This plan also does not validate audio/game behavior. The paired-clock PIA test has passed, and root corrected the main CPU observation to sample the previous registered bus value; that functional result does not replace fitted timing checks for the return-byte path.
