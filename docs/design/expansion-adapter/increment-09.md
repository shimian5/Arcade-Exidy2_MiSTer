# Increment 9 — full-flow synthesis exposes uninferred RAM

Completed 2026-10-06. **Probe failed; storage implementation is not accepted.** [Project metadata](increment-09-project.json) pins sources, device and limits; [result](increment-09.json) records the failure/log hash.

Ran Quartus 17.0.2 from unsandboxed PowerShell using the full `quartus_sh --flow compile expansion_probe` flow, following the owner's global instruction. The project lives in ignored `simulation/expansion_adapter/fit09/`; it targets the repository's 5CSEBA6U23I7 device, uses virtual data/control pins and abstract independent 50 MHz/10 MHz clocks. Production project/files remain unchanged. Asynchronous clock grouping is resource-probe scaffolding and provides no physical CDC signoff.

Analysis/synthesis reports both `question_mem` and `cvsd_mem` uninferred due to asynchronous read logic (276014/276007), then exceeds register capacity (276003). The full flow exits 3 before fitting. Earlier simulation passes establish behavior only; they did not establish synthesizable block-RAM mapping. No resource count, fitted timing or valid FPGA image is available from this attempt.

Next increment: preserve the baseline loader and implement a separate RAM-inference candidate with reset-free registered RAM read/write processes, keeping reset/valid/zero-result gating outside the arrays. Replay the baseline public-port/read-deadline checks and connected synthetic/ROM cases, then rerun the complete Quartus flow. Whole-core resource fit and physical clock/reset integration remain later gates.
