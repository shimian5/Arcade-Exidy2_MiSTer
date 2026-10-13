param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = Join-Path $repoRoot 'simulation/side_trak/roms'
$zip = Join-Path $romRoot 'sidetrac.zip'
$outDir = Join-Path $repoRoot "simulation/side_trak/$Run"
$sourceLua = Join-Path $PSScriptRoot 'side_trak_reference.lua'

if (-not (Test-Path -LiteralPath $zip)) { throw "ROM archive not staged: $zip" }
if (Test-Path -LiteralPath $outDir) { throw "Output already exists at $outDir; choose a fresh Run." }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$scriptFile = Join-Path $outDir 'side_trak_reference.lua'
Copy-Item -LiteralPath $sourceLua -Destination $scriptFile
@('cfg','nvram','input','sta','diff','comment','home') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}

$oldLocation = Get-Location
try {
    Set-Location $outDir
    & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms sidetrac *> 'verifyroms.log'
    $verifyCode = $LASTEXITCODE
    $verifyText = [System.IO.File]::ReadAllText((Join-Path $outDir 'verifyroms.log'))
    [System.IO.File]::WriteAllText((Join-Path $outDir 'verifyroms.log'), $verifyText, [System.Text.UTF8Encoding]::new($false))
    if ($verifyCode -ne 0 -or (Get-Content 'verifyroms.log' -Raw) -notmatch 'romset sidetrac is good') {
        throw "MAME 0.288 ROM verification failed (exit $verifyCode)"
    }

    $args = @(
        'sidetrac', '-noreadconfig', '-nowriteconfig', '-skip_gameinfo',
        '-rompath', $romRoot,
        '-cfg_directory', (Join-Path $outDir 'cfg'),
        '-nvram_directory', (Join-Path $outDir 'nvram'),
        '-input_directory', (Join-Path $outDir 'input'),
        '-state_directory', (Join-Path $outDir 'sta'),
        '-diff_directory', (Join-Path $outDir 'diff'),
        '-comment_directory', (Join-Path $outDir 'comment'),
        '-homepath', (Join-Path $outDir 'home'),
        '-snapshot_directory', $outDir,
        '-video', 'none', '-sound', 'auto', '-volume', '-32', '-nothrottle', '-nosleep',
        '-noplugins', '-autoboot_delay', '0', '-autoboot_script', $scriptFile,
        '-seconds_to_run', '64'
    )
    & $mame @args *> 'mame.log'
    $runCode = $LASTEXITCODE
    $manifest = [ordered]@{
        set = 'sidetrac'
        run = $Run
        emulator = (& $mame -noreadconfig -version | Select-Object -First 1)
        mameSha256 = (Get-FileHash -LiteralPath $mame -Algorithm SHA256).Hash
        romZipSha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        luaSha256 = (Get-FileHash -LiteralPath $scriptFile -Algorithm SHA256).Hash
        exidySourceSha256 = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
        verifyRomExitCode = $verifyCode
        mameExitCode = $runCode
        targetFrames = 3600
        inputSchedule = 'coin1 frames 60-69; start1 120-149; right 240-359; fire 360-479; left 480-599; up 600-719; down 720-839; Lua nonzero means active'
        busPolicy = 'passive actual CPU read/write taps only; no scripted memory reads; $5103 only observed on real CPU reads'
        captureSettings = [ordered]@{ video='none'; sound='auto'; volumeDb=-32; throttle=$false; plugins=$false; frameTarget=3600 }
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 'run-manifest.json'
    if ($runCode -ne 0) { throw "MAME reference run failed (exit $runCode); see mame.log" }
    Get-Content 'events.log'
}
finally { Set-Location $oldLocation }
