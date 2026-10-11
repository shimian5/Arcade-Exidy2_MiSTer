# FAX startup branch and playable reference — 2026-10-11

FAX/FAX 2 now have a reproducible route into reference gameplay. A diagnostic
override of **P1 port `$1c00`, bit 2 low** bypasses the startup-check branch that
kept earlier captures outside normal play. This is deliberately different
from MAME's declared unused-bit default; it is not an unmodified MAME pass or
a working FPGA game. Physical pin/jumper semantics still need verification.

## Evidence

The new `tools/reference_cases/fax_health_capture.lua` wraps either existing
gameplay or Free Play driver and adds passive CPU-state samples every 60
frames and actual NMI/IRQ vector read counts. Program/ROM memory and bank
state are not modified. Without the optional override, it preserves inputs.
`fax_health_summary.py` requires all 121 ordered samples, completion at 7200,
18 passing input checks and no error marker; emulator exit alone is insufficient.

Both fresh FAX2 baseline captures complete but stay outside gameplay:

| FAX2 configuration | Late samples with I flag set | Final IRQ vector pairs |
| --- | ---: | ---: |
| Default DIP, ordinary inputs | 61/61 | 1 |
| Free Play, ordinary inputs | 61/61 | 1 |
| Free Play, diagnostic bit 2 low | 9/61 | 3,968 |

Baseline CPU PCs and question pointers keep changing; this is not a stopped
CPU. Byte-suppressed debugger inspection identifies the startup branch at
`80D9`: it tests the result of the port-bit check at `C6AA`. A zero result
branches to `8123`, followed by interrupt enable at `8126`; a nonzero result
enters the long question-processing path around `8106`/`F8A4`. The `C6AA`
routine tests `$1c00 & 4`. PC labels refer specifically to the inspected FAX2
image. No instruction-byte dump or disassembly is committed. The debugger
used [MAME's opcode-suppressed dasm command](https://docs.mamedev.org/debugger/memory.html#dasm).

The pinned MAME `exidy.cpp` declares IN3 bits 3:2 as unused, active low,
therefore high at idle. Its declared four buttons and starts remain unchanged
in the diagnostic. Only the CPU-visible bit 2 is forced low by a read tap,
enabled explicitly with `FAX_HEALTH_FORCE_STARTUP_BIT2_LOW=1`.

The diagnostic FAX2 snapshot at frame 4800 visibly shows a World Travel
question with an answer, after the declared coin/start/answer sequence. FAX
with the same override reaches its difficulty menu at frame 4800 and a
visible History question with four answers at frame 6000. Both complete 7200 frames
and 18 input checks. FAX records 4,218 IRQ vector pairs and 7/61 late samples
with I set. These are bounded gameplay observations, not all-bank, all-question
or completion acceptance.

Ignored evidence directories:

- `simulation/fax-health/fax2-default/`
- `simulation/fax-health/fax2/` (Free Play baseline)
- `simulation/fax-health/fax2-bit2-low/`
- `simulation/fax-health/fax-bit2-low/`
- `simulation/fax-health-debug/` (temporary opcode-suppressed inspection)

Use MAME 0.288, the same pinned archives/settings as
[the prior capture](fax-gameplay-capture.md). Set `FAX_BANK_OUT`, `FAX_BUS_OUT`,
`FAX_EVENT_OUT`, `FAX_HEALTH_OUT` to files in a fresh ignored run directory;
set `FAX_HEALTH_BASE_SCRIPT` to the absolute existing gameplay/Free Play
script, `FAX_CAPTURE_FRAMES=7200`, and run the new wrapper as the autoboot
script with delay zero. Set the diagnostic variable only for the isolated
override run. Validate with:

```powershell
python tools/reference_cases/fax_health_summary.py simulation/fax-health/fax2-bit2-low
```

## Input-helper change and remaining gates

`rtl/fax_controls.v` is still an unbound helper. Its new `STARTUP_CHECK`
parameter defaults to zero, selecting the observed normal-startup branch;
setting it to one preserves the previous high-bit/MAME-default behavior.
P1 idle is now `$fb` in normal mode. Bit 3, answer/start mappings, P2 and
non-FAX reads are preserved. The updated focused Verilator 5.052 fixture passes (`PASS fax controls`),
with ignored logs `simulation/fax-health/controls-build.log` and
`controls-run.log`. It checks both startup values, each answer, starts, P2 and disabled/address/write gates.
No release MRA, production core read mux or QIP is changed by this helper edit.

The future FAX integration should explicitly choose this startup setting and
retain an optional diagnostic mode only if justified by board evidence. It
still needs the exact profile/loader gate, question memory bank binding,
complete RAM/map parity, P2 inputs, runnable MRAs and full-core fit. Repeat
reference questions/answers, empty-bank boundaries and resets before game
acceptance. The input result resolves the prior reference-startup blocker;
it does not prove the physical pin was intended to be strapped low.
