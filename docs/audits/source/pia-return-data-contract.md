# PIA audio response bus timing and capture contract

## Finding

The fresh candidate STA report `simulation/timing-candidate/reports/setup.rpt` identifies the PIA audio-response bus as the current worst setup path. Its worst path starts at `PIA_8B.portb_ddr[3]`, crosses through `PIA_9B.data_out` and the main CPU read mux, and ends at `CPU_databus_in[3]`: slack −0.993 ns, data delay 3.082 ns, launch/latch relationship 3.150 ns, skew −0.731 ns (report lines 23, 40–45, 89–105). Other worst paths are bits of `portb_ddr` and `portb_data[0:1]` to the same bus register (lines 23–29). This is a constrained timing failure in the candidate STA view, not evidence of a PIA functional failure or proof that a one-bit synchronizer is sufficient.

The chain is:

1. Audio CPU writes PIA_8B port B. `modules/pia/pia6821.vhd:194-270` updates `portb_ddr`/`portb_data` on `PIA_8B.clk` rising edges when `cs` and `rw='0'`. The output process at `:415-425` drives `pb_o` from the data register where DDR bits are outputs and otherwise drives zero. In `rtl/audio_board.v:134-163`, `PIA_8B.pb_o` is `audio_DO_bus`.
2. That full 8-bit bus feeds PIA_9B's `pa_i` (`rtl/audio_board.v:102-132`). PIA_9B is clocked by `master_clock`; its read process is combinational (`modules/pia/pia6821.vhd:125-190`). For a port-A data read, it returns `porta_data` on configured output bits and `pa_i` on input bits (`:137-149`). The report's internal `PIA_9B.data_out` logic confirms this input path is selected for the failing bits.
3. `audio_data_out` is PIA_9B data output (`rtl/audio_board.v:103-112`) and top-level `audio_data_out` feeds a registered main CPU read mux (`rtl/Exidy2.v:169-178`). The PIA address window is `$5200-$520f` (`rtl/audio_board.v:105`); the broad data read term at `Exidy2.v:177` is additionally qualified by read direction.
4. `CPU_databus_in` is captured on every `posedge master_clock` (`rtl/Exidy2.v:169-178`). The main T65 has the same `master_clock` input but advances only when `PH_1` is high (`:182-199`); the CPU core itself only consumes state/input on a rising clock when `Enable='1'` (`modules/cpu-t65/T65.vhd:454-465`, with other state processes likewise gated at `:335-365`, `:534-545`, `:676-686`). Thus the bus register updates much more often than the CPU's roughly once-per-64-master-cycle microstep. That slack in the transaction can be useful for a local mailbox, but it does not change the current one-master-cycle STA requirement on the always-updating register.

The cross-board paths are source-level protocol crossings: PIA_8B runs on `audio_clk`, and PIA_9B/main read mux use `master_clock` (`rtl/audio_board.v:103-140`, `rtl/Exidy2.v:169-178`). Both are PLL-derived in the current top-level design; they should be constrained according to the actual PLL output relationship, not assumed asynchronous or excused wholesale. The candidate setup report explicitly times this path. Existing PIA false-path constraints in `Arcade-Exidy2.sdc:211-219` suppress selected PIA-to-PIA/T65 paths and do not establish a data handshake or coherence guarantee for this PIA8-to-main read chain.

## What holds the byte stable

The PIA source preserves the response as an 8-bit registered port output, not a transient combinational CPU value: the data and DDR registers change only on a selected PIA write (`modules/pia/pia6821.vhd:194-270`), while `pb_o` reflects those registers (`:415-425`). That is the right structural basis for bundled-data capture. But the RTL alone does not prove how long firmware leaves all eight bits unchanged around every main-side response read, nor that all eight bits switch atomically at the destination. PIA CA/CB lines are cross-connected between the two devices (`rtl/audio_board.v:119-161`), but they are not used by the PIA_9B read mux as a qualified “response byte valid” signal; the module routes CA1/CB1 and CA2/CB2 for PIA edge/IRQ behavior.

