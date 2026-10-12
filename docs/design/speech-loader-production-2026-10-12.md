# Mouse Trap speech loader production integration audit

Audit date: 2026-10-12. This note reflects the current top-level binding, the production wrapper and reset-conditioned loader sources, the candidate MRA, and the wrapper fixture result.

## Production connection and clocks

`Arcade-Exidy2.sv` now instantiates `rtl/speech_loader.sv` as `exidySpeechLoader`. It receives raw HPS `ioctl_download/index/wr/addr/dout`, runs its main transport on `clk_sys`, and uses native `clk_audio` for the CVSD port and speech-enable synchronizer. Its `ioctl_wait` returns to `hps_io`. Its normalized `base_wr/base_addr/base_data` feed `exidy2.dn_wr/dn_addr/dn_data`; the live raw index-1 byte still updates `mod_other`, so PCB values including `B0` and `D0` remain intact for the core. The top-level CPU reset remains `(RESET | status[0] | buttons[1] | ioctl_download | loader_hold)`, while the bridge reset input is `!RESET` only. That split is required: each MRA component asserts `ioctl_download`, so using it to reset the bridge would destroy state between component downloads.

Production sources are `rtl/expansion/exidy_expansion_bridge_rr.sv`, `rtl/expansion/exidy_transport_adapter.sv` (which also defines `exidy_cvsd_read_quarantine`), `rtl/expansion/exidy_reset_sync.sv`, and `rtl/expansion/exidy_expansion_loader_rr.sv`. The latter has separate 192 KiB question and 16 KiB CVSD RAMs and destination-domain `cvsd_reset_n`. The wrapper filters raw indices to 0, 1, 6, and 7 before the transport; options/config/NVRAM indices 2, 3, 4, 254, 255 and other unrelated indices do not create loader sessions. The speech RAM read port and speech-enable synchronizer use native `clk_audio`; do not replace it with `auPH0` or another divided enable.

The board ROM remains in `rtl/rom_loader.sv`: `selector` maps the start of index 0 to the 64 KiB `eprom_0`, then maps later offsets to board audio, graphics, mapper, and PROM RAMs. The wrapper’s base bus is deliberately a registered tuple: its `base_wr` pulse, `base_addr`, and `base_data` all come from the same accepted adapter output byte. The wrapper fixture checks each output against the corresponding raw index-0 address/data sampled by the adapter, including the pulse delay. Do not wire raw `ioctl_addr/ioctl_dout` alongside the delayed `base_wr`; that would misalign address/data from the write strobe.

## Session identity and image contract

The ordinary shipped `releases/Mouse Trap.mra` uses index 1 byte `10`. That byte selects the ordinary Mouse Trap board and does not prove that speech data was loaded. Speech is enabled only after exact marker byte `90`, descriptor acceptance, base-image length acceptance, and the complete CVSD image. Existing interrupt-profile candidates use high-bit PCB bytes `B0` and `D0`; the wrapper recognizes only exact raw byte `90` as the new speech marker. For any other index-1 byte it clears bit 7 only in its private loader data (`{0, raw_data[6:0]}`), while `Arcade-Exidy2.sv` continues passing the original `ioctl_dout` through to `mod_other`.

The descriptor contract is 16 bytes: `45 58 01 03 05 40 49 01 00 00 00 00 40 00 00 00`. This is magic `EX`, version 1, Mouse Trap profile 3, mask `05`, little-endian index-0 byte count `0x014940`, zero question-image length, little-endian CVSD byte count `0x004000`, and zero reserved bytes. The required stream sequence is index 1 marker `90`, index 7 descriptor, index 0 base image with exactly `0x14940` bytes at contiguous addresses starting at zero, then index 6 CVSD image with exactly `0x4000` bytes at contiguous addresses starting at zero. The loader keeps speech reset/quarantine active until index 6 completes and commits readiness. Address gaps, extra/short streams, invalid descriptors or invalid transfer order fault the extended session and leave speech disabled until external reset.

## MRA order is part of the protocol

