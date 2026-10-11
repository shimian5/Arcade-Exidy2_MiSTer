# Actual T80 voice-I/O and RIOT callback join — 2026-10-11

## Corrected reference contract

The previous helper audit left MOS6532 callback semantics unresolved and tested a raw ORA-only callback. That interpretation is superseded. The official pinned [MAME MOS6530/6532 implementation](https://github.com/mamedev/mame/blob/27a8d9e85b58058965907d1d8a7a92f8ed039348/src/devices/machine/mos6530.cpp) was retrieved to ignored `simulation/reference_sources/mos6530.cpp`, SHA-256 `41BE46E64708319DD7CBEDAD0D8E8B9713A6963C1853B4899CD3EEA12103D6F7`.

`update_pa` (195–206) emits `(ORA & DDRA) | ~DDRA`. Reset invokes it after clearing both registers (172–187); both PA data and DDR writes invoke it (418–440). Input-configured bits are pulled high, independently of external input-pin state. Combined with `exidysound.cpp`'s saved-command/reset handler, this requires command capture and reset control from the callback byte. It is neither raw ORA-only nor a callback only when physical pins change.

## Candidate changes

[mousetrap_voice_command.v](../../../rtl/mousetrap_voice_command.v) tracks accepted PA data and DDR writes, including address mirrors; computes the callback byte; and emits the initial reset callback. Its accepted-write input is a per-clock accepted register write, not an asynchronous bus level. It must observe every actual RIOT write or its shadow registers diverge. Timer/edge/PB register writes do not produce PA callbacks.

[mousetrap_voice_io.v](../../../rtl/mousetrap_voice_io.v) now uses saved callback bit4 for CPU reset and accepts consecutive callback pulses without requiring a low intervening cycle. T80 I/O writes still use rising transaction acceptance so a held WR strobe cannot repeat the digit/PB0 side effect. Decoder reset stays independent. Both helpers remain unbound and outside QIP; production RTL/build inputs are unchanged.

## Joined actual CPU verification

`sim/mousetrap_voice_io/run_t80_join.ps1` compiles actual T80/Z80 VHDL, actual R6532 VHDL, speechRomBus, both candidate helpers and a synthetic instruction fixture. No game image is embedded. Two parallel instances use continuous enable and a one-in-four enable. Both execute the stream, assert CPU reset by PA4, release through a DDRA input pull-up, and execute the stream again.

Each instance checks eight completed IN results and ten OUT transactions across two epochs: command-only, clock-only low, combined command/high clock and unselected reads; PB-only, digit-only, simultaneous low/high and unselected writes. Memory stores verify the bytes the real CPU sampled, not merely combinational helper outputs. The first OUT is stretched with disabled enables and WAIT; bus address/data must stay stable and side effects remain correct. Actual R6532 PB0 input and DDR output override are checked. PA4 CPU reset must preserve digit/PB0 and decoder lifecycle.

Passing root run: `simulation/harness/mousetrap_voice_io/modelsim-t80-voice-20261011-161948-789/`:

```text
PASS T80 voice join div=1 epochs=2 reads=8 writes=10 held=46 disabled=18 wait=36
PASS T80 voice join div=4 epochs=2 reads=8 writes=10 held=94 disabled=72 wait=36
PASS actual T80 voice I/O and RIOT callback join
```

A deliberate raw-data callback substitution fails at reset initialization, proving the corrected callback contract is necessary. The runner requires that specific failure before accepting the negative control. Positive joined simulation has zero errors; 40 time-zero numeric conversion warnings come from the two existing T80 instances, with no testbench failure.

The updated exhaustive helper/R6532 runner also passes: 131,072 read cases, 65,536 write cases, consecutive callback pulses, consecutive aliased DDRA/ORA writes, non-PA exclusion, DDR-only release and the deliberately low external PA4 input versus pulled-high callback distinction. Evidence: `simulation/harness/mousetrap_voice_io/modelsim-20261011-162024-104/`, zero errors/warnings.

## Acceptance boundary and next unit

This closes the bounded actual-T80 I/O/RIOT callback join and replaces the erroneous earlier callback assumption. It does not run Mouse Trap firmware or produce sound. The joined fixture puts CPU, adapter and RIOT on one test clock and changes CPU enable cadence; it does not establish cross-domain command delivery or the real clock rates. Production binding needs a held-command/acknowledgment or FIFO crossing, aligned reset/image readiness, and accepted-write qualification matching the audio CPU's actual phi2/RDY behavior. Do not connect the candidate command byte directly across audio/speech clock domains.

Next bounded unit: qualify an MC3417-compatible CVSD decoder against pinned MAME behavior, including clock-edge polarity, syllabic adaptation, decay and reset. Then join full speech firmware, clock/status, decoder/filter/mix and expansion loader; perform a fresh full unsandboxed Quartus flow and hardware listening tests. The production build remains `020b2ae`; no new full-core build was needed for these unbound candidates.
