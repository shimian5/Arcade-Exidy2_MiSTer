# Venture PIA input and CA1 ordering in pinned MAME

> **Correction:** the earlier runtime interpretation in this document is superseded by the callback-order audit in [pia-response-mismatch-review.md](pia-response-mismatch-review.md). The seven timestamp-paired PA=`40` reads occurred earlier in CSV callback order than the PB=`00` writes. The apparent stale responses were an artifact of sorting per-CPU `mame.time()` values across CPUs. The runtime sections below must not be read as evidence that those writes left the PIA state unchanged or that a stale read followed them.

## Result

The pinned MAME 0.288 `pia6821_device` does not have a CA1-controlled Port A input latch. In `control_a_w`, CRA bit 5 is the CA2 direction selector (`c2_output`), not a Port A latch enable. `get_in_a_value()` reads the current external-input value and merges it with output bits according to DDRA; `porta_w()` updates that input value directly. `ca1_w()` only tracks CA1 state and sets the IRQ flag on the configured edge. There is no operation that snapshots PA data when CA1 changes.

This rules out the proposed explanation that CRA=`0x2C` snapshots the previous `0x40` before a following PB write of `0x00`. In fact, bit 5 of `0x2C` selects **CA2 output**; bit 4 is zero, selecting CA2 strobe mode; bit 3 is one, setting its output high. Bit 2 selects the PA data register, bit 1 selects falling-edge CA1 flagging, and bit 0 disables IRQ output. The IRQ flag can still appear in CRA reads when bit 0 is clear.

## Exact callback order

