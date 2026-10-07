# FAX / FAX 2 question-bank and PROM contract

This audit compares the pinned MAME FAX map with the isolated expansion-loader candidate and independently reassembles the question banks from the private MAME archives. It writes only metadata under ignored `simulation/`; it commits no ROM bytes, generated image, capture, or test output. This is not production wiring or full FAX game acceptance.

## Pinned MAME source behavior

The source is `simulation/reference_sources/exidy.cpp`, pinned to MAME 0.288 commit `27a8d9e85b58058965907d1d8a7a92f8ed039348` (SHA-256 `0f58186ad90f0592454c505ff10fbca948eba14e7815704b2d24b13f69327486`). `fax_state::fax_map` writes the bank selector at `$2000` and reads the selected ROM through `$2000-$3fff`. `fax_bank_select_w` uses `data & 0x1f`; it logs a warning when that value is greater than `0x17`, but does not clamp or reject it. `machine_start` configures 32 entries of `0x2000` bytes each from `maincpu + 0x10000`. The FAX and FAX 2 maincpu region is `0x40000` bytes.

Therefore banks 0-23 map the valid question-ROM interval `[0x10000, 0x40000)`. Bank 23 spans `0x3e000-0x3ffff`. Bank 24 begins exactly at `0x40000`, one byte past the maincpu region; banks 25-31 point farther beyond it. Although the source configures those eight entries and lets the 5-bit selector choose them, the archive contains no valid expected bytes for those reads. Treating their runtime contents as `0x00` would be an unverified assumption. The separate candidate loader deliberately stores only 24 banks, suppresses backing reads for bank numbers 24-31, and returns a valid zero byte once the profile/window is ready. That is deterministic quarantine behavior, not established MAME parity. Before claiming full game equivalence, capture whether either game's code selects banks 24-31 and define the desired out-of-range behavior.

The FAX ROM declarations populate 22 of the 24 in-region question banks. The archive reconstruction confirms FAX banks 22 and 23 contain no loaded ROM members; the independent expansion image leaves these holes zero-filled. FAX 2 populates all 24 in-region banks. The existing adapter capacity and question-stream length are 24 × 8 KiB = 192 KiB. Its public-port tests already exercise the first and last byte of each of these 24 banks; they do not exercise MAME's bank-select register or assign a valid result to banks 24-31.

## `fxl-12b` PROM

MAME declares `fxl-12b` at offset `0x0140`, size `0x0100`, in a `0x0240`-byte `proms` region for both sets. Both declarations have CRC32 `6b5aa3d7` and SHA-1 `bfc4a6d01b977d55ad4dadc0123339343f1aa975`. The actual archive payload verified from the parent `fax.zip` is 256 bytes, SHA-256 `b18698a293a9f20fca832c2ddc49f5853f4702e39dc90708b54e2be33bf9e984`, with three distinct byte values. The `fax2.zip` clone omits this shared member; the audit found it in `fax.zip`, matching the MAME clone relationship and manifest.

The pinned driver comments that the FAX PROM region is “loaded, but not hooked up.” A source-wide search finds no PROM-region consumer or `fxl-12b` reference outside the two ROM declarations. MAME's current bank handler is a direct `data & 0x1f` operation; it does not use `fxl-12b` to decode the bank. Consequently, the current MAME contract requires no PROM lookup for CPU question-bank reads. If hardware-level evidence later says this PROM participates in a board decode, that would need a separate schematic/logic contract and explicit loader stream; do not invent a PROM decode from the filename or ROM declaration alone.

## Archive-backed boundary runner

`tools/fax_bank_prom_audit.py` re-reads the MAME availability manifest and private `fax.zip`/`fax2.zip` members, checks each member's size, CRC32, and SHA-1, reconstructs the 192 KiB question images with their holes zero-filled, and checks their hashes against the earlier independently recorded expansion-image manifest and ignored staged images. It enumerates bank select examples after the MAME `& 0x1f` mask, records first/last-byte expectations for all valid banks, identifies invalid region offsets for 24-31 without emitting fake expected data, and checks the candidate adapter's fixed 24-bank boundary and zero-result policy against its source. It also verifies `fxl-12b` for both sets and checks that the pinned MAME source still has no PROM consumer.

Run from PowerShell with read access to the private archive directory:

```powershell
py -3 tools/fax_bank_prom_audit.py --rom-dir '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'
```

Result: `PASS FAX source/archive audit`. FAX question image SHA-256 is `462bf48564d2e40647dfad3f35bc794bed6432f6d20da8282d0b9aa11145817a`, with empty banks `[22, 23]`; FAX 2 is `9171f92c9a84e193bb875cd3b197634ef5803f48104a2028f9aed6b73ab892ae`, with no empty in-region banks. Both sets' verified `fxl-12b` hash is `b18698a293a9f20fca832c2ddc49f5853f4702e39dc90708b54e2be33bf9e984`. The full metadata report is at ignored `simulation/fax_bank_prom/report.json`.

Remaining dependencies include an actual `$2000` bank-select latch in the core, mapping the candidate storage to that register/window, validating the index-1 and question-stream profile relationship, and deciding whether the 24-31 MAME out-of-region case is unreachable in both games. The MAME source's unused PROM declaration does not add a PROM-load requirement for MAME-compatible banking. No production RTL, QIP, MRA, or shared integration tracker was changed.
