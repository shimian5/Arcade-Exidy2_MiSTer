# Mouse Trap development speech hardware acceptance

Status: owner testing pending. This checklist records observations; it does not certify speech, gameplay or CRT timing. Keep recordings and results outside tracked source files under ignored `simulation/` or on your own storage.

## Identify the build

Use the development RBF and speech expansion candidate MRA identified in [STOPPING_POINT](../../STOPPING_POINT.md). The candidate MRA is [Mouse Trap (speech expansion candidate)](<../../candidates/mra/Mouse Trap (speech expansion candidate).mra>); its `<rbf>Exidy2</rbf>` must resolve to that development RBF on the MiSTer. Record the actual RBF SHA256, MRA checksum, MiSTer main version, ROM set, controller mapping and DIP settings. Preserve the existing release/core selection for comparison and recovery. The candidate needs the existing parent archives plus the four speech ROMs in `mtrap.zip`; do not rename a legacy MRA to imply speech support.

## Test sequence

Run each case first on HDMI, then Direct Video over S-Video to the 15 kHz JVC BVM. Record the adapter, display model, `direct_video`/video settings and any scaler/audio configuration; these are observations, not a new approved native CRT mode.

| Case | Procedure | Record / acceptance condition |
| --- | --- | --- |
| Cold start | Power off and reload the development core/candidate. Wait through startup, coin and start using ordinary controls. | Successful startup/gameplay, base audio present, no sustained idle buzz or clipped output. Speech boot is under investigation; record exact behavior even if silent. |
| Speech events | Play through dog transformation, interactions with cats, cheese collection and loss of life. | Record timestamp, controls and game event with every voice heard; compare with the matched native MAME run. Do not assign a phrase name solely from a numeric command. |
| Pause / resume | Pause during base audio and during an audible speech event, then resume. | Pause mutes; resume does not hang the game, repeat commands spuriously or leave a stuck tone. |
| Core reset | Reset during idle and during speech; coin/start again. | Startup and base audio recover; note voice/phase differences. Core reset clears the speech subsystem; PA4 CPU reset has a different retention policy. |
| Reload speech | Reload the same candidate, then repeat startup/gameplay. | No stale voice image, stuck download or lost base audio. |
| Legacy reload | Load the normal Mouse Trap MRA, then another legacy Exidy title; finally return to the candidate. | Speech disabled for legacy selection; expected legacy game/base audio works; candidate can enable speech again. |
| Gain / duration | Capture the same event from MAME and MiSTer, at a fixed recording gain. | Check onset, approximate duration, missing voices and audible clipping. The causal FPGA renderer does not promise sample-exact MAME WAV output. |
| Display | Observe sync, geometry and stability in both output paths. | Record faults separately from speech. Original 280p60/CRT remediation remains open. |

## Result record

For each run record: build/MRA identity, output path, startup/reset/reload history, input sequence, event time, expected MAME event, actual result, and recording filename. A passing bounded simulation or fitted timing report cannot replace these hardware results. Until this matrix and native phrase evidence pass, keep the release MRAs/RBF unchanged.