The soundboard routes its PB callback to the main PIA's `porta_w`, and its CB2 callback to the main PIA's `ca1_w` ([pinned Exidy configuration](../../../simulation/reference_sources/exidy.cpp#L1619)). The sound PIA PB output handler forwards its byte through `m_pb_callback` ([pinned sound header](../../../simulation/reference_sources/exidysound.h#L137)). In the pinned 6821 source, `port_b_w()` stores the output latch and calls `send_to_out_b_func()` before it performs any CB2 write strobe. `send_to_out_b_func()` computes `m_out_b & m_ddr_b` and invokes the write handler. With DDRB=`0xFF`, a PB write of `0x00` therefore sends `0x00` through the callback chain to main PA input before the CB2 strobe can cause the main CA1 edge.

So, for an actual mapped PB write in captured CRB=`0x2C`/DDRB=`0xFF` state, the PIA's own operation order predicts main PA input becomes `0x00` before the edge that sets main CA1. A later main PA read should then return `0x00` with DDRA=`0x00`. The previously cited seven trace pairs do not test that sequence: callback order puts their PA reads before the PB writes. The 6821 latch theory is unsupported, and those pairs provide no write-before-read discrepancy to explain.

## Relationship to the seven frozen events

The seven formerly paired events are qualified accesses, but callback row order places each main PA=`0x40` read before its apparent audio PB=`0x00` write. Their timestamp differences of 337–361 µs are not elapsed latencies. The corrected row-order finding and first pair's rows are recorded in [pia-response-mismatch-review.md](pia-response-mismatch-review.md).

The callback-row ordering removes the apparent write/read conflict. The bus CSV still does not expose callback invocation or pin values, so it cannot validate the runtime handoff for a genuinely ordered write followed by read.

## Source provenance

The source files were fetched from the public MAME repository at pinned commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` and kept only in the ignored `simulation/reference_sources/` directory:

| File | SHA256 |
|---|---|
| `src/devices/machine/6821pia.cpp` | `9EC05BF851920883D74AEA55062377D401F758D4E3C460A068013DEC912909F3` |
| `src/devices/machine/6821pia.h` | `B37F5735EB0CB1B7CE27B0ED17155855CD6676B96AB70116082FCF684B6A10A1` |
| `src/mame/shared/exidysound.h` | `EFA3A7515169D91C4BA26C9FF49D3BF37E19A77319DDAB2ACE704974C579D92E` |

Relevant definitions are in `6821pia.cpp`: `get_in_a_value()` (line 205), `port_a_r()` (391), `control_a_r()` (483), `send_to_out_b_func()` (633), `port_b_w()` (689), `set_a_input()`/`porta_w()` (848/864), and `ca1_w()` (900). The control-bit helpers at line 1118 define CRA bit 5 as CA2 output selection. The local Exidy sources and frozen trace metadata identify the same MAME commit.

The source-only review required no MAME run, ROM access, Quartus build, or production edit. The exact-source analysis alone is not proof that the FPGA implementation matches MAME's callback timing; the focused instrumentation below narrows the runtime discrepancy but still cannot observe callback invocation directly.

## Focused MAME save-item instrumentation

A follow-up MAME 0.288 run used Lua's `emu.item(...):read(0)` on PIA save items (`m_in_a`, `m_ddr_a`, `m_ctl_a`, `m_in_ca1`, `m_irq_a1`, `m_out_b`, `m_ddr_b`, `m_ctl_b`, `m_out_cb2`) while existing CPU-space read/write taps recorded the game’s normal accesses. The script performs **no PIA register reads**, so it does not acknowledge either PIA's interrupt flags. It classifies audio offset `$1002` using the live saved CRB bit 2 and also observes any audio DDRB/CRB or main DDRA/CRA writes. It records the tap's bus byte and write mask separately from the live PIA output/input state.

The older state-run3 analysis associated seven pre-handler audio write taps with PA reads by timestamp; that association was invalid across CPU-local times. Its saved-item values do not establish post-write state at a later causal PA read. The tap observes the CPU transaction before its mapped handler and cannot by itself prove that the handler or output callback completed. Other observed `$00` sequences remain observations, not a controlled comparison proving the disputed ordering.

The bus write tap records a CPU write transaction before the mapped PIA handler; it is not a post-handler observation. Since the PA reads in question precede these writes in callback order, the cited state samples cannot establish a contradiction between handler behavior and a later read. The available Lua tap API still does not expose the output callback boundary, and this run makes no FPGA parity claim.

The focused output and all captured artifacts remain under ignored `simulation/pia_mismatch_instrument/state-run3/`; the raw event log is not part of this source report. The reproducible state probe is [probe_pia_items.lua](../../../tools/pia_firmware_timing/probe_pia_items.lua), SHA256 `029A852F95657A817F851E381B2687FB0CE4C9616E75AC70931402A7183E7BDB`; the boundary logger is [mismatch_state_trace.lua](../../../tools/pia_firmware_timing/mismatch_state_trace.lua), SHA256 `69D9243B55EBFB7D1B877929C959C7708F958A9C524994C78986CD4434FE8864`. It ran MAME 0.288 (binary SHA256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`) from an isolated working directory with `-noreadconfig -nowriteconfig -skip_gameinfo -video none -sound none -nothrottle -nosleep -noplugins -autoboot_delay 0 -seconds_to_run 80`; the Lua script exits at frame 4500 and applies the same coin/start inputs as the frozen capture. It reproduced the relevant event timestamps. The Venture PIA map is `$1000-$1003` mirrored through `$17ff`, and each cited audio access uses base address `$1002` with full-byte mask `FF`; callback-row order, not timestamp order, determines the event sequence.

The Lua API exposes no `side_effects_disabled` flag; it reported no debugger object in this run, which executed the CPU normally. The read taps added no PIA register reads. A mapped write-handler/output callback hook would be needed to observe the full handoff directly; it is no longer motivated by the timestamp-paired seven cases, which were in the opposite callback order.

## Write-tap validity audit

The write tap is a pre-handler observation, but it is not a replacement handler. In the pinned `handler_entry_write_tap::write()` and `write_interruptible()` implementations, MAME calls the tap and then synchronously forwards the same `offset`, `data`, and `mem_mask` to `m_next`. The Lua binding wraps that callback and only substitutes the data if the Lua callback returns an integer; these capture callbacks return nothing (`nil`), so they leave the transaction unchanged. `install_write_handler_helper()` creates the mapped write delegate before the tap is installed; `install_write_tap()` wraps the existing write path as a passthrough. This establishes that the tap sees a write request before the mapped handler and that the handler call follows in the same call stack. The tap alone does not observe the handler's post-state or prove that a device callback changed its state.

For all seven timestamp-associated events, captures show audio PC `$5C33` writing `$00` to `$1002` with `mem_mask=$FF`; because the associated PA reads precede these write rows, save-item samples from this filtered sequence cannot establish that a later read retained `$40`. The original trace's status/data reads are ordinary CPU accesses; the MAME Lua API used here exposes no `side_effects_disabled` or debugger execution-state control. Its metadata reports no debugger object, and the accesses are from the running audio/main CPU PCs. This supports normal CPU execution but does not expose a C++ `side_effects_disabled` flag.

The Exidy map binds `$1000-$1003` directly to the sound PIA's `read`/`write` delegate, with mirror mask `$07FC`. `$1002` is in the base range, and the raw bus trace reports that base address, so this is not an alternate mirrored register. Its full-byte mask is `FF`. There is no second audio write to the PIA in the first disputed event's following 0.8 µs, and the full interval to the main PA read contains no audio PB/DDR/CRB or main PA DDR/CRA write. NMOS 6502 read-modify-write operations do issue two writes to the effective address (the pinned `om6502.lst` `asl_aba` sequence explicitly writes the old and then modified value), but the seven observed `$5C33` events each have only the single `$00` write and are not a paired RMW write sequence.

Therefore the instrument is valid for establishing that the CPU issued a full-byte zero write and that the tap did not alter it. It does not reveal post-handler state. No callback/state contradiction is established by these timestamp-associated events, and this audit assigns no cause to MAME, firmware, or the FPGA.

The additional pinned source snapshots are public MAME source at commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`, stored only in ignored `simulation/reference_sources/`:

| Source | SHA256 |
|---|---|
| `src/emu/emumem_het.cpp` | `3353901EE8F7ADD6CBE889A2A5951012E7D2C29607DDB47172399665AECC03D3` |
| `src/emu/emumem_aspace.cpp` | `2B7411F12EB6305070070F16FF781B5B80A14E52160A59EEFC09C018C4BDA03C` |
| `src/frontend/mame/luaengine_mem.cpp` | `10C1B361350ADB06521A51ED4E32BA5DFEEE579E6E8D2C4807EEE506837C3493` |
| `src/frontend/mame/luaengine.h` | `C2573793095786F019734DC6A4CED25AC03D92C011B40C49950B009F8EC96B48` |
| `src/devices/cpu/m6502/m6502.cpp` | `C1B50A9A19929B5BF170722B51FE165AAE30FCBF9A32FC9A3C2B484F36318CB6` |
| `src/devices/cpu/m6502/om6502.lst` | `90022EDB0ED1B756F615472F5141AAD47A04BD120C1AAD3A5A1493FB6509C3E8` |

## Post-write instruction-fetch proxy

A single isolated Venture 0.288 run added a narrow audio program-space read tap at `$5C30-$5C40`. The Lua callback sets a pending sequence ID only on a full-mask PB-data write of `$00` at `$1002`; the first matching program-space read then records that ID and samples the saved PIA items without reading PIA registers. The pending ID is carried through the following main CRA IRQ-status read and PA-data read. This avoids a tap over the full 64 KiB audio address space and does not force a bus value or write.

The selected device is `:soundbd:audiocpu`, instantiated as `m6502_device` in pinned `exidysound.cpp`; the machine config assigns it an `AS_PROGRAM` map and does not define an `AS_OPCODES` map. In pinned `m6502.cpp`, `memory_space_config()` exposes `AS_PROGRAM` alone when no opcode map is configured, and `init()` aliases the sync access view (`m_csprogram`) to the program view in that case. The default `read_sync()` uses `m_csprogram`. The NMOS `sta_aba` microcode writes the target and then calls `prefetch()`. In the capture, each tapped PB write at PC `$5C33` is followed by the first narrow-range program read at address and PC `$5C36`, byte `$E6`, 1.117–1.118 µs later. Together, the configured address-space alias, source microcode order, address/PC match, and observed next byte identify this as the next instruction-fetch proxy. The tap API itself reports program-space reads, not an explicit SYNC pin, so this remains source-correlated fetch evidence rather than a separate CPU-pin capture.

The run recorded ten qualifying `$00` writes in its 50.9–72.0 s capture window. Its filtered logger only starts recording main CRA/PA reads after a PB write and next-fetch sequence is pending. Therefore the absence of the earlier timestamp-paired PA read from this output is a logger selection effect; it cannot establish that the read did not occur before the write. The next-fetch save-item values are samples at that fetch, not evidence about callback order of omitted reads. Adding a read tap can also affect dispatch/performance and scheduling. No root cause or FPGA parity claim follows from this probe.

The reproducible Lua source is [mismatch_fetch_proxy.lua](../../../tools/pia_firmware_timing/mismatch_fetch_proxy.lua), SHA256 `4B1E4AD53BA004D7F4088E5F0B427639C88E21FFC12E3706CCF4C12BF5383A20`. Its ignored raw output is `simulation/pia_mismatch_instrument/fetch_proxy_run1/pia-fetch-proxy.csv`, SHA256 `274FC3C1181F348139786E727A7222E8E17F72F57B95E7A2B0F8A6446C2AD13A`; metadata and complete MAME log are beside it. The run used `C:\MiSTerDev\mame\mame.exe` 0.288, binary SHA256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`, and the existing Venture archive, SHA256 `AF340219D7FA4BF9D0A2A9FFABA7053189A6A2542D63B8CF2D3B74358DB72BCD`. The Lua `m.version` field was unavailable (`nil`); the MAME command-line version check reported `0.288 (mame0288)`. Source snapshots are pinned at commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`:

| Source | SHA256 |
|---|---|
| `src/mame/exidy/exidysound.cpp` | `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660` |
| `src/devices/cpu/m6502/m6502.cpp` | `C1B50A9A19929B5BF170722B51FE165AAE30FCBF9A32FC9A3C2B484F36318CB6` |
| `src/devices/cpu/m6502/m6502.h` | `580BDF7ECA726F4D0A7502DED7CD462153B935B7CD44C1A6490818E685657F90` |
| `src/devices/cpu/m6502/om6502.lst` | `90022EDB0ED1B756F615472F5141AAD47A04BD120C1AAD3A5A1493FB6509C3E8` |

The isolated working directory was `simulation/pia_mismatch_instrument/fetch_proxy_run1/`; from that directory the invocation was:

```powershell
& 'C:\MiSTerDev\mame\mame.exe' venture -noreadconfig -nowriteconfig -skip_gameinfo -rompath '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)' -cfg_directory cfg -nvram_directory nvram -input_directory input -state_directory state -diff_directory diff -comment_directory comment -homepath home -video none -sound none -nothrottle -nosleep -noplugins -autoboot_delay 0 -autoboot_script mismatch_fetch_proxy.lua -seconds_to_run 80
```

The Lua script applied the same frame-based coin/start schedule as state-run3 and exited at frame 4500. ROM bytes and captured CSV remain ignored and are not included in the source report.
