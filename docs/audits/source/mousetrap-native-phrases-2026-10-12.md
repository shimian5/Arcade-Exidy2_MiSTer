# Mouse Trap native gameplay voice evidence — 2026-10-12

## Result

The late-input 3,600-frame run got past the earlier startup wait: the main CPU was executing around `A1A9`, read the coin/start and game-control input ports, and produced sound-PIA traffic after coin and movement. Its frame-2400 image is still the “MOUSETRAP HALL OF FAME / JOIN THE … / BY ENTERING YOUR INITIALS” screen, so this run does not verify that play began. There was no post-start sound-CPU RIOT PA/DDRA write after frame 322 and no bark, meow, chomp, or other game-issued speech boundary. The actual phrase route remains unresolved.

The first bounded 900-frame attempt had stopped before this later input/read window. I moved the genuine inputs after frame 1460, where the earlier capture first showed main-CPU input and sound activity. This change closed the early-boot ambiguity but did not produce speech commands. No memory, CPU register, RIOT port, or speech command was forced.

Private capture products are under `simulation/mousetrap_voice_gameplay_lateBoot/`: `bus.csv`, `events.log`, `summary.txt`, `run-manifest.json` and the three screenshots. The Lua recorder and parameterized runner are [mousetrap_voice_gameplay.lua](../../../tools/mame/mousetrap_voice_gameplay.lua) and [mousetrap_voice_gameplay.ps1](../../../tools/mame/mousetrap_voice_gameplay.ps1). The parser and mirrored-register check are in [mousetrap_voice_summary.py](../../../tools/reference_cases/mousetrap_voice_summary.py).

## Reproducible late-input run

The local executable was `C:\MiSTerDev\mame\mame.exe`, MAME 0.288 (`mame0288`), SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`. It ran the staged `mtrap` set from `simulation/a2-local/roms`; the ZIP SHA-256 was `4F87B2C49FCEE00B2A4B7ACD4227EA50229C622F8ADBD4F840B8630EFB55EEE6`. MAME exited 0 after 3,600 frames. User configuration, plug-ins, video, sound, throttling and sleeping were disabled. `tools/mame/mousetrap_voice_gameplay.ps1 -Run lateBoot -Frames 3600 -InputProfile late` reproduces the schedule and capture. The pinned source basis is the local official-source snapshot `simulation/reference_sources/exidy.cpp`, `exidysound.cpp` and `mos6530.cpp`.

Inputs used complete MAME field masks for assertion and zero for release. Port values two frames after each transition verified the active-low levels:

| Frames | Input | Asserted port sample | Released port sample |
|---|---|---|---|
| 1800–1825 | Coin 1 | frame 1802: `IN0=7F` | frame 1827: `IN0=FF` |
| 1860–1890 | 1 Player Start | frame 1862: `IN0=FE` | frame 1892: `IN0=FF` |
| 2000–2120 | P1 Right | frame 2002: `IN0=FB` | frame 2122: `IN0=FF` |
| 2150–2180 | Dog Button | frame 2152: `IN0=EF` | frame 2182: `IN0=FF` |
| 2220–2250 | Yellow Button | frame 2222: `IN2=FE` | frame 2252: `IN2=FF` |
| 2300–2330 | Red Button | frame 2302: `IN2=FD` | frame 2332: `IN2=FF` |
| 2380–2410 | Blue Button | frame 2382: `IN2=F7` | frame 2412: `IN2=FF` |
| 2500–2530 | P1 Up | frame 2502: `IN0=DF` | frame 2532: `IN0=FF` |
| 2600–2720 | P1 Left | frame 2602: `IN0=F7` | frame 2722: `IN0=FF` |
| 2800–2830 | Dog Button | frame 2802: `IN0=EF` | frame 2832: `IN0=FF` |
| 2900–2930 | P1 Down | frame 2902: `IN0=BF` | frame 2932: `IN0=FF` |

Snapshots at frame 1600 (`precoin.png`), 1920 (`after_start.png`) and 2400 (`play.png`) show: “PLEASE STAND BY / VERSION 5” before coin; a black transition after start; then the Hall of Fame / initials screen. The main CPU PC samples were `A1A9` at frames 1600, 1800, 2100, 2400 and `A1A7` at 1920, 3000 and 3600. The capture recorded 18,439 `$5101` IN0 reads, 3,193 interrupt-latch reads and one `$5213` IN2 read. It establishes that the late input schedule reached active CPU input polling, but the screenshot does not show a playable board state.

## Voice and RIOT results

The CSV contains 4,102,842 bus events: 3,152,457 voice-Z80 reads, 928,482 voice-Z80 writes, 3,509 sound-CPU writes in the RIOT/timer window and 266 main sound-PIA writes. The summary filters the RIOT window by the actual mapped-register predicate before register decoding; only four sound-CPU writes are accepted as RIOT registers, all at frame 322:

| Time | PC | RIOT address/register | Data | Resolved PA callback | Effect |
|---:|---:|---|---:|---:|---|
| 5.371746792 s | `6C78` | `0801` / DDRA | `1F` | `E0` | voice reset held |
| 5.371753497 s | `6C7D` | `0803` / DDRB | `40` | — | PB direction setup |
| 5.371760202 s | `6C82` | `0800` / ORA | `EF` | `EF` | voice reset held |
| 5.371779199 s | `6C8F` | `0800` / ORA | `FF` | `FF` | voice reset released |

The voice Z80 made 928,482 I/O writes, including 928,480 with A4 low (digit-write candidates) and two with A5 low (busy candidates). Its 928,480 A7-low command/status reads all returned `FF`. These writes begin at frame 0, before the sound CPU releases the voice CPU at frame 322, and continue without a new RIOT PA/DDRA command. They are startup/idle traffic, not a decoded game phrase. Main sound-PIA writes occur at frames 1801 after coin, 2002 after movement, and 2003 after button activity; that activity does not establish a speech command in the absence of a new RIOT callback.

## RIOT recorder correction

The first-pass recorder filtered RIOT I/O with `(address & 0x1f) <= 3`. The pinned `mos6530.cpp` map mirrors register offsets 0–3 with mask `0x18`; over offsets 0–31 the valid register predicate is `(offset & 4) == 0`, followed by `offset & 3` for PA, DDRA, PB or DDRB. The recorder now keeps those aliases for both reads and writes. The summary runs a 32-offset oracle and checks that neither tap has regressed to the old filter. The corrected late-input capture still contains only the four frame-322 setup writes, with no later PA/DDRA callback.

The earlier [voice reference audit](mousetrap-voice-reference-2026-10-12.md) preserves the historical 3,600-frame first-pass capture and hash. Its screen did not establish gameplay. The 900-frame attempt is also retained privately but is superseded for boot-phase conclusions by this later 3,600-frame run. The current evidence shows the game advancing beyond the standby screen to Hall of Fame; it does not establish a playable game state or native phrase boundary.

## Remaining gate

To identify real bark, meow or chomp transitions, first reach and verify an actual game board, then observe a post-frame-322 PA/DDRA update and correlate it with the following digit/clock stream. The current run’s confirmed port activity and PIA writes are insufficient to name a speech phrase. Do not infer phrase identity from idle digit writes or from sound-PIA traffic alone.
