# PIA reply transport and timing contract

The production `07a49c5` reply pipeline misses setup on every byte bit. Its
minimum related-clock edge window is 3.150 ns. Placement and setup steering
did not close it; opposite-edge capture shortens that window. A different
capture contract is required before changing the constraints.

## Ordered snapshot transport

The candidate samples the changed tuple `{PIA8 CB2, DDR-masked PB byte}` on
the audio clock and queues it in a four-word asynchronous FIFO. It forwards
raw CB2 polarity to PIA9 CA1. Each destination pop captures the byte first,
then delivers CB2 on the following master edge. Pops are at least two master
edges apart. The normal PIA PA-read/CA2 acknowledgement wiring is preserved.

This is a transport queue, not a firmware-consumed response mailbox. Firmware
need not read PA to drain it: newer source data can overwrite the destination
value before a slow CPU read, as in the original direct wiring. DDR/control
initialization changes also cross without requiring a CPU acknowledgement.
The FIFO preserves a one-audio-edge notification pulse that a latest-value
snapshot mailbox can coalesce. The rejected snapshot candidate remains a
negative comparison in the test source.

Either reset input asynchronously resets both FIFO domains through separate
local reset conditioners. Each domain's state resets from its local
conditioner's output; release is synchronous to that domain. Outputs are zero
while reset is asserted and until local release. An empty FIFO does not expose
retained array contents. This is coordinated link reset, not preservation of
an in-flight response through a reset.

## Throughput and retention

The fitted clocks have the 7:22 period ratio: at most seven source snapshots
arrive in 22 master cycles, while destination service permits eleven pops.
Neither CPU pause stops these clocks. Source output transitions are registered
PIA state and therefore persist at least one audio period. The FIFO sampler
observes them on the following source edge.

A saturated actual-Verilog test sends 4,096 changed byte/notification tuples
at every audio edge, at all seven relative phase offsets. It independently
checks every destination byte in sequence and notification on the next master
edge, and rejects overflow. Root replay passes all 28,672 tuples. An independent
integer event model of the pointer synchronizer latency also finds a maximum
writer-visible occupancy of two for the tested ratio/phases. These checks do
not model analog metastability or a stopped destination clock. If the clocks
or service rate change, the capacity contract must be requalified; full-buffer
guarding prevents overwrite but cannot preserve every transient input tuple.

## Timing bounds

The write pointer is published through two destination synchronizer stages.
The read process sees the updated synchronized pointer on the following edge,
so a newly written word cannot be captured earlier than two master periods
after the write (approximately 44.3 ns). The queue slot cannot be reused until
its read pointer has returned through the source synchronizer and the writer
advances around the queue. Payload is stable around capture.

`candidates/timing/pia-fifo.sdc` applies a **20 ns maximum delay** to all 36
array registers feeding the eight byte registers and notification-value
register. It also bounds each Gray-pointer crossing to 20 ns, shorter than
either source period and the minimum pointer change interval. Stage-to-stage
synchronizer paths, destination PIA/CPU reads and the remaining board paths
retain their ordinary clock constraints. No payload false path, multicycle
waiver or clock-domain-wide exception is added.

Installed Quartus 17 command help confirms `set_max_delay` is clock-relative
and does not support `-datapath_only`. Consequently fitted path delay, skew,
uncertainty and exception precedence must be inspected alongside slack; a
positive summary alone does not establish the physical bundle bound. Narrow
first-stage reset-conditioner exceptions do not excuse second-stage or local
reset recovery/removal.

## Evidence gates

The actual VHDL PIA/Verilog transport fixture covers normal/partial-DDR bytes,
forwarded CRA bit 7, the previously registered CPU bus sample, PA-read
acknowledgement, reset and subsequent response, unread write bursts and mode
101 short/held pulses. The snapshot negative comparison loses a burst update
and a short pulse; the FIFO preserves them. The final reset-during-pending
assertion and independent root replay pass. The final runner produced 30
paired-PIA PASS markers and 16 saturated-stream PASS markers, including exact
edge coincidence and its one-picosecond neighbors. These 16 streams delivered
65,536 snapshots in total. Root evidence is ignored under
`simulation/pia_return_mailbox/modelsim-20261007-230323-790/`.

An isolated full-project Quartus flow is running under
`simulation/pia-fifo-full-core/`. Production RTL, SDC and release files have
not yet changed. Promotion requires the final functional replay plus fitted
setup, hold, recovery/removal and bounded-path reports. Remaining legacy event
clocks/latches and exception coverage must be reported separately; this
transport does not repair every unconstrained board event.
