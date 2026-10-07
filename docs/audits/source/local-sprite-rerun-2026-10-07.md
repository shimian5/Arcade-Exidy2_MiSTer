# Sprite fixture rerun — 2026-10-07

The source-fragment sprite fixture was rerun against the accepted Venture `active03` MAME trace using the incoming profile-0 compatibility substitution. No production RTL or MAME/ROM capture was edited. Verilator 5.052 ran from the installed Arch WSL environment; no Quartus work was performed by this worker.

## Commands and results

Positive replay from PowerShell at the repository root:

```powershell
py -3 tools/sprite_fixture/run_fixture.py --build-name luna_rerun_20261007 --run active03
```

The Windows Python driver invoked WSL and ran:

```sh
cd '/mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/sim/sprite_fixture' && make BUILD_DIR=../../simulation/sprite_fixture/luna_rerun_20261007 GEN_DIR=../../simulation/sprite_fixture/generated
```

The command returned **0**. Extraction and the selected MAME event replay passed. All 18 writes from frames 2400–2402 passed, including six writes per frame at `$5100`, `$5101`, `$5000`, `$5040`, `$5080`, and `$50C0`. The source trace contains 11,228 accepted bus-write rows and 480 coordinate-write rows in the right/fire window. The positive build and run logs are ignored under `simulation/sprite_fixture/luna_rerun_20261007/`.

The documented fault control was also run:

```powershell
py -3 tools/sprite_fixture/run_fixture.py --build-name luna_rerun_20261007_negstatus --run active03 --inject-wrong-expected
```

It returned **1**, as expected. The intentionally flipped first expectation is rejected at frame 2400, `$5100`: input `$F1`, expected M1 nibble `0`, actual M1 nibble `1`; expected and actual M2 nibble are both `$F`. Its logs are in ignored `simulation/sprite_fixture/luna_rerun_20261007_negstatus/`.

## Profile-0 extraction check and provenance

The live `rtl/Exidy2.v` at this rerun has SHA-256 `4F39C4C29863E3C0FA0C61C574711C72B42A67A251FAEE85A3E785C35685FC2E`. Its active EIR assignment uses the profile-selected `int_cause[4:2]`, and the active collision strobe name is `cDET_sel`. The fixture's documented profile-0 substitution replaces those with the legacy baseline EIR expressions and `cDET`. I checked the generated `simulation/sprite_fixture/generated/rtl_extracted.svh`: it contains no `int_cause` or `cDET_sel`, and its EIR assignment is:

```verilog
always @(posedge rCPU_IRQ) EIR <= {!vscnt[8],!m_coina,!m_coinb,!(nM01VDT|nM02VDT),1'b0,!((nSGCVID|nM01VDT)|CBLB),2'b00};
```

The fragment SHA-256 is `E720A5C17E30C3D69B03A9FD9F0B8BA94979675B4A67D706A8792D8D336EEF22`; it matches the fixture's documented profile-0 fragment hash. The updated driver SHA-256 is `A34017483F20AE95BA447DC24C8D481119F6364EA101FE228B708333F891260E`; testbench SHA-256 is `8A18EA2688CF39A1CF129759DFBD845FF6FA7522CD56C5773F904A8840391B30`.

The replay trace is `simulation/venture_startup/active03/bus.csv`, SHA-256 `067B058E6E176FD195C06D514C21FF6BFD62AC55B66CA37B20E1EC1AD82D7B5B`. The pinned `simulation/reference_sources/exidy.cpp` has SHA-256 `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486` (pinned source commit recorded in the existing sprite-fixture report: `27a8d9e85b58058965907d1d8a7a92f8ed039348`).

The fixture remains a bounded extracted-RTL and bus-event test, not a full CPU or game-renderer simulation. It does not identify the moving sprite as an arrow or projectile, prove whether MAME used mirrored write addresses (the accepted tap canonicalizes them), validate whole-system collision scheduling, or establish that Venture issue I05 is fixed. Existing documented MAME-versus-RTL collision policy differences remain.
