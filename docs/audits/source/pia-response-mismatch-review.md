# Venture PIA response trace: causal-order correction

## Correction (supersedes the earlier mismatch finding)

The earlier seven “stale response” mismatches were produced by sorting callbacks on `mame.time()` and comparing timestamps across the main and audio CPUs. That ordering is invalid for this trace. MAME can report the executing CPU's local scheduler time from a device callback; local times from two CPUs are not a globally sortable event clock. The CSV's callback row order is the causal order recorded by the passive taps.

In all seven disputed pairs, the main CPU's `PA_DATA=0x40` callback row precedes the audio CPU's `PB_DATA=0x00` write row. The first pair is CSV row 183188 (main read, timestamp 51.251590930 s) followed by row 183229 (audio write, timestamp 51.251248762 s). Thus the timestamp appears to run backward by about 342 µs while callback order shows the read happened first. The same row-before-write ordering holds for the other six pairs. They are **not evidence of a write-before-read stale response**; the old mismatch conclusion and its 337–361 µs “latencies” are withdrawn.

The callback-order analyzer now pairs each qualified audio PB write with the first main PA data-read callback after that row and before the next audio PB data-write row. Re-analysis of the frozen capture finds Venture: 5,790 qualified writes, 5,790 reads before the next write, 5,790 byte matches, and zero mismatches. It observes 7,027 timestamp regressions between adjacent callbacks, all across CPU labels. Signed callback timestamp differences remain diagnostic only and are not presented as elapsed latency.

Reproduce from the repository root:

```powershell
python tools/pia_firmware_timing/analyze_capture.py --run-dir simulation/pia_firmware_timing/20261007_03 --output simulation/pia_firmware_timing/analysis/20261007_03_causal.json
```

The CSV remains ignored at `simulation/pia_firmware_timing/20261007_03/venture/pia-bus.csv`, SHA256 `777A84E05FAD450EF18C6C1768FB220AC09603ABF0F161919BDDD9C773CA64AA`. The analyzer is [analyze_capture.py](../../../tools/pia_firmware_timing/analyze_capture.py). It reports callback-order pairing and timestamp regressions separately. The prior `20261007_03.json` timestamp-sorted output is historical and must not be used as evidence.

This correction resolves the apparent bus-trace mismatch only. It does not prove FPGA PIA behavior or establish cross-CPU elapsed latency. The filtered fetch logger omits main reads before its pending sequence is armed, so absence from that log cannot establish cross-run divergence or a scheduling effect caused by the extra tap.
