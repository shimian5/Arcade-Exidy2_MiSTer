# Teeter Torture MRA integration candidate

This candidate is loader metadata for the planned Teeter binding. It is **not a working game release**: the production core still lacks its spinner/D-pad binding and 600 Hz periodic NMI. The standalone controls fixture is not top-level acceptance.

The pinned MAME Teeter configuration derives from Venture, with collision mask/invert `0x0c/0x0c`. Index 1 `D0` selects the Venture-class CPU/audio base plus interrupt profile 3; profile 3 currently changes collision causes only. Index 2 `37` follows the measured native raster reload. Validate ROM decoding, video and full CPU execution before accepting this profile.

## Byte layout

All 17 ROM members match the local MAME metadata by size/CRC/SHA1. The staged archive matches the previously verified read-only NAS archive. The assembled stream is 84288 bytes (`0x14940`), with no omitted MAME ROM parts or byte-placement mismatches in the existing loader auditor.

| Stream range | Intended contents |
|---|---|
| `0x00000..0x0ffff` | Eight program ROMs at CPU `0x8000..0xffff`, lower region padded zero |
| `0x10000..0x13fff` | Audio padding then five ROMs at physical `0x1800..0x3fff`, corresponding to MAME `0x5800..0x7fff` |
| `0x14000..0x147ff` | 2 KiB graphics |
| `0x14800..0x148ff` | `tt5c.129` decoder PROM |
| `0x14900..0x1491f` | `tt6d.123` VRAM-control PROM |
| `0x14920..0x1493f` | `tt14h.123` sprite-control PROM |

The PROM order follows hardware loader banks rather than MAME's contiguous PROM-region order. No tone ROM, speech extension or hiscore metadata is invented. The MRA SHA-256 is `C8AF881DC04CC50FD94643BCD4C291D8AB520FCF28460F757D6A3F2B91FCD9CC`.

## Controls and switches

Fire defaults to A; the four directional bits remain available for the planned D-pad steering binding. Additional face buttons are labelled unused so start and coin slots align with the current top-level indices. Pause has no ninth default button. Spinner and analog mode selection require production `hps_io`/OSD binding and hardware validation; labels alone do not provide them.

DSW defaults to `0xde`: bonus 20,000, one coin/one credit, three lives, coin-2 bit unpressed. The coinage switch uses noncontiguous bits 11,12,15, corresponding to DSW 3,4,7; the eight values follow the pinned MAME table in binary selector order. Verify MiSTer noncontiguous DIP interpretation on hardware.

## Replay

```powershell
py -3 tools/mra_audit/audit.py --rom-dir simulation/teeter-contract/roms --json simulation/teeter-contract/mra-candidate-audit.json 'candidates/mra/Teeter Torture (integration candidate).mra'
```

This proves archive/loader metadata only. Controls, periodic NMI, complete memory/video/sound behavior, top-level ROM consumption and hardware remain open. Keep this MRA under `candidates/` until those gates pass.
