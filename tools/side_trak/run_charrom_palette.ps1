param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = Join-Path $repoRoot 'simulation/side_trak/roms'
$zip = Join-Path $romRoot 'sidetrac.zip'
$outDir = Join-Path $repoRoot "simulation/side_trak/character_path/$Run"
if (-not (Test-Path -LiteralPath $zip)) { throw "Verified Side Trak archive not staged: $zip" }
if (Test-Path -LiteralPath $outDir) { throw "Output already exists at $outDir; choose a fresh Run." }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dump_mame_char_region.lua') -Destination (Join-Path $outDir 'dump_mame_char_region.lua')
@('cfg','nvram','input','sta','diff','comment','home') | ForEach-Object { New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null }

$oldLocation = Get-Location
try {
    Set-Location $outDir
    & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms sidetrac *> 'verifyroms.log'
    if ($LASTEXITCODE -ne 0 -or (Get-Content 'verifyroms.log' -Raw) -notmatch 'romset sidetrac is good') {
        throw 'MAME 0.288 Side Trak ROM verification failed.'
    }
    $mameArgs = @(
        'sidetrac', '-noreadconfig', '-nowriteconfig', '-skip_gameinfo', '-rompath', $romRoot,
        '-cfg_directory', (Join-Path $outDir 'cfg'), '-nvram_directory', (Join-Path $outDir 'nvram'),
        '-input_directory', (Join-Path $outDir 'input'), '-state_directory', (Join-Path $outDir 'sta'),
        '-diff_directory', (Join-Path $outDir 'diff'), '-comment_directory', (Join-Path $outDir 'comment'),
        '-homepath', (Join-Path $outDir 'home'), '-video', 'none', '-sound', 'none',
        '-nothrottle', '-nosleep', '-noplugins', '-autoboot_delay', '0',
        '-autoboot_script', (Join-Path $outDir 'dump_mame_char_region.lua'), '-seconds_to_run', '3'
    )
    & $mame @mameArgs *> 'mame.log'
    if ($LASTEXITCODE -ne 0) { throw "MAME ROM-window probe failed with exit $LASTEXITCODE; see mame.log" }
    $mameWindow = Join-Path $outDir 'mame-char-window.bin'
    if (-not (Test-Path -LiteralPath $mameWindow) -or (Get-Item -LiteralPath $mameWindow).Length -ne 2048) {
        throw 'MAME probe did not produce the expected 2KiB mapped character window.'
    }
    & python (Join-Path $PSScriptRoot 'build_char_vectors.py') --rom-zip $zip --mame-window $mameWindow --out-dir $outDir
    if ($LASTEXITCODE -ne 0) { throw 'Character ROM/palette source-vector generation failed.' }

    & wsl.exe -d archlinux -- bash -lc "cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && bash tools/side_trak/run_charrom_palette.sh $Run"
    if ($LASTEXITCODE -ne 0) { throw 'Verilator character ROM/palette candidate regression failed.' }
    [ordered]@{
        set = 'sidetrac'
        run = $Run
        mameVersion = (& $mame -noreadconfig -version | Select-Object -First 1)
        mameSha256 = (Get-FileHash -LiteralPath $mame -Algorithm SHA256).Hash
        romZipSha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        characterLuaSha256 = (Get-FileHash -LiteralPath (Join-Path $outDir 'dump_mame_char_region.lua') -Algorithm SHA256).Hash
        candidateSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'candidates/side_trak/exidy_sidetrak_charrom.sv') -Algorithm SHA256).Hash
        sourceSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
        mameVerification = 'romset sidetrac is good'
        mappedCharacterWindowBytes = 2048
        mamePixelCases = 16384
        capture = 'No screenshot or decoded image; MAME debugger reads only the mapped ROM window.'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $outDir 'run-manifest.json')
}
finally { Set-Location $oldLocation }
