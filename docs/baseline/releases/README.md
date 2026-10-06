# Release and source baseline

Captured 2026-10-06 from `C:\MiSTerDev\Arcade-Exidy2_MiSTer`.

## Checkout

- Branch: `main`
- HEAD: `bfd1b5c2a1ea7607f3cf7255b01a8dc2a11f8236`
- Git tree: `f57689994caf04ee100f4ae88e1b1c1ee64a9879`
- Tracked state: clean; the only local change observed was pre-existing untracked `WORKPLAN.md`.
- Submodules: none recorded. `git submodule status` could not start its Git shell (signal pipe, Win32 error 5); direct checks found no tracked `.gitmodules` and no gitlink entries.
- Tracked files: 133. Per-file size and SHA-256 are recorded in `manifest.json`. The inventory digest is `836346f028f3177b1865918809fb8e089855e61352f8466278a41fbd3c00de00`; see the manifest for canonicalization.

## Release artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `Arcade-Exidy2_20240414.rbf` | 3,066,604 | `e5ffe369286701f595a7e6dac7c369dcebd29c291243d07b30ad1137c56807a8` |
| `Arcade-Exidy2_20240526.rbf` | 3,024,524 | `4462be721f00665944672c1e44711040eddeff82da7f155ffdac067351b43eae` |
| `Hard Hat.mra` | 1,700 | `8560a38c086a18c35132c110b0176025a7c167882a7b8da919992f80b2e74346` |
| `Mouse Trap.mra` | 1,723 | `f708811c2f32b93f9a7ec62948e2876065eebdc17e3a72fd132994fb96f57dea` |
| `Pepper II.mra` | 1,767 | `14ad9b676c8213d3e34bfffe18356e71d37977ea0a2977ea44badd9ae55b5064` |
| `Spectar.mra` | 1,620 | `7b62d8a4b6a71414484609d907bcf222749c2fbe3ce4958207ea584ed9729a9e` |
| `TARG.mra` | 1,649 | `b5c0d3f598671b9f7d058b6fcb5dfad57aa7a59d7fa863c1002cfa3727f371eb` |
| `Venture Revision 5.mra` | 1,827 | `e7da0534a3872e66faf4322ca0f964355aba082dcf74d91685daa403810a7381` |

The May 26, 2024 RBF is the newest dated repository release and is recommended as the comparison candidate. This does not establish the image or MRA currently installed on the owner’s MiSTer hardware. The original release artifacts were left untouched.

## Capture commands and limits

Commands run from the repository root: `git status --short --branch`; `git rev-parse HEAD`; `git branch --show-current`; `git rev-parse HEAD^{tree}`; `git ls-files`; `git ls-files -s`; `git ls-files .gitmodules`; PowerShell `Get-FileHash -Algorithm SHA256` for every tracked file and release artifact; `Get-Item` for release sizes and checkout timestamps.

Hashes identify the exact current bytes. The Git commit/tree identify the committed source baseline; the per-file manifest also captures content independently of Git object hashing. Checkout timestamps are included as local metadata only, not claimed upstream provenance. No Quartus build, simulation, ROM copying, release modification, or hardware test was performed.
