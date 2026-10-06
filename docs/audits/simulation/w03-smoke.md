# W03 simulation harness smoke

Date: 2026-10-06. This is a deliberately small executable smoke fixture and a mixed-language tool-feasibility check. It is not an Exidy2 CPU, board, game, ROM, or sound acceptance test.

## Smoke fixture

`sim/harness/tb_exidy_ls139.sv` tests the actual `ls139` module in `rtl/ttl_chips.v`, a 2-to-4 decoder instantiated by `rtl/Exidy2.v`. It checks the disabled output and each selected output. The fixture does not model a CPU or claim full-core behavior.

From the repository root in Arch WSL, the exact command is:

```sh
make -C sim/harness smoke
```

Observed semantic result and process status:

```text
PASS tb_exidy_ls139 checks=6
exit status: 0
```

The complete Verilator run output is retained locally at ignored `simulation/harness/ttl_ls139/` (binary and build log). Generated binaries and logs stay under ignored `simulation/`.

## Selected VHDL route

`files.qip` selects `modules/6840/index.qip`, whose only source is `modules/6840/berzerk_sound_fx.vhd`. The adjacent `berzerk_sound_fx.v` is not selected by that QIP. A supplied Ubuntu 24.04 GHDL 6.0.0 package runs in Arch WSL without installation when its bundled `lib` directory is in `LD_LIBRARY_PATH`. `make -C sim/harness vhdl-check` analyzes the selected VHDL with Synopsys compatibility, synthesizes it to Verilog into ignored local output, and runs Verilator lint on that translation. Override `GHDL` and `GHDL_LIB` if the package is located elsewhere.

This route was exercised successfully: GHDL analysis/synthesis exited 0 and Verilator 5.052 lint exited 0. The synthesis diagnostic warns that port `sample` has no assignment. `rtl/audio_board.v` connects that port to `U3D_6840_sound` but builds its final audio signal from `snd1`, `snd2`, and `snd3`; the warning alone does not show a missing audible effect. Translation and lint establish tool compatibility only. No behavioral 6840 checks have been run, and GHDL's synthesis-to-Verilog output is not treated as proof that the VHDL and neighboring unselected Verilog agree.

For other VHDL blocks, the same candidate flow is `ghdl -a --std=08 --ieee=synopsys`, `ghdl --synth --std=08 --ieee=synopsys --out=verilog`, then Verilator. Each module needs its own dependency-ordered VHDL source list, testbench, semantic oracle, and review of GHDL synthesis limitations. This probe says nothing about the VHDL CPU, RIOT, PIA, RAM, or mixed VHDL/Verilog top. The CPU/RIOT/6840/RAM paths remain outside this smoke unit. For dual-clock RAM specifically, preserve the selected `rtl/dpram_dc.vhd` inference and same-address cross-port semantics; an asynchronous-read substitute is not validated here.

Exact feasibility target output in `simulation/harness/ghdl/` includes `berzerk_sound_fx.v`, `synthesis.log`, and `verilator-lint.log`. These are ignored generated artifacts; regenerate them with `make -C sim/harness vhdl-check`.

## Fingerprints and pinned reference

| Item | Version or SHA-256 |
| --- | --- |
| Verilator | 5.052, 2026-09-05; `/usr/bin/verilator`: `098b09b11ba7d3e904ae13d924a9e8dac8ced5c9d7c9beff3b9d36119a417581` |
| GNU Make | 4.4.1; `/usr/bin/make`: `9018663161af324a74326c035cfd05408cba13a26c1f6b801cf5f3195f2bee40` |
| Supplied GHDL executable | 6.0.0, mcode; SHA-256 `c7d63e138a5f2edb40c50f523465462d0bd707a8e2ff43c76a72ae5d393eab55` |
| Supplied GHDL shared library | `libghdl-6_0_0.so`; SHA-256 `e86160eb51dc2db2376f2f20a6dbc05e2bb0ce5f810c1ed2f0284640f6a79d73` |
| Exidy2 selected VHDL | `modules/6840/berzerk_sound_fx.vhd`; SHA-256 `7ef53f9625e0e24d4b4c49e766423603f4e95324bb5c439f867eb7a5705446f4` |
| Selecting QIP | `modules/6840/index.qip`; SHA-256 `1a41919214ee58448d86dc404c34f0edc94656dae0786e43c02985821c051c9f` |
| Exidy2 used decoder source | `rtl/ttl_chips.v`; SHA-256 `ba26c3d21e9bb6b433d7afcc3fb566d3bbd73ebdb2e24c335f4dd9eb7ef45e9e` |
| Generated GHDL Verilog | Local ignored `simulation/harness/ghdl/berzerk_sound_fx.v`; SHA-256 `ac6dea5a34c59d52a3829edec122e5f71841dfdfee7685bc62c0c2d93807c3b2` |

The MAME reference source is pinned to official tag `mame0288`, commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` ([official MAME 0.288 release/tag](https://github.com/mamedev/mame/releases/tag/mame0288), [resolved commit](https://github.com/mamedev/mame/commit/27a8d9e85b58058965907d1d8a7a92f8ed039348)). GitHub identifies the release tag as signed and verified. This is a source revision pin; it does not establish a byte-for-byte match with the locally installed MAME executable.

## Remaining coverage

This unit only opens a repeatable smoke path and makes the selected 6840 VHDL translation route concrete. It does not execute CPUs, RIOT, PIA, 6840 transactions, dual-clock RAM, sound ROMs, MAME, or a game. Those need separate semantic fixtures and evidence before their W03 acceptance cells can be marked complete.
