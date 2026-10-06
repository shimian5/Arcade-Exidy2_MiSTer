# Increment 2 — simultaneous skid dequeue/enqueue

This single owner-authorized increment repairs byte loss when an older skid entry drains on the same clock that a new byte arrives. The outgoing byte uses the write port; the incoming byte replaces it in the pending slot for the next clock. Transfer-end drain handling now uses the same byte handler, preventing double handling or a false overflow fault for a legal late arrival.

Verilator 5.052 checks pass for:

- Three begin-index transitions and upper-index concurrent-byte rejection from increment 1.
- Six distinct byte values AA/BB/CC/DD/EE/FF delivered exactly once, at addresses 0–5 and index 0, with consecutive arrivals, start+first-byte, stop+write and delayed end-pending write. Transfer and pending state drain completely without a fault.
- A second arrival while the single speech skid slot is blocked: fault asserted, no forwarded writes, older byte AA retained and wait asserted.

The stale-acknowledgement diagnostic still exits nonzero at its intended expectation. [Results](increment-02.json) retain source/test hashes and all five case outcomes. Adapter acceptance remains false. These raw-interface checks do not prove host backpressure, faulted-session quarantine or physical CDC safety.

```powershell
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/review.py
```

Production files/releases remain unchanged; no Quartus build was run. **Stopped after this increment awaiting owner go-ahead.** The next proposed increment is a fresh read-revocation acknowledgement handshake before speech overwrite, including stale-high and stopped/slow remote-clock checks.
