# W02 ROM availability and MAME verification audit

Date: 2026-10-06

MAME: `0.288 (mame0288)`
Executable SHA-256: `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`
ROM library: `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)` (owner-labelled 0.257 split set)
ROM search path: `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split);C:\MiSTerDev\mame\roms`
Commands per set: ``mame.exe -noreadconfig -rompath "<NAS>;<local>" -listxml <set>`` and ``mame.exe -noreadconfig -rompath "<NAS>;<local>" -verifyroms <set>``. No game/UI launch; no ROM copies. `-noreadconfig` prevents user configuration from changing these checks. Verification stdout is saved per set in the JSON. Process exit codes were not captured by the original piped run; they were not rerun solely to capture exit codes.

MAME metadata was queried from installed MAME 0.288; the library is labelled 0.257, so this is a cross-version availability check. The 28 MAME ROM definitions include ROM name, size, CRC, SHA1, region, offset and merge attributes in `availability-manifest.json`. XML sample entries with blank names are omitted; nonempty sample names indicate sample references only, not that sample archives exist. `-verifysamples` was not run.

| Set | NAS ZIP | MAME verify | Parent | ROMs | Named samples |
|---|---:|---|---|---:|---:|
| sidetrac | 5513 bytes | good |  | 5 | 5 |
| targ | 8180 bytes | good |  | 10 | 5 |
| targc | 7128 bytes | good | targ | 10 | 5 |
| spectar | 10189 bytes | good |  | 10 | 5 |
| spectar1 | 9872 bytes | good | spectar | 11 | 5 |
| spectarrf | 3003 bytes | good | spectar | 10 | 5 |
| rallys | 9237 bytes | good | spectar | 12 | 5 |
| rallysa | 9223 bytes | good | spectar | 12 | 5 |
| panzer | 9156 bytes | good | spectar | 12 | 5 |
| phantoma | 8413 bytes | good | spectar | 7 | 5 |
| phantom | 8389 bytes | good | spectar | 7 | 5 |
| mtrap | 33654 bytes | good |  | 17 | 0 |
| mtrap4 | 15859 bytes | good | mtrap | 17 | 0 |
| mtrap4g | 15892 bytes | good | mtrap | 17 | 0 |
| mtrap3 | 15830 bytes | good | mtrap | 17 | 0 |
| mtrap2 | 15854 bytes | good | mtrap | 17 | 0 |
| mtrapb | 19253 bytes | best available (NEEDS REDUMP) | mtrap | 15 | 0 |
| mtrapb2 | 19571 bytes | good | mtrap | 15 | 0 |
| venture | 29073 bytes | good |  | 17 | 0 |
| venture5a | 22626 bytes | good | venture | 17 | 0 |
| venture4 | 23229 bytes | good | venture | 17 | 0 |
| venture5b | 25944 bytes | good | venture | 13 | 0 |
| teetert | 24439 bytes | good |  | 17 | 0 |
| pepper2 | 21209 bytes | good |  | 14 | 0 |
| pepper27 | 16418 bytes | good | pepper2 | 14 | 0 |
| hardhat | 19960 bytes | good |  | 10 | 0 |
| fax | 198471 bytes | good |  | 38 | 0 |
| fax2 | 187909 bytes | good | fax | 40 | 0 |

All 28 target ZIPs exist on the NAS. All 27 sets other than `mtrapb` report “is good”; `mtrapb` reports `74s288.6c (32 bytes) - NEEDS REDUMP` and “best available,” a known imperfect dump rather than a missing ZIP. Clone sets show their declared parent in MAME output (for example `targc [targ]`) and each parent ZIP is present in the audited set list.

`-verifyroms` establishes MAME archival ROM availability/integrity for this installed reference version. It does not validate MRA byte layout, sample archive availability, or gameplay. No differences beyond the `mtrapb` bad-dump warning were reported by this 0.288-vs-labelled-0.257 check.
