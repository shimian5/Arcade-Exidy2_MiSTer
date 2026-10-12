$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$rtl = Join-Path $repoRoot 'rtl\mc3417_stream.v'
if (-not (Test-Path -LiteralPath $rtl)) { throw "Renderer RTL not found: $rtl" }
$runRoot = Join-Path $repoRoot 'simulation\mc3417_stream'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$runDir = Join-Path $runRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        $rtl `
        (Join-Path $PSScriptRoot 'tb_mc3417_stream.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed; see $runDir" }

    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417_stream `
        -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed; see $runDir" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') `
        -SimpleMatch 'PASS mc3417_stream directed fixture' | Select-Object -First 1
    if ($null -eq $pass) { throw "Missing directed fixture PASS; see $runDir" }

    # Both mutations must trip a directed assertion. A one-tick ramp breaks
    # the interruption/partial-ramp checks; an early timeout breaks the
    # boundary check before the normal timeout sequence.
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417_stream `
        -gRAMP_TICKS=1 -do 'run -all; quit -f' *> negative-ramp.log
    $badRamp = Select-String -LiteralPath (Join-Path $runDir 'negative-ramp.log') `
        -SimpleMatch 'Fatal: zero quotient holds:' | Select-Object -First 1
    if ($null -eq $badRamp) { throw "RAMP_TICKS negative control did not fail; see $runDir" }

    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417_stream `
        -gIDLE_TICKS=20 -do 'run -all; quit -f' *> negative-timeout.log
    $badTimeout = Select-String -LiteralPath (Join-Path $runDir 'negative-timeout.log') `
        -SimpleMatch 'Fatal: not idle at exact age threshold:' | Select-Object -First 1
    if ($null -eq $badTimeout) { throw "IDLE_TICKS negative control did not fail; see $runDir" }

    Write-Output $pass.Line.Trim()
    Write-Output 'PASS negative controls: short ramp and early timeout rejected'
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
