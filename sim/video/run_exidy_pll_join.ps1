$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin='C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$runDir=Join-Path $repoRoot ('simulation\exidy_pll_join\run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force $runDir | Out-Null
Push-Location $runDir
try {
 & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
 if($LASTEXITCODE){throw 'vlib failed'}
 $files=@('rtl/pll/pll_0002.v','candidates/video/exidy_output_pll.sv','candidates/video/exidy_output_control.sv','sys/pll_cfg/pll_cfg.v','sys/pll_cfg/altera_pll_reconfig_top.v','sys/pll_cfg/altera_pll_reconfig_core.v','sim/video/tb_exidy_pll_join.sv') | ForEach-Object {Join-Path $repoRoot $_}
 & (Join-Path $modelsimBin 'vlog.exe') -sv -work work @files *> vlog.log
 if($LASTEXITCODE){throw "vlog failed: $runDir\vlog.log"}
 & (Join-Path $modelsimBin 'vsim.exe') -c -L altera_lnsim_ver -L altera_mf_ver -L cyclonev_ver -lib work work.tb_exidy_pll_join -do 'run -all; quit -f' *> vsim.log
 if($LASTEXITCODE){throw "vsim failed: $runDir\vsim.log"}
 $pass=Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS actual PLL configuration join' | Select-Object -First 1
 if($null -eq $pass){throw "PLL join did not pass: $runDir\vsim.log"}
 $pass.Line.Trim()
 $hashes=[ordered]@{}
 foreach($f in @('rtl/pll/pll_0002.v','candidates/video/exidy_output_pll.sv','candidates/video/exidy_output_control.sv','sys/pll_cfg/pll_cfg.v','sys/pll_cfg/altera_pll_reconfig_top.v','sys/pll_cfg/altera_pll_reconfig_core.v','sim/video/tb_exidy_pll_join.sv')){$hashes[$f]=(Get-FileHash (Join-Path $repoRoot $f) -Algorithm SHA256).Hash}
 [ordered]@{sourceSha256=$hashes;result=$pass.Line.Trim();limits='Vendor model internal periods quantize. This checks configuration handshake, source stability, modelled ratios and reset retention, not physical lock/jitter or complete output video.'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath source-audit.json -Encoding utf8
 "Logs: $runDir"
} finally {Pop-Location}
