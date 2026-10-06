# First worker block: baseline review

Started 2026-10-06 following owner authorization. Three Luna workers gathered bounded evidence; the integrator reviews results before updating WORKPLAN.md. No core RTL, release MRA/RBF, or Quartus build changes belong to this block.

| Unit | Worker | Evidence | Review |
| --- | --- | --- | --- |
| Release/source baseline | baseline_releases | [Release report](releases/README.md), [manifest](releases/manifest.json) | Accepted: integrator independently recalculated all 133 tracked file hashes; zero mismatches. |
| ROM/MAME availability | rom_availability | [ROM report](roms/availability-report.md), [manifest](roms/availability-manifest.json) | Accepted: 28 set records, no metadata parse errors, no empty sample references; MAME executable hash independently verified. |
| Build/simulation tooling | toolchain_audit | [Toolchain report](toolchain/toolchain-audit.md), [manifest](toolchain/toolchain-manifest.json) | Accepted: Quartus version independently confirmed; unsandboxed WSL discovery establishes available Arch Verilator/Make. No compile or simulation run. |

## Preserved baseline and local artifact policy

- Source HEAD: `bfd1b5c2a1ea7607f3cf7255b01a8dc2a11f8236`, branch `main`.
- Comparison release: `releases/Arcade-Exidy2_20240526.rbf`; this does not establish the image installed on owner hardware.
- No tracked `.gitmodules` or gitlink entries were found. `git submodule status` encountered a Windows Git shell error; independent direct checks establish the submodule inventory.
- Workers share the checkout with disjoint documentation directories. No worker compiles or edits shared RTL in this block.
- Existing ignore rules cover `simulation/` and `output_files/`, verified with `git check-ignore`. Future ROM-dependent fixtures/captures go under ignored `simulation/`; future build outputs use isolated directories consistent with the ignore policy.
- No ROM bytes or assembled images are included in these documentation artifacts. NAS access is read-only; this block does not copy archives into MAME's local ROM directory.

## What this block does not establish

Release hashes do not establish source-to-RBF reproducibility. ROM archive presence or MAME verification does not establish correct MRA download layout or gameplay. Static project inspection does not establish successful Quartus elaboration, fit or timing. Original reports remain open until their corresponding reproduction and acceptance tasks pass.

## Results and next block

W01 is complete. W02 availability, per-set verification and metadata are complete; local staging, existing MRA byte-layout verification, loader extensions and storage estimates remain open. No ROM copies were needed because MAME verified directly against the read-only NAS search path.

- All 28 target ZIPs and declared clone parents exist. MAME reports 27 good sets and `mtrapb` best available with `74s288.6c` needing redump. Process exit codes were not captured; verbatim verification output is retained in the manifest. Sample metadata is captured, but sample archives were not verified.
- Behavioral reference: local MAME `0.288 (mame0288)`, SHA-256 `DCF8677FCE188E8E2625D4A2928005565652930D3F85D930F5D49D939535B182`. The owner-labelled 0.257 library passed verification except for the documented bad-dump warning; do not infer that moving master source matches this executable.
- Installed Quartus: `17.0.2 Build 602 07/19/2017 SJ Lite Edition`, confirmed with unsandboxed PowerShell `quartus_sh.exe --version`. No compile stages ran.
- WSL Arch Linux: Verilator 5.052 and Make 4.4.1. Ubuntu: Make 4.3. No GHDL/Icarus found in either distro. Exidy2 has no checked-in simulation harness; the VHDL CPU/RIOT/6840/RAM paths require a mixed-language or approved translated simulation strategy.
- Missing CDF/SignalTap references and legacy timing exceptions are recorded as audit leads, not proven build failures.

Recommended next three bounded units:

1. Audit the six existing MRA download layouts against hash-verified archive entries and the current loader; report packing/address/hash mismatches without changing game logic.
2. Specify a reproducible Exidy2 simulation/reference harness, pin matching MAME source, and establish how the selected VHDL dependencies will be exercised. Prove a small fixture before relying on gameplay results.
3. Build an isolated native-raster measurement fixture using the actual source clock/counter logic; measure totals, active boundaries and sync phases before proposing CRT clock ratios.

These units are proposed for the next execution block, not launched by this handoff. No source defect or forum issue is closed by the baseline audit.
