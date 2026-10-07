# FAX / FAX 2 controls read candidate

This source-only candidate implements the MAME FAX answer/start input bytes and gives the eventual MRA button naming proposal. It is not wired into `Arcade-Exidy2.sv`, `rtl/Exidy2.v`, QIP, or any MRA. No production build or game validation was run.

## Input reads

The pinned board-source audit in [`docs/audits/source/fax-controls.md`](../audits/source/fax-controls.md) records MAME’s `fax_map`: `$1c00` reads `IN3` for player 1, and `$1a00` reads `IN4` for player 2. `rtl/fax_controls.v` takes active-high pressed signals and generates the MAME active-low bytes:

| Address | Result bits | Idle value |
| --- | --- | --- |
| `$1c00` P1 | bits 7:4 Answer 1–4; bit 1 Start 1P; bit 0 Start 2P; bits 3:2 high/unused | `0xff` |
| `$1a00` P2 | bits 7:4 Answer 1–4; bits 3:0 high/unused | `0xff` |

Each answer signal independently pulls down its matching bit. P1 start signals pull down bits 1 and 0 respectively. The required `fax_enabled` profile gate must be asserted only for a validated FAX/FAX2 profile. Disabled profiles, non-selected addresses and non-read cycles pass through `other_read_data`. `fax_selected` identifies either selected read. The module is stateless, so reset has no behavior.

The decoder selects FAX input bytes over `other_read_data`, which allows a focused simulation of a conflicting lower-priority RAM value. During integration, the FAX address decode must be applied before a later RAM/ROM mux can override it. The MAME FAX map assigns `$1c00` and `$1a00` to inputs; the FPGA’s shared memory/address map still needs explicit priority review alongside any Exidy2 RAM/ROM regions and new expansion reads.

## MRA button element proposal

Use this button element only when constructing the eventual FAX/FAX 2 MRA after core bindings exist:

```xml
<buttons names="Answer 1,Answer 2,Answer 3,Answer 4,Start 1P,Start 2P,Coin A,Coin B,Pause"
         default="A,B,X,Y,Start,Select,L,R" />
```

The four answer labels default to face buttons A/B/X/Y in order. The defaults follow local release MRA conventions, for example the [Robotron 2084 MRA](C:/MiSTerDev/Arcade-Robotron_MiSTer/releases/Robotron%202084.mra) and [Victory MRA](C:/MiSTerDev/Arcade-Victory_MiSTer/releases/Victory%20(Exidy).mra). Pause is intentionally unassigned by this eight-button default list and needs user remapping or a separately defined pause shortcut. Start 1P/2P, Coin A/B, and Pause labels follow the existing Exidy top-level `J1` configuration in `Arcade-Exidy2.sv`. The XML is an element proposal, not a runnable MRA; this core has no validated FAX/FAX 2 MRA profile.

The production profile gate must preserve ordinary RAM reads at these addresses for all other games. The eventual input binding needs `hps_io.joystick_0` for player 1 and `hps_io.joystick_1` for player 2, with each player’s four face-button inputs routed to the four answer signals. The current top only connects `.joystick_0(joystick_0)` and only defines a `J1` button list. The P2 signal mapping, shared start/coin policy, player count/controller behavior, and exact settings exposure need to be settled as part of integration. The proposed MRA label list and current `J1` OSD list are not themselves proof that the eight signals are available.

## Verification

[`sim/fax_controls/tb_fax_controls.sv`](../../sim/fax_controls/tb_fax_controls.sv) checks all eight answer buttons independently, both P1 starts, simultaneous combinations, idle and unused bits, exact address/read selection, disabled-profile preservation, pass-through behavior, and FAX-read priority over conflicting fallback data. The source has no state to reset.

Run from the repository root in Archlinux WSL:

```sh
verilator --binary --timing -Wno-fatal --top-module tb_fax_controls \
  --Mdir simulation/test-logs/fax-controls-obj \
  rtl/fax_controls.v sim/fax_controls/tb_fax_controls.sv -o sim
simulation/test-logs/fax-controls-obj/sim
```

This candidate does not validate MAME gameplay, P2 physical layout, MRA loader interpretation, core address priority, FAX/FAX 2 profile selection, or ROM/question-bank execution.
