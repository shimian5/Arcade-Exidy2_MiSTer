# Sprite and collision reference fixture

This is a bounded source-fragment Verilator test plus an event replay, not a full `Exidy2` CPU/game renderer simulation. The runner extracts exact selected equations from `rtl/Exidy2.v`, compiles them in a small wrapper with Verilator, and injects a short real MAME CPU-write excerpt from the accepted Venture capture. Independent expectations come from the pinned MAME driver register map, Venture collision configuration, and pixel-coordinate formulas.

The 18 captured writes from `active03` frames 2400–2402 (`bus.csv` SHA-256 `067B058E6E176FD195C06D514C21FF6BFD62AC55B66CA37B20E1EC1AD82D7B5B`) pass against the extracted latches: both object coordinate banks, `$5100` image nibbles, and `$5101` control tuple. MAME's map supplies the independent CPU-visible register addresses and raw write bytes. The fixture separately checks RTL's internal vertical latch convention (`rM1V/rM2V = bus byte + 1`, modulo 256); that is an RTL-fragment check, not evidence that MAME and RTL vertical coordinates match. M1/M2 horizontal and vertical reloads, byte wrap, coordinate boundaries, sprite graphics-address bank selection, collision truth cases, IRQ set, and `$5103`-select acknowledge clear pass. The event window contains 480 coordinate writes across frames 2400–2519; the fixture replays only the first three frames to keep the Verilator case small.

## Source-backed divergences

1. **Sprite address mirrors.** MAME maps `$5000/$5040/$5080/$50C0` with mirror mask `0x003f`; RTL's decoded strobes compare against the four exact addresses. A synthetic `$503F` write therefore has MAME's expected sprite-1-X result `$99`, while the extracted RTL retains the prior `$21`. Equivalent end-of-mirror probes cover all four banks. The accepted Lua tap canonicalizes addresses before writing `bus.csv`, so the captured game trace cannot tell whether the game used mirrors. The boundary case identifies a source difference; it does not establish a runtime effect.

2. **Control latch interpretation.** RTL captures `$5101` as `{ADSEL,M2R[4],M1R[4],CPL[4:0]}`. In pinned MAME, sprite 1 is conditionally drawn: its helper treats bit 7 high as disabled unless bit 4 overrides (or old hardware has no collision mask). Sprite 2 is drawn unconditionally; bit 6 selects its graphic set. Bits 5/6 select the graphic sets for sprites 1/2. This comparison is covered by synthetic low/high control values and actual captured `$F0` writes. The fixture checks the RTL tuple; it does not infer which sprite image is an arrow.

3. **Venture collision / IRQ policy.** Pinned MAME configures Venture with collision mask/invert `0x04/0x04`, so its collision timer accepts M1/background (`0x04`) and excludes M2/background (`0x08`) and M1/M2 (`0x10`). RTL `cDET` asserts for either sprite overlapping background outside blanking; that aggregate feeds the IRQ latch. The extracted RTL therefore requests an IRQ for a synthetic M2/background-only case where MAME Venture does not. RTL captures active-high M1/background into `EIR[2]`, while MAME's Venture invert maps the corresponding collision to bit 2 low. These are first source-level divergences under the fixture's input cases, not proof of the cause of a game symptom. MAME collision timer scheduling and RTL scan/pixel phase are not equated cycle by cycle.

MAME calls Motion Object 1 the player in its collision comments. The accepted traces and coordinate correlation establish a second moving object whose `$5080` sequence changes when Button 1 is held, but they do not prove that the sprite is an arrow/projectile. Sprite serialization, graphics-ROM identity and rendered MAME-versus-RTL frame alignment remain a separate follow-up. No ROM-derived bytes or images are stored in tracked files.

## Run and evidence

From PowerShell at the repository root, run the existing WSL Arch Linux Verilator/Make toolchain. Outputs, extracted source fragments, event include, logs, and binaries are ignored under `simulation/sprite_fixture/`.

```powershell
python tools/sprite_fixture/run_fixture.py --build-name reviewA
```

The runner writes `generated/fixture-report.json`, `generated/rtl_extracted.svh`, and `generated/replay_events.svh`, then compiles/runs the fixture. It returns nonzero on extraction, event expectation, compile, or simulation failure. A negative check intentionally flips the first independent expectation byte and must fail at the captured `$5100` event:

```powershell
python tools/sprite_fixture/run_fixture.py --build-name negative --inject-wrong-expected
```

The expected failure is a divergence at frame 2400, address `$5100`, with expected sprite-1 nibble `0` and actual `1`. Do not use this negative invocation as a passing simulation.

Reviewed hashes: `rtl/Exidy2.v` SHA-256 `C8AA3946DEDA06F6D4E371CC4F64DA7B6C99D6E599AA8F948C711AA60C0E51BD`; selected extracted fragment SHA-256 `E720A5C17E30C3D69B03A9FD9F0B8BA94979675B4A67D706A8792D8D336EEF22`; fixture driver SHA-256 `6893F026756DDAB6BBB02E89734798284ED8E1BC22C9828FA694FD189665C5EC`; testbench SHA-256 `8A18EA2688CF39A1CF129759DFBD845FF6FA7522CD56C5773F904A8840391B30`. Pinned MAME source is commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`; selected `simulation/reference_sources/exidy.cpp` SHA-256 `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486`. Verilator 5.052 completed the final run with all 18 replay events passing; the fault-injection run failed at its first intentionally incorrect latch expectation.
