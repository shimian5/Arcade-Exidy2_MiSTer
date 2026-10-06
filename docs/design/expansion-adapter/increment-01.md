# Increment 1 — begin index

Owner authorized single increments with an explicit stop/go-ahead boundary. This increment changes only the isolated adapter's start handling and focused regression harness; no production wiring, Quartus build or release change was made.

The adapter previously registered `transfer_begin` and its private active index without updating the output index. The downstream loader therefore sampled the preceding stream index. The adapter now registers the output index alongside begin. Starts with nonzero upper index bits fault before creating a transaction; a simultaneous first byte is not retained or forwarded for that rejected start.

Verilator 5.052 regression results:

| Check | Outcome |
| --- | --- |
| Sequential starts 0, 7, 6 | Correct index with each begin, including downstream clock-edge observation; all three transfers drain. |
| Start 0x0106 with concurrent byte | Fault asserted, no begin, active transfer, skid byte or write. |
| Simultaneous skid drain/arrival | Known failure still reproduces. |
| Stale acknowledgement before overwrite | Known failure still reproduces. |

[Results](increment-01.json) retain source/testbench hashes, exits and ignored-log paths. The historical sixth-block report is unchanged. The adapter remains unaccepted until the remaining transport/quarantine gates pass.

```powershell
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/review.py
```

**Stopped after this increment.** Next proposed increment is the skid-buffer simultaneous dequeue/enqueue fix with ordered-byte regression. It has not started and requires owner go-ahead. Full connected HPS/loader transport, address bounds, CDC/quarantine, FAX2, synthesis and physical acceptance remain later work.
