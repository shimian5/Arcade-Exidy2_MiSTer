# PIA return-byte placement experiment review

## Bit-5 path evidence

The one-bit placement trial assigned `audio_byte_stage[5]` to `FF_X37_Y16_N26` and `main_byte_data[5]` to `FF_X37_Y16_N25`. The fitted timing report puts the mapped feeder at `LABCELL_X37_Y16_N24`, so source register, feeder logic and destination register all occupy the same X37/Y16 LAB. The feeder is not left at a remote tile by the register-only assignments.

With production constraints after the setup-steering fit, the byte path remains failing: bit 5 is worst at -0.431 ns. Its reported data delay is 2.493 ns, including 2.156 ns from source Q through interconnect to the feeder input, 0.077 ns through the feeder cell, and 0.260 ns in the destination register. Setup relationship is 3.150 ns; clock skew is -0.758 ns. The earlier placement-only result for this same assigned pair measured 1.977 ns source-to-feeder interconnect, 0.077 ns feeder cell, and 0.260 ns destination cell, for 2.314 ns data delay and -0.236 ns bit-5 slack; another byte bit remained worst at -0.330 ns. This shows that same-LAB co-location can improve one placement result, but does not make the path pass or make the result repeatable across fitter runs.

The targeted hold report for bit 5 has +0.609 ns slack and 1.794 ns data delay; it uses the same local feeder and reports no inserted delay chain. That path does not support blaming the setup route on hold repair. The hold and setup values are from separate checks and should not be combined into a causal claim.

## Quartus assignment support and resource limits

The installed Quartus Prime Shell is version 17.0.2 Build 602. Its interactive `help set_location_assignment` confirms the assignment command and states that legal location values depend on device/package/resource; it directs users to the Assignment Editor Browse dialog to identify legal resource locations. The existing one-bit trial proves that `FF_X...` assignments to these register nodes are accepted and honored. It does not prove a `LABCELL_X...` location assignment to the feeder is legal for this device, so a feeder-location assignment is not proposed.

The fitter did place one audio-clock FF and one master-clock FF in the same LAB, proving that this mixed-clock pair is legal in the observed fit. That does not prove eight pairs can be packed together. Each source register has its synchronous reset condition, each destination has a feeder data path, and shared LAB control/input resource limits may prevent a byte-wide packing. The saved site inventory lists FF occupancy only; it cannot establish available combinational LUT resources or all control compatibility. The local feeder's exact placement is visible in the timing path, but no complete fitted LUT occupancy report is available in this evidence set.

## Recommendation

There is no evidence-backed local-feeder move: the feeder is already in the same LAB as the bit-5 source and destination. Repeating the single-bit constraint or assigning a feeder location without device-specific legality evidence is not justified. A full-byte paired-register placement is defensible only as one isolated diagnostic fit using observed-valid, unoccupied FF sites, with no assumed feeder placement. It is not an expected repair: the locally paired bit still misses by 0.431 ns in the production-SDC replay, and the prior fit's single-bit improvement left other byte paths failing.

Before such an all-byte trial, a post-fit inventory must confirm all candidate FF sites and the fitter must validate LUT/control resources. After fit, replay the original production SDC and inspect all eight setup and hold paths; do not use the stronger steering SDC summary as acceptance evidence. If the purpose is to close timing rather than measure a physical lower bound, stop physical-only steering here and investigate a separately justified protocol or register architecture. Placement evidence does not justify a timing exception or handshake change.
