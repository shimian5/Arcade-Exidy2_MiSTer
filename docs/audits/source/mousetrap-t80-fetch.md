# Mouse Trap speech CPU fetch fixture

The repository's actual T80 core can complete a short synthetic program with a one-edge synchronous ROM and a wait-state response. A second fixture reads the existing verified Mouse Trap speech image and checks its initial instruction fetches through the first I/O write. Together these fixtures establish bounded CPU/ROM timing behavior, not production speech integration.

`sim/mousetrap_speech/tb_t80_sync_rom.vhd` instantiates `modules/cpu-t80/Z80.vhd`, which instantiates the repository T80se/T80 implementation. The program performs `LD A,12h`, two immediate-port writes separated by an immediate-port read, a ROM data load from `$0100`, a memory write to `$2000`, and HALT. The ROM model samples a request on a rising edge, holds response data/valid until `mem_rd` drops, and deasserts active-low `wait_n` until that response exists. The test checks all 16 program/data fetch addresses in order, stable address while waiting, I/O addresses/data, and the final memory write value `A5h`. It completes at 885 ns with the PASS marker. The scoreboard stops at completion so post-HALT bus cycles are outside the tested contract.

The actual core's timing supports this protocol: `T80.vhd` stalls T-state 2 while `WAIT_n=0` (around lines 1272–1282) and captures `DI` on an accepted read; `T80se.vhd` registers the data input at T-state 2 only when `WAIT_n=1` (around lines 157–186). The wrapper `Z80.vhd` maps active-high `reset` to the core's active-low reset. The fixture holds reset for five rising edges and then runs with `clk_en=1`, `intreq=0`, `nmi=0`, and `busrq_n=1`.

Reproduction from PowerShell, with GHDL already installed in the workspace's Arch WSL distribution:

```powershell
wsl.exe -d archlinux -- bash -lc 'set -e; cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer; mkdir -p simulation/mousetrap_speech; cd simulation/mousetrap_speech; export LD_LIBRARY_PATH=/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -a --std=08 -fsynopsys -frelaxed ../../modules/cpu-t80/T80_Pack.vhd ../../modules/cpu-t80/T80_Reg.vhd ../../modules/cpu-t80/T80_MCode.vhd ../../modules/cpu-t80/T80_ALU.vhd ../../modules/cpu-t80/T80.vhd ../../modules/cpu-t80/T80se.vhd ../../modules/cpu-t80/Z80.vhd ../../sim/mousetrap_speech/tb_t80_sync_rom.vhd; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -e --std=08 -fsynopsys -frelaxed tb_t80_sync_rom; /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -r --std=08 -fsynopsys -frelaxed tb_t80_sync_rom --assert-level=error --stop-time=100us > run.log 2>&1; grep -q "PASS actual T80" run.log; tail -n 2 run.log'
```

GHDL 6.0.0 mcode completed successfully. It emits startup numeric_std metavalue warnings at time zero from the legacy core; the test's explicit completion marker appears at 885 ns and the run reaches the configured 100 µs stop time without an assertion failure. The source fixture and all simulator work products are separate: only the VHDL testbench is intended for source control; `simulation/mousetrap_speech/` is ignored.

The actual-image fixture `sim/mousetrap_speech/tb_t80_mtrap_rom.vhd` loads the 16 KiB byte-per-line hex image from the working directory and instantiates the actual T80 core with the one-edge synchronous ROM protocol. It verifies six consecutive fetch addresses, `$0000` through `$0005`, and checks that the first output address/data equal the immediate operands loaded from that image. It finishes at 345 ns. `sim/mousetrap_speech/run_mtrap_rom.ps1` reconstructs the payload bytes from the staged text image and checks its SHA-256 against the existing increment-07 manifest before compiling or running. The manifest identifies 16,384 raw ROM bytes, SHA-256 `96aabec1a71953afb98f4a28d090c9d2b3564cf7b487cf55604c96aaeba23bf0`, ordered as `mta_2a.2a`, `mta_3a.3a`, `mta_4a.4a`, `mta_1a.1a`. The staged ASCII hex file itself has SHA-256 `8a1ab5cb96ec5f40135329b47087bb33df48cf40afe6037b4732a92ec96e9e1b`. No ROM contents are embedded in the fixture or report, and no ROM bytes are added to source control.

To rerun the actual-image check from PowerShell, with GHDL available in the documented Arch WSL distribution:

```powershell
& .\sim\mousetrap_speech\run_mtrap_rom.ps1
```

SHA-256 provenance for this run:

| Source | SHA-256 |
|---|---|
| `modules/cpu-t80/Z80.vhd` | `6ad8a13c72d566414ab4e236204290a210f0e4df3b5e6db07def9d1c8c2bcb73` |
| `modules/cpu-t80/T80se.vhd` | `b54559bbddb2fe30f15794b6691ef6c10dd1b1ace3e3b29e92a22780560f1bf2` |
| `modules/cpu-t80/T80.vhd` | `4f4cd80ce371cea06ce0b954b2430b1081dbfb76e13049e1d261168718223bc7` |
| `sim/mousetrap_speech/tb_t80_sync_rom.vhd` | `22157dc4f31a562e7677ba06a6bd18f016d8d0c21aa15dba31b428dae9a005b6` |

The actual image came from already verified ignored staging; no fresh archive read was needed. The real-ROM test stops after the first output and does not run further firmware. Still untested: the production `speech_rom_bus` adapter joined to T80, firmware reset-release timing, Z80 clock-enable ratio, full I/O decoder semantics, interrupt behavior, actual index-6 loader handshake, and CVSD behavior. These fixtures prove the actual CPU can consume synchronous ROM responses; they do not prove physical speech works.

Independent root verification passes the synthetic program in fresh `simulation/mousetrap_speech_root/` and the manifest-guarded real-image boundary through `run_mtrap_rom.ps1`. The runner now creates a fresh sibling directory under ignored `simulation/mousetrap_t80_<timestamp>/` for each real-image run, so it needs no pre-existing simulator work directory. The CPU remains connected to the fixture's synchronous ROM responder, not the production speech adapter; joining those two independently tested components is still required.
