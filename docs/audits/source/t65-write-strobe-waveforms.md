# T65 write-strobe waveform fixture

This focused GHDL fixture runs the repository's actual `modules/cpu-t65/T65.vhd` against a synthetic ROM program. The program loads `$11`, then issues consecutive `STA` instructions to `$5000`, `$5040`, `$5080`, `$50C0`, `$5100`, `$5101`, `$5200`, and `$5201`, followed by a jump loop. It embeds no game ROM. `sim/teeter_nmi/tb_t65_write_strobes.vhd` uses the same GHDL 6 toolchain and T65 source list as the existing NMI fixture.

The fixture models the source's PH_1 clock-enable cadence: the master clock is 10 ns, and T65's `Enable` is asserted once every 64 master ticks, matching `cencnt` increment and `PH_1 <= cencnt[5:0] == 6'd31`. It checks the actual T65 bus address, `R_W_n`, and data for each expected write, requires the write bus to remain unchanged across sampled master edges, and verifies each write remains active over a PH_1 enable. It asserts RDY low during the first write and holds it until two actual PH_1 enables have occurred. T65 completes the in-flight write despite RDY low, advances to the next read at `$8005`, then holds that read request through the second PH_1 enable. The test checks that stable read request before resuming RDY and verifies the write sequence continues. The eight writes are back-to-back at the instruction level (no reload between stores).

The observed edge polarity matches the current source equations:

| Strobe | Decode polarity during write | Transition at write start | Transition at write end | Existing capture edge |
|---|---|---|---|---|
| `nWM1H`, `nWM1V`, `nWM2H`, `nWM2V` | High | rising | falling | rising, so capture begins the selected write |
| `nWMOL`, `nWCPL` | Low | falling | rising | rising, so capture occurs when the selected write deasserts |
| `WEVEN`, `WODD` | High | rising | falling | rising, so capture begins the selected write |

The fixture checks one active and one inactive transition for each bank. It also uses event-driven assertions on the strobe signals themselves, so the `$11` data is checked at the exact active and inactive transitions, including the `nWMOL`/`nWCPL` end-of-write rising edge rather than only at master-clock samples. The exact production expressions and PH_1 cadence are pinned by `tools/t65_write_strobe_source_guard.py`; if these lines change, the source guard fails and the waveform model requires review. `$5200/$5201` use a fixture-level address-window approximation for `ABSEL`, whose live source is the `U5C_out` decode; this fixture does not instantiate the Exidy2 wrapper or its decoder. Likewise, `$5100/$5101` are decoded from their addresses in the fixture. The tested CPU is real T65 RTL; the surrounding board decode is a source-guarded behavioral model.

Run from Windows PowerShell:

```powershell
wsl.exe -d archlinux -e bash -lc "cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/sim/teeter_nmi && make write-strobes"
py -3 tools/t65_write_strobe_source_guard.py
```

Result with GHDL mcode 6.0.0: `PASS T65 writes all eight decoded registers with stable bus and pause/resume`, simulation stopped at 25.326 us. The test emits expected time-zero numeric metavalue warnings from uninitialized internal T65 state; no assertion failed. Source hashes at run time:

- `rtl/Exidy2.v`: `4F39C4C29863E3C0FA0C61C574711C72B42A67A251FAEE85A3E785C35685FC2E`
- `rtl/audio_board.v`: `76E73D1C5D34E805254D27469C03378270B27CB717BD96433D0BA32BDA77D510`

This supplies edge-semantics evidence for considering clock-enable conversions; it does not propose or verify any production RTL change, reproduce Quartus timing, or measure fitted timing margins.
