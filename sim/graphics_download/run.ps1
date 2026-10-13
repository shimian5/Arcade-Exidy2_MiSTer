$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin='C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$runDir=Join-Path $repoRoot ('simulation\graphics_download\run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force $runDir | Out-Null
$core=Get-Content (Join-Path $repoRoot 'rtl/Exidy2.v') -Raw
$m=[regex]::Match($core,'eprom_1 U11D_gfx.*?\n\);',[Text.RegularExpressions.RegexOptions]::Singleline)
if(!$m.Success -or $m.Value -notmatch '\.CLK_DL\(~master_clock\)'){throw 'Production graphics download clock guard failed'}
$fragment=$m.Value.Replace('SPRITE_ADDR','read_addr')
[IO.File]::WriteAllText((Join-Path $runDir 'production_gfx_instance.vh'),$fragment)
# ModelSim's vendor VHDL RAM model crashes on the production blank init-file
# string. Use its documented no-file sentinel in this private simulation copy.
# All 2,048 locations are overwritten before checking; startup contents are untested.
$ram=Get-Content (Join-Path $repoRoot 'rtl/dpram_dc.vhd') -Raw
$ram=$ram.Replace('string := " ";','string := "UNUSED";')
[IO.File]::WriteAllText((Join-Path $runDir 'dpram_dc.vhd'),$ram)
Push-Location $runDir
try {
 & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
 & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work (Join-Path $runDir 'dpram_dc.vhd') *> vcom.log
 if($LASTEXITCODE){throw "vcom failed $runDir"}
 & (Join-Path $modelsimBin 'vlog.exe') -sv -work work ("+incdir+"+$runDir.Replace('\','/')) (Join-Path $repoRoot 'rtl/rom_loader.sv') (Join-Path $PSScriptRoot 'tb.sv') *> vlog.log
 if($LASTEXITCODE){throw "vlog failed $runDir"}
 & (Join-Path $modelsimBin 'vsim.exe') -c -L altera_mf -L altera_mf_ver -lib work work.tb_graphics_download -do 'run -all; quit -f' *> vsim.log
 if($LASTEXITCODE){throw "vsim failed $runDir"}
 $pass=Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch -Pattern 'PASS actual graphics RAM download/read' | Select-Object -First 1
 if(!$pass){throw "Graphics download did not pass: $runDir"}
 $pass.Line.Trim()
 & (Join-Path $modelsimBin 'vsim.exe') -c -L altera_mf -L altera_mf_ver -lib work work.tb_graphics_download +CORRUPT=1 -do 'run -all; quit -f' *> negative.log
 $negative=Get-Content (Join-Path $runDir 'negative.log') -Raw
 if($negative -notmatch 'graphics byte mismatch' -or $negative -match 'PASS actual graphics'){throw 'Wrong expected graphics byte was not rejected'}
 'PASS corrupt expected-byte negative control'
 $hashes=[ordered]@{}
 foreach($f in @('rtl/Exidy2.v','rtl/rom_loader.sv','rtl/dpram_dc.vhd','sim/graphics_download/tb.sv','sim/graphics_download/run.ps1')){$hashes[$f]=(Get-FileHash (Join-Path $repoRoot $f) -Algorithm SHA256).Hash}
 [ordered]@{checks=4096;sourceSha256=$hashes;negative='wrong expected byte rejected';limits='Actual vendor RAM model; simulation-only no-file sentinel replaces blank init-file string. All bytes overwritten; no startup-state, sprite scheduling or hardware acceptance.'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath source-audit.json -Encoding utf8
 "Logs: $runDir"
} finally {Pop-Location}