Pinned MAME source supports the peripheral-level handshake shape but is not a cycle-level proof of this RTL bus contract. `simulation/reference_sources/exidy.cpp:1613-1623` connects main PIA port A/B, CA2/CB2, and the sound board's callbacks. The sound-side source defines the PIA register mapping (`simulation/reference_sources/exidysound.cpp:562-590`). The Victory sound implementation stages a command by writing PIA port A and then asserting CA1 (`:799-810`), and its response read fetches the port-B output before lowering CB1 (`:776-785`). This is evidence that a held data byte plus a separate handshake edge is a normal modeled protocol, not proof that every current Exidy2 profile's response read holds the byte for a particular number of master clocks. No firmware disassembly or PIA bus capture was performed for this review.

## Recommended next action

First preserve the current interface and investigate timing closure with accurate clock modeling and placement. The measured deficit is under 1 ns on one shallow bundle-return chain; a correctly related PLL clock model and ordinary timing optimization could close it without adding read latency or changing firmware-visible PIA behavior. Confirm the actual generated-clock waveforms/phase relationship in the fitted design and re-run full-flow STA with the path timed. Do not add a false path for this response chain.

If it remains negative, the most defensible RTL remedy is a **whole-byte, master-domain response mailbox with an explicit request/acknowledge protocol**, not a single synchronized bit and not a blind bus sampler:

- Capture all eight `audio_DO_bus` bits together into a source-held response bundle; keep that bundle unchanged until acknowledgment. Use a synchronized single-bit request/acknowledge toggle (or equivalent level handshake), with synchronizer attributes/placement on the control chain and ordinary timing between its stages.
- After the request has crossed into the master domain, capture the held bundle into a master-clock register and select it for the PIA_9B `pa_i` return path. Ensure the CPU read request waits until the destination byte is valid; otherwise the new latency merely returns the previous response.
- On reset, clear both sides' pending/valid state and define which side owns a request in flight. Keep the existing PIA reset behavior and 8-bit register semantics; reset must not expose a partly-updated byte.
- Specify the latency explicitly: two destination sampling edges for the control synchronizer, plus the mailbox capture edge, before valid is asserted. This would be a change from current zero-extra-cycle combinational return. Validate against main/audio CPU bus ordering and each firmware handshake/profile before adoption.

An alternative two-flop-per-bit `audio_DO_bus` sampler alone is not accepted as a solution: it can resolve metastability probabilistically but can capture a torn byte if the audio side changes several output bits near the sampling edge, and it provides no valid/acknowledge ordering. It becomes reasonable only as the data stage of a bundled-data protocol that guarantees source stability from before request synchronization until after acknowledgment. If the firmware does not hold the bus for that interval, use a source-side snapshot on the response event, then transfer the snapshot as a bundle.

## Limits

This report is a source/STA audit only. It did not invoke Quartus, alter RTL/SDC, run MAME, inspect a firmware transaction trace, or measure fitted silicon. It does not establish whether routing changes alone will close the path or whether every game keeps the response bundle stable across the proposed handshake interval. A later implementation should demonstrate byte coherence, reset during an in-flight transfer, both read/write directions, normal response latency, and all relevant sound-board profiles before replacing the current wiring.

## Evidence hashes

SHA-256 of the inspected files:

| File | SHA-256 |
|---|---|
| `simulation/timing-candidate/reports/setup.rpt` | `A2159073A58BF1D5A27290D45814ABE4982C89ED69A302F6E0EB0B571A6727B9` |
| `rtl/audio_board.v` | `8D2BD150AFF03F7CBE806F4A53025393986C6FED41EEBDD770F28B5D1661D946` |
| `rtl/Exidy2.v` | `4F39C4C29863E3C0FA0C61C574711C72B42A67A251FAEE85A3E785C35685FC2E` |
| `modules/pia/pia6821.vhd` | `0EB5087CFD3156368B2C277378E308D78E830AF8BD684262EECF7CD058C8FC12` |
| `modules/cpu-t65/T65.vhd` | `00A6F987028B5F963B457B57F6A3859203953DDC7C472086CB90992E643BB0FE` |
| `simulation/reference_sources/exidysound.cpp` | `57C0EDC71E9FAF0A37E48EEF406586E95A95902EF0F9E53275A7AD3326FAD660` |
| `simulation/reference_sources/exidy.cpp` | `0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486` |
| `Arcade-Exidy2.sdc` | `F44F6A651CBD698F93CAC7ADA44BFFF7424172CDBA59626CC544F8A348ECB763` |
