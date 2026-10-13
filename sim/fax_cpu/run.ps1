$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$corePath = Join-Path $repoRoot 'rtl\Exidy2.v'
$systemTopPath = Join-Path $repoRoot 'Arcade-Exidy2.sv'
$core = Get-Content -LiteralPath $corePath -Raw
$systemTop = Get-Content -LiteralPath $systemTopPath -Raw

function Require-Pattern([string]$Text,[string]$Pattern,[string]$Label) {
    if (-not [regex]::IsMatch($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw "Production source guard failed: $Label"
    }
}

Require-Pattern $core 'assign\s+RAMSEL\s*=\s*fax_enabled\s*\?\s*\(CPU_addrbus\[15:11\]\s*!=\s*5''d0\)\s*:\s*\(CPU_addrbus\[15:10\]\s*!=\s*6''d0\)' 'FAX 2 KiB / legacy 1 KiB RAM decode'
Require-Pattern $core '\.address_a\(fax_enabled\s*\?\s*CPU_addrbus\[10:0\]\s*:\s*\{1''b0,CPU_addrbus\[9:0\]\}\)' 'independent expanded RAM address bit'
Require-Pattern $core '\.address_b\(fax_enabled\s*\?\s*hs_address\[10:0\]\s*:\s*\{1''b0,hs_address\[9:0\]\}\)' 'host RAM address follows selected profile'
Require-Pattern $core '\.wren_a\(!CPU_RWn\s*&\s*!RAMSEL\)' 'CPU work RAM write decode'
Require-Pattern $core '\.cpu_write\(PH_1\s*&&\s*!CPU_RWn\)' 'question-bank write is PH_1 qualified'
Require-Pattern $core 'CPU_databus_in\s*<=\s*fax_controls_selected\s*\?\s*fax_input_byte\s*:\s*fax_question_selected\s*\?\s*fax_question_data\s*:\s*\(!RAMSEL.*?\(!ROMSEL' 'FAX controls and question data precede ordinary memory mux'
Require-Pattern $core 'faxProfileControls\s*#\(\.STARTUP_CHECK\(1''b0\)\)' 'production startup-check default'
Require-Pattern $core '\.p1_answer_pressed\(\{!m_blu,!m_red,!m_yel,!m_fire\}\)' 'P1 answer controls'
Require-Pattern $core '\.p2_answer_pressed\(fax_p2_answers\)' 'P2 answer controls'
Require-Pattern $core 'fax_startup_check,fax_controls_data\[1:0\]' 'IN3 bit 2 input'
Require-Pattern $systemTop '8''hF4:\s*mod_other\s*<=\s*8''h74;\s*8''hF8:\s*mod_other\s*<=\s*8''h78;' 'marker normalization before profile decode'
Require-Pattern $systemTop '\.fax_p2_answers\(joystick_1\[7:4\]\).*?\.fax_p2_start_pressed\(joystick_1\[8\]\).*?\.fax_startup_check\(status\[23\]\)' 'top-level P2/start/startup bindings'

$tools = @('vlib.exe','vcom.exe','vlog.exe','vsim.exe')
foreach ($tool in $tools) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) { throw "Missing ModelSim executable: $tool" }
}
$outputRoot = Join-Path $repoRoot 'simulation\fax_cpu'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
$faxInputMatch = [regex]::Match($core,'wire\s+\[7:0\]\s+fax_input_byte\s*=.*?;',[Text.RegularExpressions.RegexOptions]::Singleline)
$muxMatch = [regex]::Match($core,'always\s*@\(posedge\s+master_clock\)\s*begin\s*CPU_databus_in\s*<=.*?\n\s*end',[Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $faxInputMatch.Success -or -not $muxMatch.Success) { throw 'Cannot extract the production FAX read mux from rtl/Exidy2.v' }
$extractedMuxPath = Join-Path $runDir 'production_fax_read_mux.vh'
[IO.File]::WriteAllText($extractedMuxPath,$faxInputMatch.Value + "`r`n" + $muxMatch.Value + "`r`n")
$audit = [ordered]@{
    fixture = 'Actual T65 6502 executes synthetic ROM bytecode through a source-guarded FAX memory/input harness.'
    sourceGuards = @('Exidy2 RAMSEL widths','11-bit CPU and host RAM addresses','PH_1 bank write qualifier','FAX control/question mux priority','P1/P2/startup bindings','top marker normalization')
    t65Sources = @('modules/cpu-t65/T65_Pack.vhd','T65_ALU.vhd','T65_MCode.vhd','T65.vhd')
    extractedProductionMux = 'fax_input_byte and complete CPU_databus_in priority mux, extracted verbatim from rtl/Exidy2.v into the test harness.'
    extractedMuxSha256 = (Get-FileHash $extractedMuxPath -Algorithm SHA256).Hash
    rom = 'Synthetic 6502 bytecode assembled in the testbench; no copyrighted game ROMs used.'
    topLevelAndQuartus = 'Not instantiated or built; this fixture checks the shared Exidy2 CPU-side contracts.'
    sourceSha256 = [ordered]@{
        'rtl/Exidy2.v' = (Get-FileHash $corePath -Algorithm SHA256).Hash
        'Arcade-Exidy2.sv' = (Get-FileHash $systemTopPath -Algorithm SHA256).Hash
        'rtl/fax_controls.v' = (Get-FileHash (Join-Path $repoRoot 'rtl\fax_controls.v') -Algorithm SHA256).Hash
        'rtl/fax_profile_controls.v' = (Get-FileHash (Join-Path $repoRoot 'rtl\fax_profile_controls.v') -Algorithm SHA256).Hash
        'rtl/fax_question_window.v' = (Get-FileHash (Join-Path $repoRoot 'rtl\fax_question_window.v') -Algorithm SHA256).Hash
    }
}
$audit | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'source-audit.json') -Encoding utf8

Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE) { throw "vlib failed; see $runDir\vlib.log" }
    $cpu = Join-Path $repoRoot 'modules\cpu-t65'
    $vhdl = @((Join-Path $cpu 'T65_Pack.vhd'),(Join-Path $cpu 'T65_ALU.vhd'),(Join-Path $cpu 'T65_MCode.vhd'),(Join-Path $cpu 'T65.vhd'))
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE) { throw "vcom failed; see $runDir\vcom.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -sv -work work ("+incdir+" + $runDir.Replace('\','/')) `
        (Join-Path $repoRoot 'rtl\fax_controls.v') `
        (Join-Path $repoRoot 'rtl\fax_profile_controls.v') `
        (Join-Path $repoRoot 'rtl\fax_question_window.v') `
        (Join-Path $PSScriptRoot 'fax_t65_harness.sv') `
        (Join-Path $PSScriptRoot 'tb_fax_t65.sv') *> vlog.log
    if ($LASTEXITCODE) { throw "vlog failed; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_fax_t65 -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE) { throw "vsim failed; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS actual T65 bytecode' | Select-Object -First 1
    if ($null -eq $pass) { throw "Simulation did not report PASS; see $runDir\vsim.log" }
    Write-Output $pass.Line.Trim()
    Write-Output "Logs and source audit: $runDir"
} finally { Pop-Location }
