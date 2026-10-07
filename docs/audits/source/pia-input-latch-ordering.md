# Venture PIA input and CA1 ordering in pinned MAME

## Result

The pinned MAME 0.288 `pia6821_device` does not have a CA1-controlled Port A input latch. In `control_a_w`, CRA bit 5 is the CA2 direction selector (`c2_output`), not a Port A latch enable. `get_in_a_value()` reads the current external-input value and merges it with output bits according to DDRA; `porta_w()` updates that input value directly. `ca1_w()` only tracks CA1 state and sets the IRQ flag on the configured edge. There is no operation that snapshots PA data when CA1 changes.

This rules out the proposed explanation that CRA=`0x2C` snapshots the previous `0x40` before a following PB write of `0x00`. In fact, bit 5 of `0x2C` selects **CA2 output**; bit 4 is zero, selecting CA2 strobe mode; bit 3 is one, setting its output high. Bit 2 selects the PA data register, bit 1 selects falling-edge CA1 flagging, and bit 0 disables IRQ output. The IRQ flag can still appear in CRA reads when bit 0 is clear.

## Exact callback order

The soundboard routes its PB callback to the main PIA's `porta_w`, and its CB2 callback to the main PIA's `ca1_w` ([pinned Exidy configuration](../../../simulation/reference_sources/exidy.cpp#L1619)). The sound PIA PB output handler forwards its byte through `m_pb_callback` ([pinned sound header](../../../simulation/reference_sources/exidysound.h#L137)). In the pinned 6821 source, `port_b_w()` stores the output latch and calls `send_to_out_b_func()` before it performs any CB2 write strobe. `send_to_out_b_func()` computes `m_out_b & m_ddr_b` and invokes the write handler. With DDRB=`0xFF`, a PB write of `0x00` therefore sends `0x00` through the callback chain to main PA input before the CB2 strobe can cause the main CA1 edge.

So, for the captured CRB=`0x2C`/DDRB=`0xFF` state, the PIA's own operation order predicts main PA input becomes `0x00` before the edge that sets the main CA1 flag. A later main PA read should then return `0x00` with DDRA=`0x00`. The frozen trace instead shows `0x40` in all seven cases. The 6821 latch theory is not supported; the remaining difference is between this callback-level expectation and the bus trace.

## Relationship to the seven frozen events

Every mismatch has the same qualified accesses: the sound CPU reads PB=`0x40`, writes PB=`0x00` with CRB=`0x2C` and DDRB=`0xFF`, and later the main CPU sees CRA status=`0xAC` before reading PA=`0x40` with CRA=`0x2C` and DDRA=`0x00`. The main PA read occurs 337–361 µs after the sound PB write. The earlier review lists exact frame/time pairs in [pia-response-mismatch-review.md](pia-response-mismatch-review.md).

This order rules out DDR masking and a CA1-captured old input as explanations. It does not by itself reveal which runtime fact differs from the expected chain: whether the PB output callback was actually delivered as `0x00`, whether the main PIA's `porta_w` was called, or whether the trace's access time represents the same side-effect boundary as the PIA callback. Those callback/input-latch values are not exposed by the existing CSV.

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

For each of the seven mismatches, the tapped audio write was address `$1002`, data `00`, mask `FF`, with live CRB=`2C`, DDRB=`FF`, output latch=`40`, and main PA input=`40`. At the following main CRA status read and PA data read, main PA input and audio PB output latch were still `40`; the PA bus byte was `40`. There were no intervening PIA control/DDR writes or additional audio PB data writes between that tap event and the main PA read. The same isolated run showed three other PB=`00` writes where the later main CRA/PA taps saw both audio output and main input at `00`, with bus read `00`. This demonstrates that the save-item observation can distinguish the two outcomes.

The bus write tap records a CPU write transaction; it does not prove the mapped PIA write handler or output callback completed. For the seven cases, the mismatch is therefore narrowed to the interval after the CPU write tap and before the following main reads. The exact MAME device source says the PIA handler would update `m_out_b` and dispatch the callback before CB2 strobing, but the observed live saved state remains `40`. The available Lua tap API does not expose a post-handler callback or the internal callback invocation itself, so this run does not explain that contradiction. It makes no claim about FPGA parity.

The focused output and all captured artifacts remain under ignored `simulation/pia_mismatch_instrument/state-run3/`; the raw event log is not part of this source report. The reproducible state probe is [probe_pia_items.lua](../../../tools/pia_firmware_timing/probe_pia_items.lua), SHA256 `029A852F95657A817F851E381B2687FB0CE4C9616E75AC70931402A7183E7BDB`; the boundary logger is [mismatch_state_trace.lua](../../../tools/pia_firmware_timing/mismatch_state_trace.lua), SHA256 `69D9243B55EBFB7D1B877929C959C7708F958A9C524994C78986CD4434FE8864`. It ran MAME 0.288 (binary SHA256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`) from an isolated working directory with `-noreadconfig -nowriteconfig -skip_gameinfo -video none -sound none -nothrottle -nosleep -noplugins -autoboot_delay 0 -seconds_to_run 80`; the Lua script exits at frame 4500 and applies the same coin/start inputs as the frozen capture. It reproduced the frozen mismatch timestamps exactly. The Venture PIA map is `$1000-$1003` mirrored through `$17ff`, and every mismatch tap address is the base `$1002` with full-byte mask `FF`; the full raw trace records only the initial audio CRB/DDRB configuration writes, so there are no intervening direction/control callbacks in these windows.

The Lua API exposes no `side_effects_disabled` flag; it reported no debugger object in this run, which executed the CPU normally. Accordingly, normal CPU PIA status/data reads kept their original side effects, and the script added none. The next investigation needs a hook at the mapped write-handler/output callback boundary (or an equivalent C++/RTL fixture) to determine why those seven tapped writes leave the PIA save items unchanged at the subsequent reads.

## Write-tap validity audit

The write tap is a pre-handler observation, but it is not a replacement handler. In the pinned `handler_entry_write_tap::write()` and `write_interruptible()` implementations, MAME calls the tap and then synchronously forwards the same `offset`, `data`, and `mem_mask` to `m_next`. The Lua binding wraps that callback and only substitutes the data if the Lua callback returns an integer; these capture callbacks return nothing (`nil`), so they leave the transaction unchanged. `install_write_handler_helper()` creates the mapped write delegate before the tap is installed; `install_write_tap()` wraps the existing write path as a passthrough. This establishes that the tap sees a write request before the mapped handler and that the handler call follows in the same call stack. The tap alone does not observe the handler's post-state or prove that a device callback changed its state.

For all seven disputed events, both independent CSV captures record audio CPU PC `$5C33` writing `$00` to `$1002` with `mem_mask=$FF`; the post-boundary logger samples the old `m_out_b=$40` at that pre-handler tap and still sees `m_out_b=$40` and main `m_in_a=$40` at the later main PA read. The original trace's status/data reads are ordinary CPU accesses; the MAME Lua API used here exposes no `side_effects_disabled` or debugger execution-state control. Its metadata reports no debugger object, and the accesses are from the running audio/main CPU PCs. This supports normal CPU execution but does not expose a C++ `side_effects_disabled` flag.

The Exidy map binds `$1000-$1003` directly to the sound PIA's `read`/`write` delegate, with mirror mask `$07FC`. `$1002` is in the base range, and the raw bus trace reports that base address, so this is not an alternate mirrored register. Its full-byte mask is `FF`. There is no second audio write to the PIA in the first disputed event's following 0.8 µs, and the full interval to the main PA read contains no audio PB/DDR/CRB or main PA DDR/CRA write. NMOS 6502 read-modify-write operations do issue two writes to the effective address (the pinned `om6502.lst` `asl_aba` sequence explicitly writes the old and then modified value), but the seven observed `$5C33` events each have only the single `$00` write and are not a paired RMW write sequence.

Therefore the instrument is valid for establishing that the CPU issued a full-byte zero write and that the tap did not alter it. The remaining evidence gap is specifically post-handler: the Lua save items are sampled at the pre-handler tap and at later bus edges, not at the PIA output callback boundary. The callback/state contradiction remains unresolved; this audit does not assign a cause to MAME, firmware, or the FPGA.

The additional pinned source snapshots are public MAME source at commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`, stored only in ignored `simulation/reference_sources/`:

| Source | SHA256 |
|---|---|
| `src/emu/emumem_het.cpp` | `3353901EE8F7ADD6CBE889A2A5951012E7D2C29607DDB47172399665AECC03D3` |
| `src/emu/emumem_aspace.cpp` | `2B7411F12EB6305070070F16FF781B5B80A14E52160A59EEFC09C018C4BDA03C` |
| `src/frontend/mame/luaengine_mem.cpp` | `10C1B361350ADB06521A51ED4E32BA5DFEEE579E6E8D2C4807EEE506837C3493` |
| `src/frontend/mame/luaengine.h` | `C2573793095786F019734DC6A4CED25AC03D92C011B40C49950B009F8EC96B48` |
| `src/devices/cpu/m6502/m6502.cpp` | `C1B50A9A19929B5BF170722B51FE165AAE30FCBF9A32FC9A3C2B484F36318CB6` |
| `src/devices/cpu/m6502/om6502.lst` | `90022EDB0ED1B756F615472F5141AAD47A04BD120C1AAD3A5A1493FB6509C3E8` |
