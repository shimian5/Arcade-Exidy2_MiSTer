[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$romHex = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$romManifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$manifest = Get-Content -LiteralPath $romManifestPath -Raw | ConvertFrom-Json
$romBytes = [byte[]]::new(16384)
$hexLines = @(Get-Content -LiteralPath $romHex)
if ($hexLines.Count -ne $romBytes.Length) { throw "Expected 16,384 ROM bytes; got $($hexLines.Count)" }
for ($i = 0; $i -lt $hexLines.Count; $i++) { $romBytes[$i] = [Convert]::ToByte($hexLines[$i], 16) }
$romHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($romBytes)).ToLowerInvariant()
if ($romHash -ne $manifest.images.mtrap.sha256.ToLowerInvariant()) { throw 'Staged Mouse Trap ROM hash mismatch' }
foreach ($tool in @('vlib.exe','vcom.exe','vlog.exe','vsim.exe')) { if (-not (Test-Path (Join-Path $modelsimBin $tool))) { throw "Missing ModelSim executable $tool" } }
$outputRoot = Join-Path $repoRoot 'simulation\mousetrap_native_replay'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
$regSourceOriginal = Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'
$regText = Get-Content -LiteralPath $regSourceOriginal -Raw
foreach ($bank in @('RegsH','RegsL')) {
    $old = "signal $bank : Register_Image(0 to 7);"
    if ([regex]::Matches($regText,[regex]::Escape($old)).Count -ne 1) { throw "Source guard failed for $bank" }
    $regText = $regText.Replace($old,"signal $bank : Register_Image(0 to 7) := (others => (others => '0'));")
}
$regSource = Join-Path $runDir 'T80_Reg_boot.vhd'
[IO.File]::WriteAllText($regSource,$regText)
[ordered]@{
    scope = 'State-conditioned replay of captured native MAME R6532 PA callbacks through the command-interrupted busy-low endpoint; not a cold replay of the full game history'
    romPayloadSha256 = $romHash
    registerSourceSha256 = (Get-FileHash $regSourceOriginal -Algorithm SHA256).Hash
    compiledRegisterSha256 = (Get-FileHash $regSource -Algorithm SHA256).Hash
    callbackGroups = @('EF,F8,FF','EF,F8,FF','EF,F9,FF','EF,FB,FF')
    intervalsNs = @(131879,583315,215675516,132160,583314,980681339,167619,506209,14237661557,167619,503975)
    nativeCapture = 'simulation/mousetrap_voice_gameplay_postdelay_busy_tail_3600/bus.csv'
    nativeBusyLowTime = '53.763739180 s; follows new EF/FB/FF group, command-interrupted transition'
    noProductionSourcesModified = $true
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $runDir 'run-manifest.json') -Encoding utf8
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE) { throw "vlib failed; see $runDir\vlib.log" }
    $vhdl = @((Join-Path $repoRoot 'modules\cpu-t80\T80_Pack.vhd'),$regSource,(Join-Path $repoRoot 'modules\cpu-t80\T80_MCode.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80_ALU.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80se.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\Z80.vhd'))
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE) { throw "vcom failed; see $runDir\vcom.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -work work (Join-Path $repoRoot 'rtl\speech_rom_bus.v') (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') (Join-Path $repoRoot 'rtl\mc3417.v') (Join-Path $repoRoot 'rtl\mc3417_stream.v') (Join-Path $PSScriptRoot 'tb_mousetrap_native_tail.sv') *> vlog.log
    if ($LASTEXITCODE) { throw "vlog failed; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mousetrap_native_tail ("+ROM=" + $romHex.Replace('\','/')) ("+IO_LOG=" + (Join-Path $runDir 'io.csv').Replace('\','/')) ("+SAMPLE_LOG=" + (Join-Path $runDir 'samples.csv').Replace('\','/')) ("+PCM_LOG=" + (Join-Path $runDir 'pcm.csv').Replace('\','/')) ("+PA_LOG=" + (Join-Path $runDir 'pa.csv').Replace('\','/')) -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE) { throw "vsim failed; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS native PA tail replay' | Select-Object -First 1
    if ($null -eq $pass) { throw "Simulation lacked PASS marker; see $runDir\vsim.log" }
    Write-Output $pass.Line.Trim()
    Write-Output "Logs: $runDir"
} finally { Pop-Location }


