# PIA callback status branch review

This review follows the four matched response callbacks from the passive MAME
capture at `simulation/pia_firmware_timing/20261007_03` into the corresponding
main-CPU program routines. MAME 0.288 ran against the pinned split-set archives
recorded in that run's manifest (MAME source commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`). The debugger's `dasm` command was run with opcode-byte output disabled. Temporary disassemblies stayed outside the repository; this note records only control-flow conclusions and PC labels.

| Set | Captured CRA status / PA data reads | Status test and success path | Timeout path |
| --- | --- | --- | --- |
| Venture | `C966` / `C983` | `BIT $5201` followed by `BMI $C983`; this branch tests CRA bit 7 and enters the PA read only when it is set. | A countdown loop and delay subroutine recheck CRA. If still clear, code sets a software timeout flag and returns zero. |
| Mouse Trap | `AC05` / `AC1D` | `BIT $5201` followed by `BMI $AC1D`; this tests bit 7 before the PA read. | A countdown loop and delay subroutine recheck CRA; timeout sets a software flag and returns. |
| Pepper II | `A302` / `A31A` | `BIT $5201` followed by `BMI $A31A`; this tests bit 7 before the PA read. | A countdown loop and delay subroutine recheck CRA; timeout sets a software flag and returns. |
| Hard Hat | `B446` / `B45E` | `BIT $5201` followed by `BMI $B45E`; this tests bit 7 before the PA read. | A countdown loop and delay subroutine recheck CRA; timeout sets a software flag and returns. |

Thus each sampled response routine does more than read CRA first: the actual
6502 control flow waits for bit 7, and the matched PA data read is on the
bit-set branch. The passive capture's callback order agrees with that code.
The routine has a bounded software timeout; this review does not infer a
hardware-time bound from its loop count.

The extra pre-source PA reads are in setup/configuration routines, separate
from these response callbacks. Venture's setup at `C91D..C939`, Mouse Trap's
`AB9C..ABB9`, Pepper II's `A299..A2B6`, and Hard Hat's `B3DD..B3FA` clear the
PIA control/data state, configure the port direction and control registers,
then read PA before returning. They are consistent with an initial stale-flag
flush/acknowledgement, not evidence that a new response can be consumed without
waiting for CRA bit 7. The captures and code inspected here do not prove every
boot path or every possible call path reaches this initialization routine.

In this implementation, selecting PA data makes `porta_read` active during a
CS-qualified read (`modules/pia/pia6821.vhd`, `pia_read`). That read clears the
CA1 interrupt flag in the falling-edge CA1 process. The same module's CA2
output logic uses control mode `101` to make CA2 follow the inverse of
`porta_read`; with the observed CRA value `$2C`, the selected PA read therefore
also produces the configured CA2 read strobe. The ROM code does not perform a
separate CA2 acknowledgement access. The response protocol is CRA bit-7
assertion followed by PA data read, whose PIA side effects clear the flag and
strobe CA2.

This supports a pending-response mailbox contract for the four inspected
firmware routines: retain the response until the receiver observes the CA1
status flag and then reads PA. It does not establish behavior for uninspected
games, alternate ROM revisions, exceptional startup paths, or an FPGA timing
margin. ROM contents and instruction-byte dumps are intentionally not included.
