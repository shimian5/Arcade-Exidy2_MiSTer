# Raw-address reference and sprite bit ordering

Fresh Venture right/fire and matched right-only captures completed with successful MAME ROM verification and execution. The [raw reference report](raw-reference.json) retains executable, ROM archive, Lua and pinned MAME source provenance. Captures contain 189,581 and 190,028 bus events. Both show zero mirrored sprite-position writes: the game uses the exact four base addresses in this tested sequence. This finding cannot establish mirror usage for other sets or input paths.

The right/fire bus file is byte-identical to the accepted fourth-block `active03` reference. All 13 common screenshots match decoded RGB pixels; the fresh capture adds frame 2460. The raw tap preserves addresses before normalization and reads no side-effecting interrupt registers itself. Scripts and captures remain separate from the earlier accepted references.

Frame-end control/coordinate states are retained for frames 2400–2519. Object-2 X first differs from right-only at frame 2436. Active MAME image pairs are `(16,48)`, `(16,63)`, `(17,63)` and `(31,48)`. Decoding the corrected 2 KiB `vel_11d-2.11d` ROM (CRC ea6fd981) shows these image selections are dot/blank graphics in this outside-room sequence. Arrow graphics exist at other image indices. The capture does **not** reproduce or identify the reported inside-room horizontal arrow; projectile identity remains open. Frame-end state also does not prove pixel-time selection.

An exact source extraction of `oLS166` passes 16,384 independent bitmap-bit checks: all 64 images × 16 rows × 16 pixels, including both eight-bit halves, MSB-first ordering and serial cascade. A wrong first expected bit fails as intended. [Serializer results](serializer-results.json) retain hashes and exits. The fixture uses explicit load/shift scheduling and actual verified graphics bytes; it does not instantiate the control PROM, RAM latency, windows or complete production gated clocks. Serialization timing, clipping and full rendered-frame parity are unfinished.

The existing primitive loads asynchronously on the PE falling edge, while the [TI SN74LS166A description](https://www.ti.com/product/SN74LS166A) specifies synchronous parallel loading. Actual Exidy RTL also blocks its gated shift clock while PE is low. Replacing only the primitive with a synchronous model would prevent loading under unchanged wiring. This is a scheduling investigation, not an accepted board correction. The fixture additionally characterizes edge-only source loading when data changes while PE stays low; compare actual PROM/ROM timing or schematics before proposing a remedy.

```powershell
& tools/sprite_serialization/run_raw.ps1 -Run fresh_fire -Mode right-fire
& tools/sprite_serialization/run_raw.ps1 -Run fresh_right -Mode right-only
python tools/sprite_serialization/analyze.py
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/sprite_serialization/run_sim.py
```

`analyze.py` uses the retained sixth_fire01/sixth_right01 pair and the supplied read-only NAS archive. Choose fresh capture names to avoid overwrites. ROM-derived hex, atlas and screenshots remain in ignored `simulation/sprite_serialization/`; tracked reports contain hashes, register state and metrics only.

Stopping point: raw-address evidence and primitive bit ordering are reviewed; complete source serialization chain, inside-room shot reproduction and per-game collision/clipping acceptance remain unfinished. Use a scripted room-entry/right-fire sequence in the next authorized work; ask the owner for the exact symptom sequence only if primary reference runs cannot reproduce it.
