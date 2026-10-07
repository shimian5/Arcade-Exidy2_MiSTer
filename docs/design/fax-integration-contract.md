# FAX / FAX 2 input integration contract

This is a source-backed integration proposal for the existing standalone [`faxControls`](../../rtl/fax_controls.v) helper. It does not change production RTL, QIP, or MRAs. Source review supports a distinct FAX/FAX 2 index-1 byte using currently unassigned `pcb[3:2]`, but those proposed metadata bytes still need owner/MRA and board-profile validation. The complete question-ROM loader contract is also still required.

## Current binding points

`sys/hps_io.sv` exposes `joystick_0[31:0]` and `joystick_1[31:0]`, but `Arcade-Exidy2.sv` currently declares only a 16-bit `joystick_0` wire and connects only `.joystick_0(joystick_0)`. The top-level button inputs come from active-high HPS bits, then are inverted at the Exidy port bindings: P1 directions use `joystick_0[0:3]`, four buttons use `[4:7]`, starts use `[8:9]`, coins use `[10:11]`, and pause uses `[12]`. The corresponding P2 four-button signals can use `joystick_1[7:4]`, subject to confirming the framework's second-controller button-index behavior on hardware. The helper takes active-high pressed inputs, so the proposed bindings are `joystick_0[7:4]` for P1 and `joystick_1[7:4]` for P2; P1 starts are `joystick_0[8]` and `[9]`.

`rtl/Exidy2.v` currently has no `$1c00` or `$1a00` FAX input branch. Its `CPU_databus_in` register selects RAM, program ROM, screen RAM, character RAM, extended video, then I/O bytes including the generic `$5101` ESR. The FAX helper's selected data must be inserted as a leading branch of this mux so a selected FAX read takes priority over any ordinary RAM/ROM decode. Its exact address/read predicates are `$1c00`/P1 and `$1a00`/P2 with `CPU_RWn` high. Preserve the rest of the mux verbatim for all other reads. Since `CPU_databus_in` is registered each `master_clock`, the FAX byte and address decode are captured together for the next T65 sample, just like existing input sources.

Proposed helper bindings, once the profile gate exists:

```verilog
.p1_answer_pressed(joystick_0[7:4]),
.p2_answer_pressed(joystick_1[7:4]),
.p1_start1_pressed(joystick_0[8]),
.p1_start2_pressed(joystick_0[9])
```

Keep the helper's active-low returned bytes: P1 `$1c00` has answer buttons in bits 7:4 and starts in bits 1:0; P2 `$1a00` has answer buttons in bits 7:4. The MAME input definition leaves the other bits high. The helper is stateless; the profile/readiness gate must disable it until the correct image has completed its load.

## MRA button metadata proposal

Use the current Exidy MRA convention for a player's four face buttons and existing shared start/coin/pause labels:

```xml
<buttons names="Answer 1,Answer 2,Answer 3,Answer 4,Start 1P,Start 2P,Coin A,Coin B,Pause"
         default="A,B,X,Y,Start,Select,L,R" />
```

This names P1's four answer inputs and the existing P1 system controls. The same face-button indices on the second controller feed P2's four answer inputs through `joystick_1[7:4]`; the metadata does not require separate `P2 Answer` labels because those are the same controller button positions on a distinct player port. Existing top-level coin and pause bindings remain available, although the FAX answer-port helper does not add coin bits to `$1c00` or `$1a00`. This is a button-element proposal only, not a runnable MRA.

## Profile and transport gate

Do not gate FAX controls on `pcb[7:6] == 2'b01` alone. `rtl/Exidy2.v` passes these two bits to `exidyIntCause`: profile `01` is Venture/FAX interrupt wiring, while the same value also applies to candidate Venture. Profile `11` is Teeter Torture and profile `10` is Pepper II/Hard Hat; changing the interrupt-profile selector to create an FAX-only value would collide with those established meanings. Current released MRAs use baseline values with the upper two bits clear; the candidate Venture changes index-1 byte `0x10` to `0x50`, Pepper II/Hard Hat change `0x30` to `0xB0`, and the Teeter candidate uses `0xD0`.