MiSTer’s MRA parser calls `rom_start(arc_info->romindex)` on each `<rom>` start tag, processes its `<part>` nodes, and calls `rom_finish(..., arc_info->romindex)` at the matching `</rom>`; see `../Main_MiSTer/support/arcade/mra_loader.cpp`, around lines 737–858. It transmits each component in document order. The expansion loader requires marker → descriptor → base → speech, so the candidate MRA now orders its `<rom>` elements `1, 7, 0, 6, 2, 3`; the NVRAM declaration follows. The production wrapper filters trailing indices 2 and 3. This ordering is essential; the former index-ascending candidate order would have faulted before the descriptor and speech could validate.

The candidate file is `candidates/mra/Mouse Trap (speech expansion candidate).mra`. It retains the release’s index-0 parts, index-2 value, index-3 24-byte legacy record, and NVRAM size; it uses index 1 `90`, and adds index 7 plus the index-6 speech image assembled from existing `mtrap.zip` components. Index 0 emits `0x14940` bytes: `0xA000 + 6*0x1000 + 0x2800 + 3*0x800 + 0x800 + 0x100 + 0x20 + 0x20`. The release MRA does not provide the final 32-byte tone slot at `0x14940..0x1495f`, so the candidate does not invent that data.

The four speech ROM parts match the reviewed MAME manifest `docs/baseline/roms/availability-manifest.json`, set `mtrap`, region `soundbd:cvsdcpu`: `mta_2a.2a` CRC `13db8ed3`, `mta_3a.3a` CRC `31bdfe5c`, `mta_4a.4a` CRC `1502d0e8`, and `mta_1a.1a` CRC `658482a6`. Each is 4 KiB and the order corresponds to offsets `0000`, `1000`, `2000`, and `3000`. The runner verifies the private staged 16 KiB image against `docs/design/expansion-adapter/increment-07-roms.json`; it never copies or prints those private bytes.

Legacy index-3 records in the checked-in MRAs are distinct from the new loader descriptor:

| MRA | Index-1 byte | Index-3 bytes |
| --- | --- | --- |
| `releases/Mouse Trap.mra` | `10` | `59 00 00 00 00 FF 00 02 00 02 00 01 00 FF 02 00 00 00 03 80 00 23 00 48` |
| `candidates/mra/Venture Revision 5 (int-profile test).mra` | `50` | `4D 80 00 00 00 FF 00 02 00 02 00 01 00 FF 02 00 00 00 03 80 00 23 00 53` |
| `candidates/mra/Pepper II (int-profile test).mra` | `B0` | `66 00 00 00 00 FF 00 02 00 02 00 01 00 FF 02 00 00 00 03 60 00 23 00 11` |
| `candidates/mra/Hard Hat (int-profile test).mra` | `B0` | `5D 00 00 00 00 FF 00 02 00 02 00 01 00 FF 02 00 00 00 03 60 00 23 00 11` |
| `candidates/mra/Teeter Torture (integration candidate).mra` | `D0` | no index 3 record |

## Fixture evidence and remaining work

`sim/speech_loader/run.ps1` extracts the descriptor and ROM index order directly from the candidate MRA, checks emitted base/speech sizes against the reviewed MAME manifest, verifies the private payload hash, and runs Verilator 5.052 against the actual production wrapper and `rtl/expansion` sources. The fixture covers unrelated-index filtering, legacy PCB bytes `10`, `30`, `50`, `B0`, `D0`, a short-base fault, external-reset recovery, the candidate in actual XML order, all 84,288 normalized base write tuples, the private 16 KiB CVSD payload, synchronous speech reads at addresses `0000`, `1234`, `3fff`, and a later legacy `10` reload that clears speech enable. Result: `PASS speech_loader wrapper tuples=84288 base_bytes=84288 speech_bytes=16384 legacy=10,30,50,B0,D0`.

The wrapper and top-level binding are now present, but a Quartus full-flow build and hardware test have not been performed in this fixture task. Speech CPU/ROM bus, command I/O, decoder, filtering, and audio mix still need to be checked as one production path. The fixture verifies digital loader behavior and tuple alignment, not timing closure or audible output.
