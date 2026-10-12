$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
& python (Join-Path $repoRoot 'tools\mc3417\prepare_reference.py')
if ($LASTEXITCODE -ne 0) { throw 'Reference preparation failed' }
$referenceRoot = Join-Path $repoRoot 'simulation\mc3417'
$linuxReference = '/mnt/' + $referenceRoot.Substring(0,1).ToLower() + '/' + $referenceRoot.Substring(3).Replace('\','/')
$compileCommand = "g++ -std=c++17 -O2 '$linuxReference/oracle.cpp' -o '$linuxReference/oracle' && '$linuxReference/oracle' '$linuxReference/stimulus.txt' '$linuxReference/reference.txt'"
& wsl -d archlinux -- bash -lc $compileCommand
if ($LASTEXITCODE -ne 0) { throw 'Pinned-method C++ oracle failed' }
$runDir = Join-Path $referenceRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        (Join-Path $repoRoot 'rtl\mc3417.v') `
        (Join-Path $repoRoot 'sim\mc3417\tb_mc3417.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed; see $runDir" }
    $referenceArgument = '+REFERENCE=' + (Join-Path $referenceRoot 'reference.txt').Replace('\','/')
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417 `
        $referenceArgument -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed; see $runDir" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS MC3417 pinned-method comparison' | Select-Object -First 1
    if ($null -eq $pass) { throw "Missing decoder PASS; see $runDir" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417 `
        -gWRONG_EDGE=1 $referenceArgument -do 'run -all; quit -f' *> negative-rising-edge.log
    $negative = Select-String -LiteralPath (Join-Path $runDir 'negative-rising-edge.log') -SimpleMatch 'reference history mismatch' | Select-Object -First 1
    if ($null -eq $negative) { throw "Rising-edge negative control did not fail; see $runDir" }
    Write-Output $pass.Line.Trim()
    Write-Output 'PASS negative control: rising-edge decoder rejected'
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
