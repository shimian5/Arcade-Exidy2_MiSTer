$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) {
        throw "Required ModelSim executable is missing: $(Join-Path $modelsimBin $tool)"
    }
}
$runName = 'modelsim-t80-voice-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$outputRoot = Join-Path $repoRoot 'simulation\harness\mousetrap_voice_io'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot $runName
$resolvedOutputRoot = (Resolve-Path $outputRoot).Path
New-Item -ItemType Directory -Path $runDir | Out-Null
if (-not $runDir.StartsWith($resolvedOutputRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Run directory escaped ignored simulation output: $runDir"
}

Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit $LASTEXITCODE" }

    $vhdl = @(
        (Join-Path $repoRoot 'modules\cpu-t80\T80_Pack.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80_MCode.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80_ALU.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80se.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\Z80.vhd')
    )
    $vhdl += (Join-Path $repoRoot 'modules\riot\R6532.vhd')
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed with exit $LASTEXITCODE; see $runDir\vcom.log" }

    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        (Join-Path $repoRoot 'rtl\speech_rom_bus.v') `
        (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') `
        (Join-Path $repoRoot 'rtl\mousetrap_voice_command.v') `
        (Join-Path $repoRoot 'sim\mousetrap_voice_io\tb_t80_voice_io_join.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit $LASTEXITCODE; see $runDir\vlog.log" }

    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_t80_voice_io_join `
        -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit $LASTEXITCODE; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS actual T80 voice I/O and RIOT callback join' | Select-Object -First 1
    if ($null -eq $pass) {
        throw "Simulation exited without its PASS marker; see $runDir\vsim.log"
    }
    # Deliberately restore the old raw-write callback interpretation. Its
    # reset/DDR callback assertion must fail, proving the join detects this specific defect.
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_t80_voice_io_join `
        -gBROKEN_RAW_CALLBACK=1 -do 'run -all; quit -f' *> negative-raw-callback.log
    $negative = Select-String -LiteralPath (Join-Path $runDir 'negative-raw-callback.log') `
        -Pattern 'RIOT reset callback missing|DDRA callback mismatch' | Select-Object -First 1
    if ($null -eq $negative) { throw "Raw-callback negative control did not fail at reset/DDR callback; see $runDir" }
    Write-Output 'PASS negative control: raw callback rejected at reset/DDR initialization'
    Write-Output $pass.Line.Trim()
    Write-Output "Logs: $runDir"
}
finally {
    Pop-Location
}
