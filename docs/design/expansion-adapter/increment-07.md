# Increment 7 — actual ROM expansion payloads

Completed 2026-10-06. All three ROM-backed connected expectations pass in [results](increment-07.json). [Fixture provenance](increment-07-roms.json) records component CRC/SHA1, archive/member, offset, image hash and zero-filled banks.

Read-only NAS archives supply Mouse Trap's four CVSD parts in MAME region-offset order, plus the FAX/FAX2 question banks. Each component matches the pinned MAME availability manifest, and each assembled image matches the prior independent 95-ROM region audit. Mouse Trap is 16 KiB; both question stores are 192 KiB. FAX banks 22/23 are zero-filled; all 24 FAX2 banks are populated. Raw bytes are confined to ignored `simulation/expansion_adapter/rom-images/`; archives remain untouched and no ROM bytes are tracked.

The actual Mouse Trap speech image passes two source file-command/GPIO/ACK sessions with stopped-clock backpressure, exact transport/store checks and every remote read byte. Both actual question images pass every stored byte and 48 public read-port bank boundary checks. Base payload remains a one-byte synthetic fixture; these tests do not boot the game or execute its audio CPU/CVSD device. They establish expansion transport/read integrity, not game/audio support.

Next: combine adapter faults, loader readiness and transport quarantine into an explicit connected reset/read-enable contract; exercise malformed full-length speech and extended-to-legacy reloads. Remaining FAX extra PROM/banks24..31, full board/game/audio execution, physical CDC/shared reset and RAM fit remain open. No production wiring or Quartus build.

Replay preparation in native PowerShell: `python tools/expansion_adapter/prepare_roms.py --rom-dir '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'`.

Replay simulation: `wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/connected.py --rom-images simulation/expansion_adapter/rom-images`.
