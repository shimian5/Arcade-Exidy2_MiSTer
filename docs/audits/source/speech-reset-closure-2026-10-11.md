# Mouse Trap speech reset closure (bounded)

## Endpoint contract and evidence

The expansion bridge's speech read interface is native to `cvsd_clk`: `cvsd_read`, `cvsd_addr`, `cvsd_valid`, and `cvsd_data` are consumed/produced in that domain. The documented caller is therefore the speech CPU and `speechRomBus` on `cvsd_clk`. Driving the T80 on the bridge's 10 ns main clock and connecting its one-cycle `rom_read` pulse directly to this interface is invalid domain usage; a missed pulse under that setup is not evidence of a bridge defect. No change to `exidy_expansion_bridge_rr` or its interface is needed for this bounded case.

`sim/mousetrap_speech/tb_t80_speech_reset_race.sv` remains the negative control: it resets only the actual T80 and speech adapter while an old `$0004` response can survive, and reproduces the stale-response release of the new `$0000` read. The standalone `tb_t80_speech_reset_drained.sv` additionally proves the reset/drain ordering with actual T80 and adapter plus a deliberately delayed endpoint.

The stronger `sim/mousetrap_speech/tb_t80_speech_bridge_reset.sv` joins actual T80 and `speechRomBus` on `cvsd_clk` to the unchanged `exidy_expansion_bridge_rr`, actual transport/quarantine path, session loader, and CVSD RAM. It sends a synthetic image through the real candidate download path. On an accepted read, the fixture stops CVSD, asserts CPU reset, starts a new session, observes the generation toggle while the old generation ack cannot release reset, resumes CVSD, waits for matching-generation drain ack, reloads the image, and checks the first post-reset `$0000` fetch returns `$C3`. It also aborts an unsampled speech-domain request with the clock stopped before its accepting edge and checks no remote request entered the outstanding pipe before session restart. Main and speech clocks use 10 ns and 74 ns periods with distinct phase. A generated loader copy in the ignored simulation run directory connects the bridge's synchronized CVSD reset to the existing RAM reset input; tracked loader/bridge production candidates are unchanged.

The fixture includes `tb_bridge_reset.sv` adversaries. Reproduce with:

```powershell
& .\sim\mousetrap_speech\run_t80_speech_reset_race.ps1
& .\sim\mousetrap_speech\run_t80_speech_reset_drained.ps1
& .\sim\mousetrap_speech\run_t80_speech_bridge_reset.ps1
```

On 2026-10-11, ModelSim passed the full T80/adapter/bridge checks: `PASS accepted in-flight reset and post-reset data c3`, `PASS unsampled request aborted across stopped-domain reset; post-reset data c3`, and `PASS bridge reset adversaries`. The connected Verilator increment-14 suite also completed all 29 cases with `expectationMet: true`, including its expected-failure negative case. Generated `increment-14.json` report metadata was restored after the run; simulation outputs remain ignored.

## Acceptance boundary

This proves reset/drain sequencing only for the existing native CVSD-domain caller and the tested synchronous endpoint. It does not establish a generic asynchronous bus API or justify synchronizing response data as independent bits. If a future T80 caller runs in `clk`/main domain, add a separate explicit CDC shim that holds address stable through a request/response acknowledgment; do not silently change the existing bridge contract. Any production binding must synchronize CPU reset assertion/release into the speech domain and keep the CPU reset held across session quarantine, accepted-read drain, matching generation acknowledgment, and image readiness. The tested async reset assertion and synchronized release are represented by the reset conditioner, but the active production core still has no bound CVSD CPU/ROM path. ROM loading, CVSD/core integration, Quartus/hardware validation, and production timing analysis remain open.

Root independently replayed the corrected native-domain runner: accepted in-flight reset, unsampled-request abort, old-generation hold, first post-reset data and bridge-reset adversaries all pass. Evidence: the fresh `modelsim-bridge-reset-*` directory emitted by `run_t80_speech_bridge_reset.ps1` on 2026-10-11. The enclosing bridge source remains unchanged.
