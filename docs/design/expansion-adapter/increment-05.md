# Increment 5 — connected source HPS transport and loader

Completed 2026-10-06. Two connected positives pass in [results](increment-05.json), with original production sources retained unchanged.

The runner extracts the original file-download decoder from `sys/hps_io.sv`, and the original GPIO two-register synchronizer plus ACK state-machine bodies from `sys/sys_top.v`. Only isolated wrapper declarations, initial fixture state, byte-wide constants and unused upload inputs are supplied. The bodies retain their original conditions and nonblocking assignments. These feed the reviewed adapter, remote read quarantine and unchanged fifth-block baseline loader. SHA-256 records pin each source and generated wrapper.

The host drives GPIO data, enable and strobe, waits for ACK high, lowers strobe, then waits for ACK low. Local Main sources confirm ordinary file transfer follows `user_io_file_tx_data -> spi_write -> spi_b/spi_w -> fpga_spi` with this ACK contract. Host-source hashes are recorded. The separate fast-block API does not perform this polling and remains outside acceptance.

Each test sends two extended marker/descriptor/base/speech sessions with different synthetic speech data. Each session verifies all 16,384 forwarded bytes, all stored memory bytes and all remote read-port bytes. Both ordinary and deliberately delayed ACK-observation variants pass: 32,860 host words, two live base writes, and 25 stopped-clock wait cycles before restart per session. Speech writes require matching remote generation, empty outstanding reads and blocked new reads. Incomplete images retain reset; exact complete images release loader readiness. The loader source copy still matches its baseline hash.

This closes the targeted ordinary file-transport connection and backpressure boundary. It does not test all HPS commands, actual SoC/MMIO execution, physical CDC/reset release, fitted RAM or FPGA output. Invalid descriptors and exact payload length/order/FAX2 matrices are next. Source-level loader readiness must still be combined with adapter faults in a production reset/read-enable contract. No Quartus build, release or production edits.

Replay: `wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/connected.py`. Isolated handshake regressions remain separately available through `review.py`.
