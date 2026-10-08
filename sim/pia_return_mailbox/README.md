# PIA return CDC fixture

Run the actual mixed-language PIA/mailbox checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File sim/pia_return_mailbox/run_pia_return_mailbox.ps1
```

The runner compiles the production VHDL `modules/pia/pia6821.vhd`, the snapshot and FIFO candidate modules, and this SystemVerilog fixture with ModelSim. For each of seven integer phase offsets it tests both a 0 ps and 500 ps shift; the latter includes exact master/audio edge coincidence at phase 6. FIFO cases also test phase 6 at 499 ps and 501 ps, one picosecond on either side. It exercises paired PIA handshakes, a first registered CPU data-bus sample, partial PB DDR, reset during a delivered pending response, a 4-snapshot burst, a one-audio-period CRB mode-101 pulse, and a 16-audio-period held write. `tb_pia_fifo_stream.sv` separately drives 4096 snapshots at the source rate once per phase/shift and checks ordered bytes, notification alignment, and overflow.

The PIA source notification is the raw PIA_8B CB2 output level, forwarded to PIA_9B CA1. The fixture configures PIA_9B CRA to `2C`, checks CRA bit 7 before reading PA, and keeps the PA read active long enough for PIA_8B to sample the returned CA2-to-CB1 acknowledgement. It does not invert CB2 or bypass the actual PIA input.

The default run includes the snapshot candidate as a negative/coalescing comparison and the FIFO candidate as the expected lossless implementation. Logs stay under ignored `simulation/pia_return_mailbox/`. `-Production` selects the production implementation only after `rtl/pia_return.v` exposes the promoted FIFO interface (`audio_notify`, `main_notify`, and `overflow`); it intentionally rejects the current legacy byte-only adapter.
