$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    $toolPath = Join-Path $modelsimBin $tool
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "Required ModelSim executable is missing: $toolPath" }
}

$hexPath = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$manifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$hexLines = @(Get-Content -LiteralPath $hexPath)
if ($hexLines.Count -ne 16384) { throw "Expected 16,384 staged image bytes, found $($hexLines.Count) lines" }
$romBytes = [byte[]]::new($hexLines.Count)
for ($n = 0; $n -lt $hexLines.Count; $n++) {
    if ($hexLines[$n] -notmatch '^[0-9a-fA-F]{2}$') { throw "Invalid image byte at line $($n + 1)" }
    $romBytes[$n] = [Convert]::ToByte($hexLines[$n], 16)
}
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $romHash = [Convert]::ToHexString($sha.ComputeHash($romBytes)).ToLowerInvariant() }
finally { $sha.Dispose() }
if ($romHash -ne $manifest.images.mtrap.sha256.ToLowerInvariant()) {
    throw "Staged Mouse Trap payload hash mismatch: $romHash"
}

$outputRoot = Join-Path $repoRoot 'simulation\mousetrap_subsystem'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('modelsim-subsystem-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$resolvedOutputRoot = (Resolve-Path $outputRoot).Path
New-Item -ItemType Directory -Path $runDir | Out-Null
if (-not $runDir.StartsWith($resolvedOutputRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Run directory escaped ignored simulation output: $runDir"
}

Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit $LASTEXITCODE; see $runDir\vlib.log" }

    $registerSource = Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'
    $registerOriginalHash = (Get-FileHash -LiteralPath $registerSource -Algorithm SHA256).Hash
    $registerText = Get-Content -LiteralPath $registerSource -Raw
    foreach ($bank in @('RegsH', 'RegsL')) {
        $original = "signal $bank : Register_Image(0 to 7);"
        if ([regex]::Matches($registerText, [regex]::Escape($original)).Count -ne 1) {
            throw "Register initialization source guard failed for $bank"
        }
        $registerText = $registerText.Replace($original, "signal $bank : Register_Image(0 to 7) := (others => (others => '0'));")
    }
    $registerSource = Join-Path $runDir 'T80_Reg_boot.vhd'
    [System.IO.File]::WriteAllText($registerSource, $registerText)
    [ordered]@{
        rom_payload_sha256 = $romHash
        register_source_sha256 = $registerOriginalHash
        compiled_register_sha256 = (Get-FileHash -LiteralPath $registerSource -Algorithm SHA256).Hash
        zero_initialized_register_banks = $true
        master_clock_hz = 14366883
        rom_response_latency_audio_clocks = '3..11 deterministic varying'
        scope = 'Simulation-only register constructor assumption and ROM backend'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'run-manifest.json') -Encoding utf8

    $vhdl = @(
        (Join-Path $repoRoot 'modules\cpu-t80\T80_Pack.vhd'),
        $registerSource,
        (Join-Path $repoRoot 'modules\cpu-t80\T80_MCode.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80_ALU.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\T80se.vhd'),
        (Join-Path $repoRoot 'modules\cpu-t80\Z80.vhd')
    )
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed with exit $LASTEXITCODE; see $runDir\vcom.log" }
    & (Join-Path $modelsimBin 'vlog.exe') -work work `
        (Join-Path $repoRoot 'rtl\speech_rom_bus.v') `
        (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') `
        (Join-Path $repoRoot 'rtl\mc3417.v') `
        (Join-Path $repoRoot 'rtl\mc3417_stream.v') `
        (Join-Path $repoRoot 'rtl\exidy_biquad.v') `
        (Join-Path $repoRoot 'rtl\mc3417_filter.v') `
        (Join-Path $repoRoot 'rtl\mousetrap_speech.v') `
        (Join-Path $PSScriptRoot 'tb_mousetrap_subsystem.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit $LASTEXITCODE; see $runDir\vlog.log" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mousetrap_subsystem `
        ('+ROM=' + $hexPath.Replace('\','/')) -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit $LASTEXITCODE; see $runDir\vsim.log" }
    foreach ($marker in @('PASS ordered digits=', 'PASS wrapper firmware', 'PASS phase clocks pause/global-reset hold')) {
        $found = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch $marker | Select-Object -First 1
        if ($null -eq $found) { throw "Missing acceptance marker '$marker'; see $runDir\vsim.log" }
        Write-Output $found.Line.Trim()
    }
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
