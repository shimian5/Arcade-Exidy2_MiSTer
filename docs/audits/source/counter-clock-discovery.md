# Counter-pulse clock collection discovery

This adds a read-only post-fit inspection helper for the five registered pulse clocks in [counter-clock-constraint-plan.md](counter-clock-constraint-plan.md). Run it only after the full Quartus flow has completed:

```text
quartus_sta -t tools/timing/discover_counter_clocks.tcl
```

It opens the completed project timing netlist and existing SDCs, prints `report_clocks`, and writes collection details plus **diagnostic-only** generated-clock lines under ignored `simulation/timing-counter-clocks/`. The script does not source or apply its candidate output and does not write the production SDC. It errors if any keeper, fitted Q pin, PLL source pin, or source clock is missing or ambiguous. Quartus collections are opaque: the helper extracts entries with `foreach_in_collection`, never `lindex` on a Quartus collection.

The checked RTL hierarchy is `emu` top → `ex2` instance of `exidy2` → `sound_board` instance of `exidyAB`. The PLL hierarchy is `emu` → `pll` → `pll_inst`. Current STA inventory names use the `emu:emu|exidy2:ex2` and `exidyAB:sound_board` hierarchy. The script uses broad prefixes only to tolerate Quartus hierarchy-label spelling; final collections must each resolve to one object. The PLL output source selectors follow the full-flow names `emu|pll|pll_inst|altera_pll_i|general[0/2].gpll~PLL_OUTPUT_COUNTER|divclk`. The script records the exact fitted pin names it finds so the candidate constraints can use actual atom names.

The installed Quartus 17 Tcl implementation at `quartus/common/tcl/internal/qsta_ss_constrainer.tcl` uses `get_clock_info -targets` and `get_node_info -name` to map clock target nodes back to clock objects (for example, around lines 5197 and 5933). The helper follows that API to find a clock targeting the resolved PLL pin. It does not assume the pin name is also the clock object's name and avoids the unverified `get_clocks -of_objects` form.

The independent source-equation fixture `tools/timing/check_counter_pulses.py` verifies the source initializer, increment, comparator, first phase, one-parent-tick high width, and recurrence over 128 parent ticks. Its expected triplets are:

| Clock | Expected source edges | Relationship |
|---|---|---|
| `BCLK` | `{1 3 17}` | first source rising edge; divide 8; one parent tick high |
| `PH_1` | `{63 65 191}` | first rise at counter value 31; divide 64; one parent tick high |
| `PH_6` | `{1 3 129}` | first source rising edge; divide 64; one parent tick high |
| `auPH0` | `{1 3 33}` | first audio source rising edge; divide 16; one audio tick high |
| `auPH0B` | `{3 5 35}` | one audio tick after `auPH0`; divide 16; one audio tick high |

The source fixture is an RTL-expression guard and lightweight functional model, not a simulator. The post-fit discovery script is not yet run against the active build, so it does not establish that its register/Q-pin selectors match that fit. Review `discovery.txt`, the diagnostic SDC candidate, `existing-clocks.rpt`, fitted generated-clock propagation, and path reports before considering any constraint edit.

## `auPH0B` sampling contract still open

`auPH0` and `auPH0B` are registered from counter comparisons at `audio_clk`. Their rising pulses are one parent audio-clock edge apart, but the update ordering matters: when the counter's old value is one, the registered `auPH0B` rises while `auPH0` falls. The audio `T65` consumes the pre-edge `auPH0` value as `enable`, so it can advance on that same `audio_clk` edge that creates the `auPH0B` edge. The 6840 is clocked directly by `auPH0B` and samples T65-derived `cs`, `vs`, `addr`, and `di` signals.

Simulation scheduling can make both nonblocking updates appear settled by the time the 6840 block runs; this does not prove the physical setup interval. After generating the pulse clock, report setup and hold from the T65/audio bus source registers through address/write decode to the 6840 control/data registers, using the exact source-to-`auPH0B` edge relationship. A poor or negative path needs a source-synchronous enable or an RTL phase adjustment justified against MAME write semantics. Do not call the one-audio-cycle nominal pulse offset sufficient setup without this report. The same-edge contract and game-level bus ordering remain open until fitted paths and a bus-trace comparison are reviewed.