The byte `0x50` is therefore not an FAX identity: it selects Venture/FAX interrupt behavior and has already been proposed for Venture. `0xD0` remains reserved for Teeter's interrupt behavior. The source offers a simpler distinct identity in unused `pcb[3:2]`, while preserving the board and interrupt fields. Proposed exact index-1 bytes are `0x74` for FAX and `0x78` for FAX 2:

| Bits | Proposed value | Existing source meaning |
|---|---:|---|
| `[7:6]` | `01` | FAX/Venture collision IRQ wiring |
| `[5:4]` | `11` | FAX board map/layout and CPU-audio-board selection |
| `[3:2]` | `01` FAX / `10` FAX 2 | New exact image identity tag |
| `[1:0]` | `00` | Existing low option bits; retained (palette table applies when `pcb[4]=0`) |

This low-bit tag is source-compatible with current consumers. A whole-tree search finds no direct `pcb[3]` or `pcb[2]` read. The only expression that includes them is `pcb[4:0] == 5'b00010` in `rtl/audio_board.v`; both proposed FAX bytes set `pcb[4]=1`, so that exact legacy Targ-tone condition remains false, as it is for the existing CPU-audio-board flag. The audio outputs choose CPU-generated audio whenever `pcb[4]=1`. `pcb[5]=1` selects the `$6000-$67ff` character-RAM address region and is appropriate for pinned MAME's FAX map, which assigns character RAM at `$6000-$6fff`; the current RTL separately routes `$6800-$6fff` through `EXTVID`, so this byte proposal does not establish full character-memory parity. FAX's machine config inherits `pepper2(config)`, consistent with the existing CPU-audio-board path. The exact bytes retain `pcb[7:6]=01` for FAX IRQ semantics and do not alter Teeter's `0xD0` value. Parsing all current release and candidate MRA index-1 first bytes found no `0x74` or `0x78` collision; current values are `0x01`, `0x02`, `0x10`, `0x30`, `0x50`, `0xB0`, and `0xD0`.

The unintegrated synthetic expansion-transport model already has separate FAX/FAX2 descriptor IDs and question data at index 5, but currently expects provisional PCB flag `0x30`. If that model becomes the loader contract, update its FAX expected flags to `0x74` and FAX2 to `0x78`, and reject any descriptor/PCB mismatch. Those descriptor IDs remain useful for validating extension-stream shape; they need not be a second FAX identity source for the input helper. Eventual `fax_enabled` should require exact `pcb == 8'h74 || pcb == 8'h78` plus `fax_questions_ready` from a validated loader. That exact byte gate separates FAX from Venture and Teeter without consuming a new image index solely for identity. These values are a source-compatible proposal, not validated MRA bytes or proof of game support.

Recommended gate for eventual integration: use the exact proposed PCB byte (`0x74` or `0x78`) together with `fax_image_valid` and `fax_questions_ready` from the implemented loader. Keep `pcb[7:6] == 2'b01` separately for Venture/FAX IRQ wiring. The loader must clear validity on a new download/reset, reject mismatched descriptor/PCB values and wrong or incomplete region lengths, and assert readiness only after all required question banks are populated. The synthetic index-7 descriptor IDs may remain the transport manifest IDs and map to the exact PCB byte; a second independent game-identity selector is unnecessary if this relationship is validated.

## Required integration and acceptance evidence

Before production wiring, settle and validate the MRA descriptor/profile bytes for both games; implement the question-ROM transport and exact bank-fill policy; connect the 32-bit HPS P1/P2 vectors; add `faxControls` to `rtl/index.qip`; and put the helper's selected data ahead of the current `CPU_databus_in` read priorities. Preserve the existing `$5101` ESR and all non-FAX read values for every non-FAX image.

Then test both profile IDs and disabled/loading states, independent and simultaneous answers on both players, P1 starts, idle high bits, exact address/read qualification, and a conflicting ordinary memory read to prove FAX priority. Verify that every other profile keeps its existing `$1a00`/`$1c00` behavior. Hardware acceptance must also confirm that two controllers' A/B/X/Y produce the intended player answers and that the MRA labels/defaults are interpreted as expected by the running MiSTer framework. The existing [`tb_fax_controls.sv`](../../sim/fax_controls/tb_fax_controls.sv) covers the standalone helper only; it does not validate any of these source bindings or the loader.
