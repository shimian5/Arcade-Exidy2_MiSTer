# T80 and speech ROM adapter join attempt

## Result

The actual T80 CPU now passes a direct mixed-language simulation with the production `rtl/speech_rom_bus.v` adapter. No CPU or adapter behavior was replaced with a behavioral mirror. ModelSim Intel FPGA Edition 10.5b compiled the real T80 VHDL dependency chain, the actual Verilog adapter, and `sim/mousetrap_speech/tb_t80_speech_join.sv`. The run completed at 1065 ns with `PASS actual T80 + production speechRomBus: reads=16 waits=31`, zero simulator errors, and 20 time-zero numeric_std metavalue warnings from legacy T80 startup.

The synthetic ROM program checks ordered instruction/data execution through a synchronous one-cycle memory model, adapter wait and data delivery, I/O read bypass (`IN` receives `5C`), both expected I/O writes, and the resulting `A5` memory write at `$2000`. The scoreboard checks exactly 16 request addresses in order (`$0000-$000A`, `$0100`, `$000B-$000E`), stable adapter address while the read strobe remains active, and rejects a duplicate request for any held `mem_rd` strobe. Exactly 16 requests and 31 sampled wait cycles were observed at completion. This proves the CPU and adapter meet this tested basic wait-state contract together. It does not exercise stale-valid/reset-drain recovery, high address masking, actual firmware execution through the adapter, CVSD logic, or hardware timing.

Run the fixture from PowerShell:

```powershell
& .\sim\mousetrap_speech\run_t80_speech_join.ps1
```

The script checks for all four installed ModelSim executables, creates a fresh ignored run directory under `simulation/mousetrap_speech/`, captures compile/simulation logs there, and requires the PASS marker. ModelSim `vsim -version` reported `Model Technology ModelSim ALTERA STARTER EDITION vsim 10.5b Simulator 2016.10`. `vcom` and `vlog` both exited with zero errors; `vsim` exited zero. The current source hashes are recorded below.

### Bounded GHDL translation attempt

An earlier fallback attempt analyzed the same VHDL dependency chain with GHDL 6.0.0, then tried to synthesize the full wrapper to Verilog with a 100-second bound. It left a 379,285-byte, 10,042-line partial file ending in a generated expression; the stderr file was empty, and no usable translation resulted. This result does not establish a source defect or explain why that translation ended. The partial files remain ignored under `simulation/mousetrap_speech/translation/`. Direct ModelSim mixed-language simulation made translation unnecessary for the present test.

## Integration contract and next path

The adapter's real interface takes active-high `mem_rd`, `io_rd`, address, `rom_ready`/`rom_data`, and returns `wait_n` and CPU data. Its request/address holding and response-drain state machine is described in `docs/design/speech-rom-bus.md`. The T80 wrapper exposes the corresponding `mem_rd`, `io_rd`, address/data, and active-low `wait_n`; it also has an interrupt-vector data mux that must remain ahead of ordinary adapter data for the wrapper's interrupt acknowledge behavior. The mixed-language fixture now verifies the normal one-cycle read response, held wait, returned instruction/data bytes, and I/O bypass together. Further bounded coverage should exercise adapter reset/drain with a stale-valid response and high-address masking before using it with a variable-latency production bridge. Actual Mouse Trap firmware execution through the adapter, loader handshake, CVSD integration, clock enable selection, and hardware timing remain open.

Source SHA-256 values for the join attempt:

| Source | SHA-256 |
|---|---|
| `rtl/speech_rom_bus.v` | `73b565d109676f20dce6b6b99b1991e194344b7d4c2730ec72ca84d7117b9d63` |
| `sim/mousetrap_speech/tb_t80_speech_join.sv` | `36f48b19e6b3cc7e3a07183cac7d6b5fb80dd7c49309f899fc313b23c2f35970` |
| `sim/mousetrap_speech/run_t80_speech_join.ps1` | `de8809bc197ba9e9e9a045a46367b4c3e218ec690397fbc0e53f95ac21d5fe33` |
| `modules/cpu-t80/Z80.vhd` | `6ad8a13c72d566414ab4e236204290a210f0e4df3b5e6db07def9d1c8c2bcb73` |
| `modules/cpu-t80/T80se.vhd` | `b54559bbddb2fe30f15794b6691ef6c10dd1b1ace3e3b29e92a22780560f1bf2` |
| `modules/cpu-t80/T80.vhd` | `4f4cd80ce371cea06ce0b954b2430b1081dbfb76e13049e1d261168718223bc7` |

No production RTL, MRA/QIP, ROM files, or Quartus outputs were changed. No physical speech or end-to-end firmware claim follows from these separate CPU and adapter fixtures.

Independent root replay of the strengthened exact-address/request scoreboard passes in fresh ignored `simulation/mousetrap_speech/modelsim-run-20261007-155215-994/`: exactly16 requests,31 wait cycles, expected I/O and memory write. This joins the actual CPU and adapter for normal synchronous responses; the variable-latency reset boundary remains a separate gate.
