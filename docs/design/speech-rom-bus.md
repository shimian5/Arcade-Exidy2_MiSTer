# Mouse Trap speech ROM bus adapter candidate

## Contract established from source

The T80 wrapper in `modules/cpu-t80/Z80.vhd` exposes active-high `mem_rd` and `io_rd`, an active-low `wait_n`, and the CPU's 16-bit address/data input. `T80s.vhd` registers its bus controls on enabled rising edges. During a memory read it keeps `RD_n` and `MREQ_n` active at T-state 2 while `WAIT_n` is low; it copies `DI` into its input register at T-state 2 only when `WAIT_n` is high (`T80s.vhd`, lines 159–188). Consequently the response byte must already be stable before the edge that observes `WAIT_n=1`.

The isolated speech store in `sim/expansion_adapter/exidy_expansion_loader_ram.sv` registers the addressed byte on `cvsd_clk` when `cvsd_read` is asserted and separately registers a one-cycle `cvsd_valid`. The bridge's remote read quarantine can delay acceptance; the read interface remains request/valid rather than combinational ROM. MAME's Mouse Trap speech map, pinned at commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` and cited in `docs/design/mousetrap-speech-reuse.md`, masks program addresses to 14 bits and maps ROM at `$0000-$3fff`.

## Candidate behavior

`rtl/speech_rom_bus.v` is an isolated adapter, not production integration. On the first active memory-read level it emits one `rom_read` pulse and captures `cpu_addr[13:0]`. It holds that address while the read is outstanding, waits for `rom_ready`, captures `rom_data`, then raises `wait_n` with the byte held stable. It does not issue another read until the CPU drops `mem_rd`. I/O reads bypass the adapter; writes are not handled. Active-high reset aborts the current state and initializes the data output to `$ff`.

The response-valid contract is one response pulse for each accepted request, with the data corresponding to the sampled address stable when `rom_ready` is asserted. Following reset, the adapter spends a guard cycle for the known one-cycle synchronous response, then waits until `rom_ready` is low before accepting a new request. The fixture injects a stale valid pulse across this window and proves it cannot release the first post-reset read. This drain depends on a bounded one-clock response latency; a variable-latency bridge must provide an explicit cancel/drained indication or reset the request/response endpoint together. The adapter has no transaction tag to distinguish arbitrarily late stale responses. Keep the speech CPU reset asserted until the ROM image and read-port protocol are ready.

The focused fixture `sim/speech_rom_bus/tb_speech_rom_bus.sv` models a synchronous one-clock ROM and checks the held wait, captured/masked address, stable response, one-read behavior under a held CPU strobe, I/O-read bypass, and reset abort/retry with a stale-valid negative case. Run it from the repository root with:

```sh
verilator --binary --timing -Wno-fatal --top-module tb_speech_rom_bus \
  --Mdir simulation/test-logs/speech_rom_bus-obj \
  rtl/speech_rom_bus.v sim/speech_rom_bus/tb_speech_rom_bus.sv -o sim
simulation/test-logs/speech_rom_bus-obj/sim
```

Observed with Verilator 5.052: `PASS speech ROM bus`.

## Limits before integration

The fixture does not instantiate T80 or prove its exact enabled-clock cadence, wait-state placement, or reset-release behavior. An attempt to analyze the exact `Z80.vhd` dependency chain with the supplied GHDL 6.0.0 succeeded (with the existing `T80_MCode.vhd` warning that local declaration `F` hides port `F`), but synthesizing the full wrapper to Verilog did not finish within the bounded run and was interrupted; no translated CPU was substituted. The wrapper's I/O interrupt-vector mux takes priority when its internal memory/I/O read controls are active; a future top-level mux must preserve that behavior. The candidate output byte is for ordinary memory reads only. The CPU clock-enable ratio, actual bridge response timing, late response handling beyond the one-cycle drain assumption, and end-to-end speech ROM fetches remain unverified. No ROM image, capture, or generated simulation output is part of this source change.
