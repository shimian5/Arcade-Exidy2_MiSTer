# Mouse Trap startup and native speech — five-step batch

Date: 2026-10-12. Sol6.1 coordinates the existing Luna workers. Previous fitted production source remains `7c69900`, checkpoint `1cafb86`. Owner probe/project edits are preserved; no release acceptance is implied.

## Steps and acceptance scope

1. **Production startup contract:** inspect actual T80 register-bank reset, fitted power-up state and firmware first use; distinguish unknown HDL simulation from proven FPGA initial values.
2. **Cold/warm boot tests:** use actual production sources/private firmware and meaningful retained-bank/reset cases. Do not replace missing startup evidence with a zeroed generated-source assumption.
3. **Native gameplay speech:** drive genuine game inputs in native MAME, verify play actually begins, capture resolved RIOT callbacks, busy and full digit streams. Diagnostic injected commands must be labelled separately.
4. **Complete stream comparison:** compare full ordered port/D0 streams and command/reset boundaries; classify clock-phase, initial-state and causality differences. Do not infer complete phrase equality from a 32-bit prefix or claim sample-exact WAV equality for the causal renderer.
5. **Checkpoint:** independently inspect worker results, land only justified fixes with appropriate full Quartus verification if production RTL changes, update remaining work and provide reproducible hardware cases.

## Current results

The five bounded investigation/checkpoint steps are complete. This does not close the production boot or native phrase acceptance gates.

| Step | Result | Remaining acceptance |
| --- | --- | --- |
| 1. Startup contract | Actual T80 banks have no reset/initial value. Read-only mapped-netlist audit finds all 128 bank FFs marked power-up-don't-care. | Post-fit per-bit cold values and initial-digit policy remain unqualified. |
| 2. Cold/warm tests | Raw unknown-bank control and four concrete-bank cases pass their expected checks; each concrete case performs 642 ROM reads, 24 I/O writes and 20 digit writes. Warm PA4 reset retains all 128 bits. | Selected seeds are not exhaustive physical startup evidence; this CPU/helper fixture does not replace a complete production subsystem/game test. |
| 3. Native evidence | Fixed RIOT mirror recording and validated delayed inputs. MAME completes a 3,600-frame capture, reaches Hall of Fame and sees inputs/PIA traffic; only startup PA callbacks E0/EF/FF are observed. | Playable board/credit/start route and game-issued bark/meow/chomp commands remain unresolved. |
| 4. Stream comparison | All 3,093 available T80 digit writes match the final native ordered prefix and sampled clock levels; alias/timer, unequal-length and mismatch controls pass. | 925,387 native writes have no T80 partner; full phrase/PCM/WAV equality is not established. |
| 5. Checkpoint | Source fixtures, recorder fixes, evidence audits and hardware checklist are committed separately from production integration. | Owner hardware results remain pending. |

See [boot audit](mousetrap-production-boot-2026-10-12.md), [native evidence](mousetrap-native-phrases-2026-10-12.md), and [comparison audit](mousetrap-phrase-comparison-2026-10-12.md). Parent independently checked the native screenshots, all available D0 streams, comparator unit tests, corrected capture summary, all five boot modes and the mapped power-up query. Selected odd/even bank seeds differ in the first two digits; no persistent divergence is established.

No production RTL/QSF/SDC changed in this batch, so fitted production source and RBF remain `7c69900` with the previously passing full flow/STA. A new full build is required if the next evidence justifies a production change. No ROM, capture, screenshot, generated test output or RBF is tracked. [Hardware acceptance checklist](../../reference_cases/mousetrap-speech-hardware.md) covers owner HDMI and Direct Video/S-Video testing; those tests remain pending.

## Stopping rule

Stop after this batch. Native boot, phrase and hardware gates stay unchecked unless their actual evidence passes. Builds/captures/ROMs remain ignored; source fixtures and audits are tracked. Legacy clock coverage and remaining FAX/game/graphics/audio/CRT work retain their separate scope.

## Next increment

Investigate why the verified native coin/start sequence reaches Hall of Fame but not a playable board: inspect credit/start state and actual input/interrupt latch reads, or use the game's declared Free Play DIP as a separately labelled normal configuration. Obtain a real post-start PA command before extending RTL replay. Then decide the cold initial-digit policy from broader seed/native-reset evidence and perform the hardware matrix. FAX, remaining sets, graphics/audio and CRT work follow the remaining-work tracker.

Source evidence/tool commit: `a3045ef`. This changes fixtures, native recorder/summary and audits only. It can be reverted independently of the production speech integration; the separate checkpoint documents the stopping point.
