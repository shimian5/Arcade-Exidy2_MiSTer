$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) { throw "Missing ModelSim executable: $tool" }
}
$outputRoot = Join-Path $repoRoot 'simulation\mousetrap_speech'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$resolvedOutputRoot = (Resolve-Path $outputRoot).Path
$runDir = Join-Path $outputRoot ('modelsim-bridge-reset-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
if (-not $runDir.StartsWith($resolvedOutputRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Run directory escaped ignored output: $runDir" }
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed; see $runDir\vlib.log" }
    $vhdl = @('T80_Pack.vhd','T80_Reg.vhd','T80_MCode.vhd','T80_ALU.vhd','T80.vhd','T80se.vhd','Z80.vhd') | ForEach-Object { Join-Path $repoRoot "modules\cpu-t80\$_" }
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed; see $runDir\vcom.log" }
    $loaderText = (Get-Content -Raw (Join-Path $repoRoot 'sim\expansion_adapter\exidy_expansion_loader_ram.sv')) -replace "`r`n", "`n"
    $oldPort = "    input  logic        reset_n,`n"
    $newPort = "    input  logic        reset_n,`n    input  logic        cvsd_reset_n,`n"
    $oldReset = "always_ff @(posedge cvsd_clk or negedge reset_n) begin`n        if (!reset_n) begin"
    $newReset = "always_ff @(posedge cvsd_clk or negedge cvsd_reset_n) begin`n        if (!cvsd_reset_n) begin"
    if (($loaderText.Split($oldPort).Length - 1) -ne 1 -or ($loaderText.Split($oldReset).Length - 1) -ne 1) { throw 'Unexpected loader source; reset-sync derivation anchors changed' }
    $loaderText = $loaderText.Replace($oldPort,$newPort).Replace($oldReset,$newReset)
    $derivedLoader = Join-Path $runDir 'exidy_expansion_loader_rr.sv'
    Set-Content -LiteralPath $derivedLoader -Value $loaderText -NoNewline
    & (Join-Path $modelsimBin 'vlog.exe') -sv -work work `
        (Join-Path $repoRoot 'rtl\speech_rom_bus.v') `
        (Join-Path $repoRoot 'sim\expansion_adapter\exidy_reset_sync.sv') `
        (Join-Path $repoRoot 'sim\expansion_adapter\exidy_transport_adapter.sv') `
        $derivedLoader `
        (Join-Path $repoRoot 'sim\expansion_adapter\exidy_expansion_bridge_rr.sv') `
        (Join-Path $repoRoot 'sim\mousetrap_speech\tb_t80_speech_bridge_reset.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_t80_speech_bridge_reset -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS accepted in-flight reset and post-reset data c3' | Select-Object -First 1
    $ackPass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS unsampled request aborted across stopped-domain reset' | Select-Object -First 1
    if ($null -eq $pass -or $null -eq $ackPass) { throw "PASS marker missing; see $runDir\vsim.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -sv -work work `
        (Join-Path $repoRoot 'sim\expansion_adapter\tb_bridge_reset.sv') *> vlog-bridge-reset.log
    if ($LASTEXITCODE -ne 0) { throw "bridge reset vlog failed; see $runDir\vlog-bridge-reset.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_bridge_reset -do 'run -all; quit -f' *> vsim-bridge-reset.log
    if ($LASTEXITCODE -ne 0) { throw "bridge reset vsim failed; see $runDir\vsim-bridge-reset.log" }
    $bridgePass = Select-String -LiteralPath (Join-Path $runDir 'vsim-bridge-reset.log') -SimpleMatch 'PASS bridge reset adversaries' | Select-Object -First 1
    if ($null -eq $bridgePass) { throw "Bridge reset PASS marker missing; see $runDir\vsim-bridge-reset.log" }
    Write-Output $pass.Line.Trim()
    Write-Output $ackPass.Line.Trim()
    Write-Output $bridgePass.Line.Trim()
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
