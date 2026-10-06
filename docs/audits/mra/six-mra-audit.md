# Existing six MRA byte-layout audit

Date: 2026-10-06. Scope: checked-in Targ, Spectar, Venture Revision 5, Mouse Trap, Pepper II and Hard Hat MRAs against the existing MAME 0.288 metadata manifest and the owner-supplied MAME 0.257 split ZIP library. This is a byte and loader-layout audit; it does not establish boot or gameplay behavior.

The reusable auditor is [audit.py](../../../tools/mra_audit/audit.py). It assembles each index-0 MRA stream in memory from literal/repeat parts and CRC-resolved ZIP members, checks each target-set ROM member's size/CRC/SHA1 against the manifest, then models `selector` in `rtl/rom_loader.sv` and the actual RAM address truncation in the EPROM modules. The complete per-part placement, archive check, byte hash, physical range and SHA1 data is in [six-mra-audit.json](six-mra-audit.json).

## Results

All 78 MAME manifest ROM entries across the six selected sets matched the actual NAS archive bytes by size, CRC and SHA1. All MRA ZIP parts resolved by CRC; every MRA part that corresponds to a MAME part was verified byte-for-byte at its loader destination. There are no physical placement or archive-byte mismatches.

| MRA set | Index-0 stream | Notable region placement |
|---|---:|---|
| `targ` | `0x14960` (84,320 bytes) | main CPU image at direct MAME offsets, including the repeated `0x3800` program chip at `0xf800`; two copies of the 1 KiB graphics dump fill `eprom_1` `0x000–0x7ff`. |
| `spectar` | `0x14940` (84,288 bytes) | main CPU direct offsets with the final program dump repeated at `0xf800`; 2 KiB graphics at `eprom_1:0x000`. |
| `venture` | `0x14960` (84,320 bytes) | audio ROM MAME offsets `0x5800–0x7fff` land at `eprom_6:0x1800–0x3fff`, consistent with the loader's `[13:0]` modulo-`0x4000` address. |
| `mtrap` | `0x14940` (84,288 bytes) | three sound-program ROMs at MAME `0x6800–0x7fff` land at `eprom_6:0x2800–0x3fff`. |
| `pepper2` | `0x14940` (84,288 bytes) | three sound-program ROMs at MAME `0x6800–0x7fff` land at `eprom_6:0x2800–0x3fff`. |
| `hardhat` | `0x14940` (84,288 bytes) | three sound-program ROMs at MAME `0x6800–0x7fff` land at `eprom_6:0x2800–0x3fff`. |

The JSON records SHA1 hashes for the effective bytes in every populated physical bank and each contiguous written offset range. These include the zero-filled MRA padding and duplicated chips, so the hashes describe the actual loaded memory images rather than only individual archive members. `eprom_2` is modeled as a 4-bit data path; its raw and effective hashes are both retained. The selected PROM bytes already have zero upper nibbles, so masking them causes no change for these six MRAs.

Three Hard Hat MRA PROMs are additional shared parts rather than entries in MAME's `hardhat` set: CRCs `43b35bb7`, `e26f9053`, `f76b4fcf`. Their actual bytes match the corresponding shared PROM parts in the other audited sets. They are classified as archive-valid MRA extras. Whether this shared PROM profile gives the correct Hard Hat board behavior remains a separate gameplay/decoding check.

The MRA still includes Venture's replacement graphics ROM `vel_11d-2.11d` (CRC `ea6fd981`), and the bytes match the current MAME Venture manifest. This resolves the historical missing-`11d-cpu` report at the metadata/loading level; image correctness and behavior remain outside this audit.

Mouse Trap's MRA omits all four MAME `soundbd:cvsdcpu` ROMs (`mta_2a.2a`, `mta_3a.3a`, `mta_4a.4a`, `mta_1a.1a`), totaling 16 KiB. Its index-0 stream currently ends at `0x14940`. The loader reserves the next `0x20` bytes for `eprom_5`; an aligned append would pad to `0x14960`, then place the CVSD bytes through `0x18960`. Since `eprom_7` uses `ADDR_DL[13:0]`, the 16 KiB block begins at physical offset `0x0960`, continues through `0x3fff`, then wraps to `0x0000` and ends at `0x095f`, filling the bank once. However, `eprom_7` has no instantiated storage/consumer in `rtl/Exidy2.v`. Complete CVSD support therefore needs an explicit loader-to-audio storage path and CPU wiring; the current MRA omission is real and cannot be fixed by an MRA-only append.

## Reproduction

Run from the repository root in PowerShell. The NAS path is opened read-only; the auditor does not extract or copy ZIP members.

```powershell
python -m unittest discover -s tools/mra_audit -v
$mras = @('releases/TARG.mra','releases/Spectar.mra','releases/Venture Revision 5.mra','releases/Mouse Trap.mra','releases/Pepper II.mra','releases/Hard Hat.mra')
python tools/mra_audit/audit.py --rom-dir '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)' --json docs/audits/mra/six-mra-audit.json $mras
```

The four synthetic tests cover selector boundaries/address truncation, MRA repeat parsing and archive aliases, effective four-bit writes versus wrong bytes, and manifest hash mismatch detection. They passed. The real audit also exited successfully with 78/78 archive entries matched and no physical placement mismatches.
