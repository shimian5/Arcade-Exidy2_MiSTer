$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mraPath = Join-Path $repoRoot 'candidates\mra\Mouse Trap (speech expansion candidate).mra'
$romPath = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$manifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$romManifestPath = Join-Path $repoRoot 'docs\baseline\roms\availability-manifest.json'
$runName = 'run-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-ffff')
$outputRoot = Join-Path $repoRoot 'simulation\speech_loader'
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$runPath = Join-Path $outputRoot $runName
New-Item -ItemType Directory -Path $runPath | Out-Null

# Read the candidate MRA itself. The fixture must use the committed descriptor,
# not a copied byte literal that could silently drift.
$mra = [System.Xml.XmlDocument]::new()
$mra.Load($mraPath)
$descText = $mra.SelectSingleNode("/misterromdescription/rom[@index='7']/part").InnerText
$descriptor = @($descText -split '\s+' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
if ($descriptor.Count -ne 16) { throw "MRA index-7 descriptor has $($descriptor.Count) bytes, expected 16" }
$baseLength = [int]$descriptor[5] + ([int]$descriptor[6] -shl 8) + ([int]$descriptor[7] -shl 16)
if ($baseLength -ne 0x14940) { throw "MRA descriptor base length is 0x$($baseLength.ToString('X')); expected emitted index-0 length 0x14940" }
$descMem = Join-Path $runPath 'descriptor.mem'
Set-Content -LiteralPath $descMem -Value ($descriptor | ForEach-Object { $_.ToString('x2') }) -Encoding ascii
$xmlOrder = @($mra.SelectNodes('/misterromdescription/rom') | ForEach-Object { [int]$_.GetAttribute('index') })
if (($xmlOrder -join ',') -ne '1,7,0,6,2,3') {
    throw "Candidate MRA ROM XML order must be 1,7,0,6,2,3; found $($xmlOrder -join ',')"
}
$orderMem = Join-Path $runPath 'mra-order.mem'
Set-Content -LiteralPath $orderMem -Value ($xmlOrder | ForEach-Object { $_.ToString('x2') }) -Encoding ascii

# Verify and read only the private ROM image's hex file; do not copy its bytes
# into committed files or print its contents.
$hexLines = @(Get-Content -LiteralPath $romPath)
if ($hexLines.Count -ne 16384) { throw "Expected 16,384 private image bytes, found $($hexLines.Count)" }
$romBytes = [byte[]]::new($hexLines.Count)
for ($i = 0; $i -lt $hexLines.Count; $i++) {
    if ($hexLines[$i] -notmatch '^[0-9a-fA-F]{2}$') { throw "Invalid private image byte at line $($i + 1)" }
    $romBytes[$i] = [Convert]::ToByte($hexLines[$i], 16)
}
$imageManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($romBytes))).Replace('-', '').ToLowerInvariant() }
finally { $sha.Dispose() }
if ($actualHash -ne $imageManifest.images.mtrap.sha256.ToLowerInvariant()) { throw 'Private Mouse Trap image hash does not match the reviewed ROM manifest' }

# Confirm MRA index-0 and index-6 stream sizes against the reviewed MAME set.
$romManifest = Get-Content -LiteralPath $romManifestPath -Raw | ConvertFrom-Json
$mtrap = $romManifest.sets | Where-Object set -eq 'mtrap'
$baseSize = 0
foreach ($part in $mra.SelectNodes("/misterromdescription/rom[@index='0']/part")) {
    if ($part.HasAttribute('repeat')) {
        $baseSize += [Convert]::ToInt32($part.GetAttribute('repeat').Substring(2), 16)
    } else {
        $rom = $mtrap.roms | Where-Object crc -eq $part.GetAttribute('crc')
        if (!$rom) { throw "MRA index-0 ROM CRC $($part.GetAttribute('crc')) is absent from the reviewed MAME manifest" }
        $baseSize += [int]$rom.size
    }
}
$speechSize = 0
foreach ($part in $mra.SelectNodes("/misterromdescription/rom[@index='6']/part")) {
    $rom = $mtrap.roms | Where-Object crc -eq $part.GetAttribute('crc')
    if (!$rom) { throw "MRA index-6 ROM CRC $($part.GetAttribute('crc')) is absent from the reviewed MAME manifest" }
    $speechSize += [int]$rom.size
}
if ($baseSize -ne $baseLength) { throw "MRA index-0 emits $baseSize bytes but descriptor declares $baseLength" }
if ($speechSize -ne 16384) { throw "MRA index-6 emits $speechSize bytes, expected 16,384" }

$drive = $repoRoot.Substring(0, 1).ToLowerInvariant()
$linuxRepo = "/mnt/$drive" + $repoRoot.Substring(2).Replace('\', '/')
$linuxRun = "$linuxRepo/simulation/speech_loader/$runName"
$compileAndRun = @"
set -euo pipefail
cd '$linuxRun'
verilator --binary --timing --assert -Wno-fatal --top-module tb_speech_loader -Mdir obj \
  '$linuxRepo/rtl/speech_loader.sv' \
  '$linuxRepo/rtl/expansion/exidy_reset_sync.sv' \
  '$linuxRepo/rtl/expansion/exidy_transport_adapter.sv' \
  '$linuxRepo/rtl/expansion/exidy_expansion_loader_rr.sv' \
  '$linuxRepo/rtl/expansion/exidy_expansion_bridge_rr.sv' \
  '$linuxRepo/sim/speech_loader/tb_speech_loader.sv' > compile.log 2>&1
./obj/Vtb_speech_loader +DESC='$linuxRun/descriptor.mem' +ORDER='$linuxRun/mra-order.mem' +ORDER_COUNT=$($xmlOrder.Count) +ROM='/mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer/simulation/expansion_adapter/rom-images/mtrap.hex' > run.log 2>&1
cat run.log
"@
& wsl.exe -d archlinux -- bash -lc $compileAndRun
if ($LASTEXITCODE -ne 0) {
    if (Test-Path -LiteralPath (Join-Path $runPath 'run.log')) {
        Get-Content -LiteralPath (Join-Path $runPath 'run.log') | Select-Object -Last 40
    } else {
        Get-Content -LiteralPath (Join-Path $runPath 'compile.log') -ErrorAction SilentlyContinue | Select-Object -Last 40
    }
    throw "speech_loader Verilator fixture failed with exit code $LASTEXITCODE (details: $runPath)"
}
Write-Output "PASS MRA profile, private ROM image, and production speech loader wrapper. Logs: $runPath"
