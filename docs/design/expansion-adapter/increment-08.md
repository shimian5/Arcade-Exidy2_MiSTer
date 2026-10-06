# Increment 8 — combined reset and read contract

Completed 2026-10-06. The isolated `exidy_expansion_bridge` combines the reviewed adapter, remote quarantine and unchanged baseline loader. All 27 synthetic/ROM-backed connected expectations pass in [results](increment-08.json).

Remote quarantine remains asserted while transport revocation, loader pending/fault, adapter fault or missing expansion readiness requires it. A transport stream reaching exactly 16 KiB cannot authorize speech reads after a malformed descriptor. Core reset hold covers raw download, active/draining transport, begin/end events, loader pending/fault and adapter fault; the end event keeps reset held through the loader's session-verdict edge. This is an integration candidate, not production wiring or a boot-complete policy.

Three new cases pass: malformed descriptor plus full-length speech keeps reads quarantined; successful extended speech followed by ordinary legacy base/marker order clears extension readiness and releases hold; the same legacy sequence recovers a loader-only protocol fault without exposing stale speech. The 21-case synthetic matrix and all three actual-ROM cases also pass with the combined contract. Adapter transport faults intentionally require shared reset; loader-only protocol faults retain the baseline's legacy recovery path.

The remote domain may drain already accepted reads after revocation; acknowledgement waits for that drain before overwrite. Physical metastability/reset release, actual CPU/audio integration, HPS commands outside the file block, fast MMIO, fitted resource/timing and FAX PROM/banks24..31 parity remain open. A standalone full-flow resource/CDC probe can now assess synthesis of this isolated candidate before touching production. No production or Quartus changes in this increment.

Replay: `wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/connected.py --rom-images simulation/expansion_adapter/rom-images`. Defaults now write increment-08 metadata, preserving earlier checkpoints; use explicit separate report/run paths for independent replay.
