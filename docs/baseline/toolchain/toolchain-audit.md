# Exidy2 toolchain and source baseline

Audit date: 2026-10-06. This is a source/tool inventory; only read-only tool discovery and version queries were run. No Quartus flow, HDL compilation or simulation was run. Findings are not a compile result.

## Project and source selection

`Arcade-Exidy2.qpf` names revision `Arcade-Exidy2`; its header records Quartus Prime Lite 17.0.2 Build 602 (2017-07-19), while the revision setting says 17.0. `Arcade-Exidy2.qsf` selects `sys_top`, Cyclone V `5CSEBA6U23I7`, generates an RBF into `output_files`, and enables `MISTER_FB=1`. It sources `sys/sys.tcl`, `sys/sys_analog.tcl`, and `files.qip`; it directly includes the core top, `Arcade-Exidy2.sdc`, `rtl/index.qip`, `sys/sys.qip`, CPU/RIOT QIPs, and several additional QIPs through `files.qip`.

The checked-in source hierarchy resolves through the QIP declarations: `rtl/index.qip` selects `Exidy2.v`, `audio_board.v`, `rom_loader.sv`, `ttl_chips.v`, `hiscore.v`, `pause.v`, and `dpram_dc.vhd`. `files.qip` selects CPU t65/t80, 6840, PIA, RIOT, JT misc and K580 modules. `sys/sys.qip` selects the MiSTer top/framework modules plus a Quartus-version-dependent PLL QIP (`pll_q17.qip` under this project version). The QIP files and their declared HDL sources were inspected on disk; this was not a Quartus parser/elaboration check.

Constraints: `Arcade-Exidy2.sdc` defines external 50 MHz clock inputs and generated PLL clocks, clock groups, false paths and a multicycle path. `sys/sys.tcl` sets the target family/device; `sys/sys_analog.tcl` supplies board pin/IO assignments. `sys/sys.qip` also declares `sys/sys_top.sdc`. The project has legacy auto-generated broad false-path exceptions; their adequacy and coverage require TimeQuest reports from the full flow.

Two QSF support references are absent in this checkout: `jtag.cdf` and `stp/audio_board_newpia.stp`. The SignalTap assignment is present and SignalTap is enabled. Their absence is a source observation only; no claim is made that either causes the full flow to fail. No other missing file was demonstrated by this bounded inspection.

## Tool availability and commands

An Intel FPGA Lite installation exists at `C:\MiSTerDev\intelFPGA_lite\17.0`; `quartus_sh.exe` and `quartus.exe` exist in its `quartus\bin64` directory. Windows `FileVersionInfo` fields are blank. The integrator therefore ran a read-only `quartus_sh.exe --version` query from unsandboxed PowerShell and confirmed **Version 17.0.2 Build 602 07/19/2017 SJ Lite Edition**. Quartus is absent from this PowerShell session's PATH. Per the project-wide instruction, when an authorized build is requested, run the full flow from an **unsandboxed PowerShell** session, from the project root:

```powershell
& 'C:\MiSTerDev\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe' --flow compile Arcade-Exidy2
```

Do not use individual Quartus stages as a substitute. This command is recorded as a future build command and was not executed.

`Get-Command` found Python 3.13 and Git, but no `verilator`, `iverilog`, `vvp`, `ghdl`, `make`, or Quartus commands in PowerShell PATH. A `_tools\ghdl6` directory contains an Ubuntu 24.04 GHDL 6.0.0 package, not a native Windows executable. The first `wsl --list --quiet` call returned `E_ACCESSDENIED` in the sandbox; one read-only unsandboxed retry succeeded and listed `archlinux` and `Ubuntu`. Bounded `command -v` checks found Verilator and GNU Make 4.4.1 in Arch Linux, GNU Make 4.3 in Ubuntu, and no Icarus (`iverilog`/`vvp`) or GHDL in either distribution. Arch reports Verilator 5.052 (2026-09-05). These checks establish tool availability, not simulation readiness; the Victory harness also requires a C++ toolchain and its targets were not run.

There is no Exidy2 simulation directory or simulation Makefile in the repository root. The local Victory project provides useful harness patterns but is not an Exidy2 regression: `C:\MiSTerDev\Arcade-Victory_MiSTer\sim\README.md` and `sim\Makefile` document `make test` and focused targets for CPU, board, graphics, frontend, video, sound and NVRAM; its Verilator/GHDL commands and synthetic/reference ROM prerequisites are specific to Victory. Adapt the harness structure and identify Exidy2 DUT-specific contracts before reusing tests. No Victory tests were run.

## Baseline gaps and next actions

1. Build the full Quartus project only at the W15 gate, from unsandboxed PowerShell, and preserve the complete log, reports, RBF hash and timing/resource evidence.
2. Resolve whether the absent CDF/SignalTap file references are intentional or need to be supplied/removed after inspecting a full-flow diagnostic; do not classify them as compile failures in advance.
3. Establish Exidy2-specific testbench top(s), source lists and expected ROM fixture handling, then use the available WSL Verilator/Make toolchain where suitable; currently only the RTL project hierarchy is explicit.
4. Review SDC exception coverage against actual TimeQuest clocks and paths after a successful full compile.

