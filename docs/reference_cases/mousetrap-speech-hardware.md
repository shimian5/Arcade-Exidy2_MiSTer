# Mouse Trap speech hardware session checklist

Status: owner hardware session pending. This is a capture checklist, not a speech, video, or CRT acceptance claim. Record observations as heard and seen; keep recordings outside tracked source files. Do not change Releases or imply the candidate is approved for general use.

## Identify the exact build

Use the accepted full-core build from `2b9eb2b` at `simulation/full-core/fax-gfx-seed2-20261013/Arcade-Exidy2.rbf` (SHA-256 `f58fee7b7d2d70aae767d2e5bd0dec8e23ada4d649422ab9404cedf9d7c6a559`) and [Mouse Trap speech expansion candidate MRA](../../candidates/mra/Mouse%20Trap%20(speech%20expansion%20candidate).mra) (SHA-256 `B0669285F0BEEFC90E11903FA50D8167E713698E0873A169D8A5A85F7567B23C`). The MRA's `<rbf>Exidy2</rbf>` must resolve to this RBF. Use the candidate's speech profile and required Mouse Trap ROM set; record the MiSTer main version, ROM-set identity, controller mapping, DIP settings, and actual RBF/MRA checksums from the device. The candidate is for this test only; leave all release files unchanged.

The isolated hardware package uses an Exidy2_Test core reference; its manifest gives the repackaged MRA hashes. The build includes production FAX binding and the RGB generate-scope correction and passed its full Quartus flow. That evidence does not cover the complete game renderer or an analog CRT path. Direct Video to S-Video into the owner's 15 kHz JVC is an observation target; the new CRT transport remains unbound, so this checklist cannot claim Direct Video timing, color, or sync is correct. Record HDMI and Direct Video results independently, including adapter/cable, display model, MiSTer video settings, `direct_video` setting, scaler, and audio routing.

## Capture setup

- [ ] Record the build and device identity above before the first run. Note whether the test begins from a cold power-on, a warm reset, or a ROM reload, and whether this device has previously loaded the speech candidate.
- [ ] Capture HDMI first. Save one continuous audio/video recording per run when practical; note any manual audio gain and keep that gain fixed for comparisons.
- [ ] Repeat the same procedure through Direct Video → S-Video → 15 kHz JVC. Record the exact signal path and any display lock, cropping, geometry, or color behavior. Treat CRT observations as unqualified transport evidence.
- [ ] For every recording, retain the original file and record filename, SHA-256, sample rate/channel format if available, capture source, and gain/settings. Do not normalize or edit the only copy.

## Normal boot and known game-time window

Use ordinary Coin 1 and Start controls; do not select Free Play for the reference sequence. Native MAME identifies a long startup wait of about 512 VBlank intervals. The successful schedule held at frame granularity used Coin 1 at frame 2100 (about 35 seconds after run start) and 1 Player Start at frame 2160 (about 36 seconds). On hardware, use the visible credit/start prompts rather than trying to time button taps to exact emulator frames. Record actual button times and what the screen showed.

| Step | Procedure | Record |
| --- | --- | --- |
| Cold first load | From a cold power-on that has not loaded the speech candidate since power-up, load the exact candidate and Mouse Trap ROM set. Wait through startup, then coin and start when the game accepts them. | Whether the core/MRA/ROM loads, time to attract/credit screen and start prompt, time to GET READY/gameplay, base audio, voice audio, errors or stalls. |
| Repeat cold load | Power the MiSTer fully off and on, then load the same candidate again. Repeat for a second power cycle if practical. | Whether startup, credits, base audio, and speech behavior repeat; note differences and exact power-cycle history. |
| Recorded normal play | After start, move right for a short interval. At a safe playable moment, tap Dog once. Continue normal play long enough to observe the result. | Timestamp every control and visible event; describe what was heard literally (for example, “short voice-like burst”), not with an inferred bark/meow/chomp label. |

The native reference run reaches the maze using Coin at frame 2100, Start at 2160, then Right beginning at frame 2220. It records two reset/release groups while Right is held (38.327 s and 38.544 s), followed by another release about one frame after a Dog-button edge (39.525 s). These are genuine game-issued PA/voice-port events, but no reliable word/animal identity is attached to them. Compare hardware by control, timing, visual game state, and the literal audio recording; do not treat command bytes as phrase names.

The first two speech output bytes also reflect retained native B-register history. MAME observed `$46`, `$47` in the third group, while the paired cold-state replay produced `$45`, `$46`; the following B increment explains the pair. This is not evidence of a production CPU initialization bug and does not establish phrase meaning. Native filtered PCM comparison, cold-start hardware behavior, and audible gain/level acceptance remain open.

## Reset, reload, pause, and repeatability

- [ ] **Warm core reset:** Reset during idle, then separately during an audible voice event if safe. Coin/start again after startup. Record recovery, base audio, voice audio, and whether a partial/repeated voice or stuck tone occurs.
- [ ] **ROM reload:** Reload the same speech MRA and ROM set without powering off. Repeat the same controls. Record whether speech image readiness, base audio, and gameplay recover.
- [ ] **Pause/resume:** Pause during base audio, during an audible voice event, and after a voice event. Resume each time. Repeat pause/resume once and include one reset while paused. Record whether playback stops/continues as expected and whether game/audio state recovers.
- [ ] **Power-cycle variation:** Repeat cold load from at least two separate power cycles if possible. Include one test that loads the candidate immediately after power-on and one that follows a prior candidate session and full power cycle. Record exact history; do not collapse unlike startup sequences into one result.
- [ ] **Legacy comparison:** Load the released Mouse Trap MRA and, if available, a legacy Exidy title using the same RBF. Record baseline behavior. Return to the speech candidate and repeat one recorded voice event. Do not edit or replace release files.

## Per-run record

Copy this block once for HDMI and once for Direct Video, and again for each reset/reload/power-cycle variant:

```text
Date/time:
RBF path and SHA-256 (device-confirmed):
Source/build identity: 2b9eb2b / video-scope-20261012
MRA name and SHA-256 (device-confirmed):
MiSTer main version:
ROM set / controller mapping / DIP settings:
Startup history (cold power-on, prior speech MRA load, reset/reload):
Output path, adapter/cable, display model, video settings:
Audio route and fixed gain:
Recording filename, format, SHA-256:
Input timestamps and visible game events:
What was literally heard (no guessed phrase labels):
Base audio / voice audio / silence / clipping / stuck tone:
Pause, reset, reload and repeat behavior:
Video lock, sync, geometry, crop and color observations:
Uncertainty or failed steps:
```

Compare matched HDMI recordings first at fixed gain. Keep the Direct Video/JVC observations separate because the new CRT transport is not qualified. A bounded simulation, MAME command trace, successful fit, or source-raster fixture cannot replace these hardware listening and display observations.
