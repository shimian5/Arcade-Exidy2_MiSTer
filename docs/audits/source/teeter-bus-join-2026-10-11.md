# Teeter production bus and T65 join — 2026-10-11

## Result

ModelSim 10.5b passes a direct mixed-language test joining the production-selected `modules/cpu-t65/T65.vhd`, the production `rtl/teeter_controls.v`, and a generated module containing the actual ESR/profile declarations, registered Teeter read qualifier, controls instance, and registered CPU read mux extracted from `rtl/Exidy2.v` at HEAD `020b2ae`.

The synthetic 6502 program repeatedly executes `LDA $5101; STA $0200`. With a three-count spinner target, the first four actual T65 stores are `FF, FF, FF, BB`: each event sample carries bit 6 and positive direction bit 2, and the fourth read sees the idle byte after three per-read increments. A scoreboard observes the byte and qualifier on the shared PH_1 edge and checks `dial_consumed` advances from the direction in that exact registered byte. The run records six qualified consumptions across the test, including the later paused/resumed sequence.

The same real CPU and extracted production path force each higher-priority mux input in turn while the CPU is paused on `$5101`. RAM, ROM, screen RAM, character RAM, and extended-video RAM each return their distinct expected byte, clear `teeter_read_pending`, and leave the dial cursor unchanged. A non-Teeter PCB profile returns generic ESR `0x97` and does not consume dial state. A pending Teeter read held through multiple PH_1 periods while paused also leaves the cursor unchanged; resuming lets queued counts drain.

## Extraction and reproduction

`tools/teeter_bus/extract_fixture.py` extracts these source spans from committed `rtl/Exidy2.v`: the CPU input register and ESR definitions, the Teeter profile-selected `IN0` declaration, the `teeter_read_pending` register and strobe, the actual `TEETER_CONTROLS` instance, and the `CPU_databus_in` priority mux. It connects the production instance's diagnostic dial outputs so the fixture can inspect state. It does not reproduce the mux expression or the event/consumption logic by hand. Generated HDL and all simulator output remain ignored under `simulation/harness/teeter_bus/`.

Run from PowerShell:

```powershell
& .\tools\teeter_bus\run_fixture.ps1
```

The runner compiles the real T65 VHDL dependency chain, the generated production bus span, the production controls module, and `sim/teeter_controls/tb_teeter_bus_join.sv`. The passing run was `simulation/harness/teeter_bus/modelsim-20261011-160229-878/` and printed:

```text
PASS source-extracted production Teeter bus + actual T65: first_samples=ff,ff,ff,bb qualified_consumptions=6 priority_suppressions=5 generic=97 pause=held
```

The extracted source SHA-256 was `4b301356d097e67d64b1a10ee2a6afc606ad6fb37786177985ce74588108c3e5`. The run had zero simulator errors; ModelSim emitted 16 expected time-zero numeric_std/metavalue warnings from legacy T65 startup before reset settled.

## Boundary and limits

The test uses the real production mux, pending qualifier, profile selection, controls module, and T65, but provides testbench address-select signals and synthetic source bytes for the larger Exidy memory map. It does not instantiate the full production Exidy core or its U5C address decoder, load the Teeter ROM, or prove game playability. Quartus integration and MiSTer hardware acceptance remain separate checks.

Root independent replay passes the same source-extracted actual-T65 checks. Evidence: ignored `simulation/harness/teeter_bus/modelsim-20261011-160351-198/`. The wrapper/profile/QIP full-flow build remains a separate gate.
