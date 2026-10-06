# Independent accepted-input video queue

The sixth-block diagnostic passes all eight X/Y coordinate bitplanes. Every tested frame contains 65,536 accepted input samples and 65,536 matching output samples, with 256 samples in row 0 and row 255, ending at x=255/y=255. Input pattern and row-width checks have zero errors. The deliberately corrupted first FIFO expectation fails with `FIFO_MISMATCH` and nonzero simulator exit. [Results](results.json) retain source and compatibility-copy hashes.

The previous missing x=255 and one-pixel mismatch were fixture stimulus/timestamp-origin errors. The old fixture prepared input on `negedge core_pix_clk`, after `arcade_video` had accepted that pixel. This fixture prepares stimulus at the preceding master-clock falling edge using only the upcoming **input** raster and independently labels actual accepted samples at the master rising edge. Output does not influence stimulus, coordinate labels or expected data. An ordered queue carries actual input RGB, coordinates and timestamps to independently reconstructed output DE coordinates. The third input frame is measured after two startup frames; no boundary samples are omitted.

Matched input-to-output register-update latency is 18 master clocks at an eight-clock pixel cadence. Observation occurs after the mixer VGA-register update at a master rising edge whose pre-edge CE_PIXEL is high. This proves this simulated capture/output-register contract. The final downstream receiver sampling, game renderer, enabled gamma/effects, OSD, CRT converter and physical outputs remain separate gates.

The simulation-only mixer scope normalization is unchanged from the fifth block. The runner imports its source-asserted extractor and directs generated copies/logs into its own run directory; it does not edit previous evidence or production sources. Gamma parameter is 1 with gamma enable off, FX0 and no freeze.

```powershell
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/video_queue/measure.py
```

Use `--run-dir simulation/video_queue_review --report simulation/video_queue_review/results.json` for independent replay. Verilator 5.052 is required in the existing Arch WSL environment. Generated binaries/logs are ignored. The runner checks positive exits and explicitly requires the negative to fail.

Stopping point: the synthetic input-to-output queue gate is passed. Production mixer elaboration in Quartus, actual renderer tap/clock integration and complete Native/CRT image acceptance remain unfinished. Historical fifth-block failures are retained as reproducible fixture diagnostics, not attributed to a production RGB/DE defect.
