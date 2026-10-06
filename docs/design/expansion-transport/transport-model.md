# Expansion download and CPU-read model

This unit tests the proposed ROM-expansion transport contract against the local MiSTer MRA loader's document-order behavior and the current main-CPU read pipeline. It is a Python behavioral model with synthetic extended payloads; it is not production RTL, a real new MRA file, an FPGA fit, or a boot/gameplay test.

## Observed MRA transfer order

The pinned local MiSTer loader at commit `d3e55f51fa4f62343c79cacb4f2736269482c3b9` reads the ROM `index` attribute (`support/arcade/mra_loader.cpp` lines 536–543), starts a download for that index and finishes it at the ROM closing tag (lines 327–366 and 799–846). Therefore each `<rom>` node is sent in XML document order. The six existing MRA files all contain ROM entries in order `0, 1, 2, 3`, with `address=0` (default). A nonzero `address` selects the loader's shared-memory path instead of ordinary byte transmission; proposed descriptor and expansion nodes must therefore use the normal `address=0` download path. Their current index-1 hardware bytes are:

| MRA | Index 1 |
| --- | ---: |
| TARG | `$01` |
| Spectar | `$02` |
| Mouse Trap | `$10` |
| Venture Revision 5 | `$10` |
| Pepper II | `$30` |
| Hard Hat | `$30` |

The full per-node inspection is in [existing-mra-order.json](existing-mra-order.json). These values are board flags, not MAME game enumeration. There is no current FAX MRA. The model uses `$30` as a provisional FAX/FAX2 lower-seven-bit flag based on the similar board profile; that mapping needs hardware/profile confirmation. It tests the candidate bit-7 marker values `$B0` for FAX and `$90` for Mouse Trap while preserving the lower flag bits.

The proposed expanded MRA ordering is index `1` marker, index `7` descriptor, index `0` base ROM, then the profile's required index `5` question or index `6` CVSD stream, with ordinary option/config entries such as index `2` permitted after the payload. The descriptor contains 16 bytes using the accepted layout: `EX`, version 1, profile id, mask bits for stream slots 0/5/6 in bits 0/1/2, three unsigned little-endian 24-bit byte counts for indexes 0/5/6, then two zero reserved bytes. Fixed literal descriptor bytes are tested independently of the encoder, so the mask mapping is not only round-tripped through shared code.

The session model requires exact, contiguous address sequences starting at zero for each index. It rejects missing, extra, duplicate, gapped, reordered, undeclared, or profile-mismatched streams and holds reset after a fault. A fresh index-1 transfer clears the prior expansion session. Since current legacy MRAs send index 0 before index 1, a legacy index-0 transfer with no fresh extended marker clears stale expansion readiness immediately; the later legacy index-1 byte leaves legacy mode active. Index-0 writes are separately represented as live base memory writes, so an index-1 recovery does not pretend those already-written bytes were undone. After a completed extension, the marker is disarmed while expansion reads remain enabled; trailing index-2 settings preserve readiness. A malformed transfer revokes readiness and leaves reset held.

The test fixtures' base lengths and ROM payloads are synthetic. No MRA was edited or created. The pinned loader's document-order behavior is directly observed; the installed MiSTer binary still requires physical validation of the proposed index transfers and reset transitions.

## Main CPU read timing model

The existing main CPU updates `cencnt` on each `master_clock` edge and registers `PH_1` from `cencnt[5:0] == 31` (`rtl/Exidy2.v` lines 84–106). T65 consumes `PH_1` as its enable, and its data input is the separately registered `CPU_databus_in` (`lines 165–197`). This creates a 64-master-clock interval between CPU enable pulses. `dpram_dc.vhd` uses an `altsyncram`; its output-register B generic is currently wired to the A generic at line 107. No production setting was changed. The behavioral path deliberately models a registered RAM Q followed by the existing CPU-data register and T65 sampling the prior registered value at the clock edge.

For a stable address changed just after a T65 enable, the new byte reaches the CPU data input after the two modeled register stages and is available well before the next 64-clock enable. The adversarial test changes address only on the sampling edge after holding the old address for 63 clocks; the CPU sees the stale prior byte. That negative case defines the implementation gate: keep address and bank selection stable for the full fetch interval, or add a wait-state/prefetch gate if an address can change that late. This Python result does not establish the exact Quartus `altsyncram` mode or a fitted CPU timing path.

Question address checks cover `$2000`, `$3fff`, bank 23's last byte, the 192-KiB store boundary, and the deterministic zero fallback for banks 24–31. That fallback is a proposed safety behavior; MAME's pointers past the declared FAX/FAX2 region do not prove its hardware parity. The CVSD address layout is checked as a 16-KiB independent store, but Z80 clock-domain access timing, CVSD clocking, and sound-device integration remain unmodeled hardware gates. FAX PROM wiring and the loaded-but-not-hooked-up PROM region remain unresolved as documented in the ROM expansion contract.

## Verification

Run from the repository root:

```powershell
python -m unittest discover -s tools/expansion_transport -v
python tools/expansion_transport/mra_order.py --output docs/design/expansion-transport/existing-mra-order.json
python -m py_compile tools/expansion_transport/model.py tools/expansion_transport/mra_order.py tools/expansion_transport/test_model.py
```

The suite verifies all six existing MRA XML orders, descriptor bytes/masks, successful synthetic FAX/FAX2/Mouse Trap streams, malformed and interrupted streams, fault persistence, stale-data clearing, extended-to-legacy order, config after payload, and positive/negative CPU read timing. No Quartus build, production RTL/MRA edit, or ROM archive access is part of this unit.
