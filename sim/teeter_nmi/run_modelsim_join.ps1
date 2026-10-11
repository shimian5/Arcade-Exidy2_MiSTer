$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) {
        throw "Required ModelSim executable is missing: $(Join-Path $modelsimBin $tool)"
    }
}
$outputRoot = Join-Path $repoRoot 'simulation\harness\teeter_nmi'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('modelsim-join-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit $LASTEXITCODE" }
    $vhdl = @(
        (Join-Path $repoRoot 'modules\cpu-t65\T65_Pack.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t65\T65_ALU.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t65\T65_MCode.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t65\T65.vhd')
    )
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed with exit $LASTEXITCODE; see $runDir\vcom.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        (Join-Path $repoRoot 'rtl\teeter_nmi.v') `
        (Join-Path $repoRoot 'sim\teeter_nmi\tb_teeter_nmi_join.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit $LASTEXITCODE; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_teeter_nmi_join `
        -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit $LASTEXITCODE; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS actual Teeter NMI generator -> T65' | Select-Object -First 1
    if ($null -eq $pass) { throw "Simulation exited without its PASS marker; see $runDir\vsim.log" }
    Write-Output $pass.Line.Trim()
    Write-Output "Logs: $runDir"
}
finally {
    Pop-Location
}
