# Mouse Trap F9 prefix B-seed control

## Result

A short simulation-only test using the actual T80, Mouse Trap speech ROM payload, `speechRomBus`, and production `mousetrapVoiceIo` isolates the first three F9-prefix outputs. With only B changed from `$45` to `$46`, the first two writes change from `$45,$46` to `$46,$47`; both runs then converge at `$55`. The D0 sequence correspondingly changes from `1,0,1` to `0,1,1`. This confirms the causal B-seed effect on the first pair and the convergence of this short prefix. It does not establish phrase identity, full phrase parity, or the native CPU's complete warm state.

## Method and results

Run `simulation/mousetrap_native_replay/f9-prefix-20261013-015609-610/` performs two ordinary T80 reset/release executions against the same staged speech ROM payload and PA sequence. Each simulation initializes the register-file slot for BC with C=`$BF` and B=`$45` or `$46`; all other register-file slots are simulation-seeded to zero. It then asserts speech reset with PA=`$EF`, releases with PA=`$F9`, and records the first three low-byte `$EF` I/O writes from the executing T80. Each run performs 136 ROM reads and finishes after the third output, under one millisecond of modeled time after the fixture starts.

| Seeded BC | I/O addresses | Output data | D0 bits | CSV SHA-256 |
| --- | --- | --- | --- | --- |
| `$45BF` | `$45EF,$46EF,$55EF` | `$45,$46,$55` | `1,0,1` | `1A88A8207F7BD59C06E676E8EF9D3DB76DB0C67130523BD392A76C5548BE29C4` |
| `$46BF` | `$46EF,$47EF,$55EF` | `$46,$47,$55` | `0,1,1` | `6C77DBD2753D740AC204BC629DD99A4A29095982BB7BC82A0986EB45A0BEF27D` |

The seed=`$46` first two outputs match the native observations. At the native F9 release MAME reports PC=`$001A`, AF=`$0012`, BC=`$46BF`, DE=`$0000`, HL=`$36D3`, SP=`$3A18`, IX=`$00C4`, and IY=`$0000`. At the first output callbacks, BC is `$46BF` and `$47BF`; the native third output is `$55` at PC `$005F`. The F9 prefix fixture intentionally seeds only BC and lets the T80 execute from its own reset entry, so it does not restore the native PC, AF, HL, SP, IX, or other warm state. Those register values are documented as native observations, not assumed equal to the simulation state.

## Scope and reproduction

Run `sim/mousetrap_native_replay/run_f9_prefix.ps1` with PowerShell 7. The runner verifies the staged ROM payload hash, creates temporary T80 register-source variants under ignored simulation output, compiles the actual CPU plus the production speech ROM and voice-I/O modules, and checks all three addresses and output values for both seeds. No production RTL, release artifact, ROM image, or native capture is changed. Source fixture hashes are recorded per seed under `run-manifest.json`.

The result closes only the immediate `B=$45 → $46` causal question: the first two bytes and their D0 bits follow B, while the third byte converges. It does not claim that a B-only seed represents the complete native warm CPU state, or that these bytes identify any heard phrase. Native filtered PCM, actual cold-start hardware behavior, and audio gain/listening remain separate acceptance gates.
