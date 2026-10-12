$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) {
        throw "Required ModelSim executable is missing: $(Join-Path $modelsimBin $tool)"
    }
}

# Keep the proven timing/pin fixture tied to production. If production wiring
# or the mirrored bench changes its event, reset, PA or PB0 contract, stop
# before compiling and require the source and fixture to be reviewed together.
function Assert-SourcePattern([string]$Path, [string]$Pattern, [string]$Contract) {
    $source = Get-Content -LiteralPath $Path -Raw
    if (-not [regex]::IsMatch($source, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw "Production/fixture source guard failed for $Contract in $Path"
    }
}
$audioBoard = Join-Path $repoRoot 'rtl\audio_board.v'
$coreTop = Join-Path $repoRoot 'rtl\Exidy2.v'
$systemTop = Join-Path $repoRoot 'Arcade-Exidy2.sv'
$callbackHelper = Join-Path $repoRoot 'rtl\mousetrap_voice_command.v'
$speechSubsystem = Join-Path $repoRoot 'rtl\mousetrap_speech.v'
$bench = Join-Path $repoRoot 'sim\mousetrap_riot_join\tb_mousetrap_riot_join.sv'
Assert-SourcePattern $audioBoard 'auPH0\s*<=\s*cencnt_au\[3:0\]\s*==\s*4''d0' 'registered auPH0 generation'
Assert-SourcePattern $audioBoard 'T65\s+A6502\s*\(.*?\.enable\(auPH0\).*?\.clk\(audio_clk\)' 'T65 enable and parent-clock relationship'
Assert-SourcePattern $audioBoard '\.phi2\(auPH0\).*?\.rw_n\(audio_nWRITE\).*?\.cs\(!io08_0F\).*?\.add\(audio_addrbus\[4:0\]\).*?\.din\(audio_databus_out\)' 'actual RIOT bus and clock pins'
Assert-SourcePattern $audioBoard '\.accepted_write\(\(cencnt_au\s*==\s*4''d0\)\s*&&\s*!auPH0\s*&&\s*!io08_0F\s*&&\s*!audio_nWRITE\)' 'production accepted-write prediction'
Assert-SourcePattern $audioBoard '\.clk\(audio_clk\),\s*\.reset_n\(RESET_n_au\).*?\.address\(audio_addrbus\[4:0\]\),\s*\.data\(audio_databus_out\)' 'callback clock/reset/data binding'
Assert-SourcePattern $callbackHelper 'accepted_write\s*&&\s*!address\[2\]\s*&&\s*!address\[1\].*?command_data\s*<=\s*\(data\s*&\s*ddra\)\s*\|\s*~ddra.*?command_data\s*<=\s*\(ora\s*&\s*data\)\s*\|\s*~data' 'PA mirror decode and callback pull-up formula'
Assert-SourcePattern $audioBoard '\.pa_in\(8''hff\).*?\.pb_in\(\{7''h7f,\s*speech_enable\s*\?\s*speech_busy\s*:\s*1''b1\}\)' 'RIOT PA pull-up and PB0 input binding'
Assert-SourcePattern $audioBoard 'mousetrapSpeechSubsystem\s+speech\s*\(.*?\.clk\(audio_clk\).*?\.state_reset_n\(RESET_n_au\).*?\.decoder_reset_n\(RESET_n_au\).*?\.global_reset\(!RESET_n_au\).*?\.pause\(pause_au\).*?\.speech_enable\(speech_enable\),\s*\.image_ready\(speech_enable\).*?\.command_commit\(command_commit\).*?\.rom_read\(speech_read\).*?\.rom_ready\(speech_valid\).*?\.rom_data\(speech_data\).*?\.busyPB0\(speech_busy\)' 'speech subsystem clock/reset/readiness/ROM/PB0 binding'
Assert-SourcePattern $audioBoard 'assign\s+audio_l\s*=\s*speech_mono\s*;\s*assign\s+audio_r\s*=\s*speech_mono\s*;' 'speech audio output binding'
Assert-SourcePattern $speechSubsystem '\.riot_pb0_in\(riot_pb0_in\)' 'speech PB0 state connection'
Assert-SourcePattern $speechSubsystem 'assign\s+busyPB0\s*=\s*riot_pb0_in\s*;' 'speech PB0 state source'
Assert-SourcePattern $coreTop 'input\s+speech_enable\s*,\s*output\s+speech_read\s*,\s*output\s+\[13:0\]\s+speech_addr\s*,\s*input\s+speech_valid\s*,\s*input\s+\[7:0\]\s+speech_data' 'core top speech ports'
Assert-SourcePattern $coreTop 'exidyAB\s+sound_board\s*\(\s*\.speech_enable\(speech_enable\).*?\.speech_read\(speech_read\).*?\.speech_addr\(speech_addr\).*?\.speech_valid\(speech_valid\).*?\.speech_data\(speech_data\)' 'core/audio-board speech port join'
Assert-SourcePattern $systemTop 'exidySpeechLoader\s+speech_loader\s*\(\s*\.clk\(clk_sys\),\s*\.audio_clk\(clk_audio\),\s*\.reset_n\(!RESET\).*?\.speech_read\(speech_read\),\s*\.speech_addr\(speech_addr\).*?\.speech_valid\(speech_valid\),\s*\.speech_enable\(speech_enable\)' 'loader main/audio clocks and read port join'
Assert-SourcePattern $systemTop 'wire\s+reset\s*=\s*\(RESET\s*\|\s*status\[0\]\s*\|\s*buttons\[1\]\s*\|\s*ioctl_download\s*\|\s*loader_hold\)' 'loader reset hold in core reset'
Assert-SourcePattern $systemTop 'exidy2\s+ex2\s*\(.*?\.speech_enable\(speech_enable\).*?\.speech_read\(speech_read\).*?\.speech_addr\(speech_addr\).*?\.speech_valid\(speech_valid\).*?\.speech_data\(speech_data\)' 'system/core speech port join'
Assert-SourcePattern $bench 'wire\s+predicted_write\s*=\s*\(cencnt_au\s*==\s*4''d0\)\s*&&\s*!auPH0\s*&&\s*!io08_0F\s*&&\s*!audio_nWRITE\s*;' 'bench accepted-write prediction'
Assert-SourcePattern $bench 'R6532\s+riot\s*\(\.phi2\(auPH0\).*?\.pa_in\(8''hff\).*?\.pb_in\(\{7''h7f,\s*pb0\}\)' 'bench RIOT PA/PB binding'
Write-Output 'PASS production source guards: auPH0 prediction, RIOT bus, reset, PA/PB0, audio and top-level ROM binding'

$outputRoot = Join-Path $repoRoot 'simulation\harness\mousetrap_riot_join'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit $LASTEXITCODE" }
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work `
        (Join-Path $repoRoot 'modules\riot\R6532.vhd') *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed with exit $LASTEXITCODE; see $runDir\vcom.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        (Join-Path $repoRoot 'rtl\mousetrap_voice_command.v') `
        (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') `
        (Join-Path $repoRoot 'sim\mousetrap_riot_join\tb_mousetrap_riot_join.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit $LASTEXITCODE; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mousetrap_riot_join `
        -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit $LASTEXITCODE; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') `
        -SimpleMatch 'PASS registered auPH0 RIOT join' | Select-Object -First 1
    if ($null -eq $pass) { throw "Simulation exited without its PASS marker; see $runDir\vsim.log" }
    Write-Output $pass.Line.Trim()
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
