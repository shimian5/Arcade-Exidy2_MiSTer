param([int]$Command = 17, [switch]$RawRegisters)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) {
        throw "Required ModelSim executable is missing: $(Join-Path $modelsimBin $tool)"
    }
}
$hexPath = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$manifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$hexLines = @(Get-Content -LiteralPath $hexPath)
if ($hexLines.Count -ne 16384) { throw "Expected 16,384 staged image bytes, found $($hexLines.Count) lines" }
$romBytes = [byte[]]::new($hexLines.Count)
for ($i = 0; $i -lt $hexLines.Count; $i++) {
    if ($hexLines[$i] -notmatch '^[0-9a-fA-F]{2}$') { throw "Invalid image byte at line $($i + 1)" }
    $romBytes[$i] = [Convert]::ToByte($hexLines[$i], 16)
}
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $actualHash = [Convert]::ToHexString($sha.ComputeHash($romBytes)).ToLowerInvariant() }
finally { $sha.Dispose() }
$expectedHash = $manifest.images.mtrap.sha256.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "Staged ROM payload SHA-256 mismatch: expected $expectedHash, got $actualHash" }
$runName = 'modelsim-firmware-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
$outputRoot = Join-Path $repoRoot 'simulation\mousetrap_firmware'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot $runName
$resolvedOutputRoot = (Resolve-Path $outputRoot).Path
New-Item -ItemType Directory -Path $runDir | Out-Null
if (-not $runDir.StartsWith($resolvedOutputRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Run directory escaped ignored simulation output: $runDir"
}

Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit $LASTEXITCODE" }

    # The actual register-file logic is unchanged. Match MAME's zeroed
    # constructor register banks in a generated simulation-only declaration.
    $registerSource = Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'
    $registerOriginalHash = (Get-FileHash -LiteralPath $registerSource -Algorithm SHA256).Hash
    if (-not $RawRegisters) {
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
    }
    [ordered]@{
        command = $Command
        rom_payload_sha256 = $actualHash
        register_source_sha256 = $registerOriginalHash
        compiled_register_sha256 = (Get-FileHash -LiteralPath $registerSource -Algorithm SHA256).Hash
        zero_initialized_register_banks = (-not $RawRegisters)
        scope = 'Simulation-only constructor assumption; no production CPU source changed'
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
        (Join-Path $repoRoot 'sim\mousetrap_speech\tb_t80_mtrap_decoder.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit $LASTEXITCODE; see $runDir\vlog.log" }

    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_t80_mtrap_decoder `
        ('+ROM=' + $hexPath.Replace('\','/')) `
        ('+IO_LOG=' + (Join-Path $runDir 'io.csv').Replace('\','/')) `
        ('+SAMPLE_LOG=' + (Join-Path $runDir 'samples.csv').Replace('\','/')) `
        ('+COMMAND=' + $Command) -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit $LASTEXITCODE; see $runDir\vsim.log" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') -SimpleMatch 'PASS actual Mouse Trap ROM + T80 + I/O + decoder' | Select-Object -First 1
    if ($null -eq $pass) {
        throw "Simulation exited without its PASS marker; see $runDir\vsim.log"
    }
    Write-Output $pass.Line.Trim()
    Write-Output "Logs: $runDir"
}
finally {
    Pop-Location
}
