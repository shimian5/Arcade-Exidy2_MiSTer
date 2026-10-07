# FAX answer-button control map

Date: 2026-10-07. Scope: compare the pinned MAME 0.288 FAX input map with the current Exidy2 input reads and existing MRA/profile conventions. Source review only; no MRA or production logic was changed. The user's selected control intent is four answer buttons for each player.

## Pinned MAME map

The local pinned board driver is `simulation/reference_sources/exidy.cpp` from MAME commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` (the source hash is recorded in `docs/design/integration-gates.md`). `fax_state::fax_map` maps `$1c00` to input port `IN3` and `$1a00` to `IN4` (`exidy.cpp:595-603`). The `fax` input definition assigns:

| Player | Address / port | Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bits 3:0 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `$1c00` / `IN3` | Button 1 | Button 2 | Button 3 | Button 4 | bit 0 Start 2, bit 1 Start 1, bits 2-3 unused |
| 2 | `$1a00` / `IN4` | Button 1 | Button 2 | Button 3 | Button 4 | unused |

All answer buttons and starts are `IP_ACTIVE_LOW` in MAME (`exidy.cpp:1058-1070`). `IN3` is the player-1 port despite its numeric tag; `IN4` is player 2. FAX 2 uses the same `fax` input configuration in the MAME game registration (`exidy.cpp:2616-2617`). These controls are separate from the ordinary `$5101` movement/start/coin port and the `$5213` Mouse Trap color buttons.

## Current core and profile gap

The current main-core read mux implements `$5101` from `ESR={coin,down,up,fire,left,right,start2,start1}` and `$5213` from `{4'b0,blue,1'b1,red,yellow}` (`rtl/Exidy2.v:127-128,175-179,599-612`). It has no `$1a00`/`$1c00` FAX input decode or two sets of four answer-button signals. Reads at those addresses are not wired to the MAME input ports. Consequently the four-answer-button mapping cannot be enabled by an MRA-only change; all eight button signals and address-read behavior still need a core implementation, plus a deliberate way to map available controller buttons to both players.

No FAX or FAX 2 release/candidate MRA exists in this tree. Existing release MRAs use index 1 for the options/PCB byte; current Pepper II and Hard Hat use `0x30`, while Mouse Trap uses `0x10`. The local synthetic expansion profile model labels FAX and FAX 2 with provisional `0x30` profile data and question-ROM indices (`tools/expansion_transport/model.py:20-24`), but explicitly calls the FAX flags provisional. That value is not validated as a production FAX board profile and does not encode button wiring. The profile should not be treated as approval to publish FAX/FAX 2 MRAs or as game support.

## Decision and next proof

Do not add a candidate FAX MRA in this bounded task. The repository has no FAX MRA template, no established production profile for FAX, and—decisively—the live input read path cannot respond to the four answer-button controls. An MRA would select ROMs/options but cannot supply the missing input mux. The relevant MAME ROM/control map is clear, but FAX/FAX 2 remain unsupported by this source evidence alone.

Before creating candidate MRAs, the core should define eight active-low answer inputs and map them to `$1c00`/`$1a00` exactly as above. Then add focused tests that assert each bit independently at each address, check start bits and unused bits, and test address decode priority against RAM/ROM. Only after that should a FAX/FAX 2 MRA be assembled using the expansion ROM indices and a profile byte validated from the board model; boot and question-bank behavior still need separate proof. No MAME runs, builds, commits, or production edits were made.
