$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
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
$runName = 'mousetrap_t80_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss_ffff')
$runPath = Join-Path $repoRoot "simulation\$runName"
New-Item -ItemType Directory -Path $runPath | Out-Null

$drive = $repoRoot.Substring(0, 1).ToLowerInvariant()
$rootWsl = "/mnt/$drive" + $repoRoot.Substring(2).Replace('\', '/')
$cmd = @"
set -e
cd '$rootWsl/simulation/$runName'
export LD_LIBRARY_PATH=/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib
/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -a --std=08 -fsynopsys -frelaxed ../../modules/cpu-t80/T80_Pack.vhd ../../modules/cpu-t80/T80_Reg.vhd ../../modules/cpu-t80/T80_MCode.vhd ../../modules/cpu-t80/T80_ALU.vhd ../../modules/cpu-t80/T80.vhd ../../modules/cpu-t80/T80se.vhd ../../modules/cpu-t80/Z80.vhd ../../sim/mousetrap_speech/tb_t80_mtrap_rom.vhd
/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -e --std=08 -fsynopsys -frelaxed tb_t80_mtrap_rom
/mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl -r --std=08 -fsynopsys -frelaxed tb_t80_mtrap_rom --assert-level=error --stop-time=20us > mtrap-run.log 2>&1
grep -q 'PASS actual T80 initial fetch' mtrap-run.log
"@
& wsl.exe -d archlinux -- bash -lc $cmd
if ($LASTEXITCODE -ne 0) { throw "GHDL actual-ROM fixture failed with exit code $LASTEXITCODE" }
Write-Output "PASS actual T80 initial-ROM boundary; verified private image; logs: $runPath"
