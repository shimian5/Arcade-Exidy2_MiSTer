param(
    [Parameter(Mandatory=$true)][ValidateSet('targ','spectar','venture')][string]$Set,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'
$outDir = Join-Path $repoRoot "simulation/reference_cases/$Set/$Run"
$sourceScript = Join-Path $PSScriptRoot 'exidy_reference.lua'
$scriptFile = Join-Path $outDir 'exidy_reference.lua'
$seconds = if ($Set -eq 'venture') { '16' } else { '64' }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if ((Test-Path (Join-Path $outDir 'run-manifest.json')) -or (Test-Path (Join-Path $outDir 'mame.log'))) {
    throw "Output already exists at $outDir; select a fresh Run name to preserve evidence."
}
Copy-Item -LiteralPath $sourceScript -Destination $scriptFile
@('cfg','nvram','input','sta','diff','comment','home') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}

$oldLocation = Get-Location
try {
    Set-Location $outDir
    & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms $Set *> 'verifyroms.log'
    $verifyCode = $LASTEXITCODE
    $verifyText = [System.IO.File]::ReadAllText((Join-Path $outDir 'verifyroms.log'))
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $outDir 'verifyroms.log'), $verifyText, $utf8NoBom)
    if ($verifyCode -ne 0 -or (Get-Content 'verifyroms.log' -Raw) -notmatch 'is good') {
        throw "MAME ROM verification failed for $Set (exit $verifyCode)"
    }

    $mameArgs = @(
        $Set,
        '-noreadconfig', '-nowriteconfig', '-skip_gameinfo',
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
        '-noplugins', '-autoboot_delay', '0',
        '-autoboot_script', $scriptFile,
        '-seconds_to_run', $seconds
    )
    & $mame @mameArgs *> 'mame.log'
    $runCode = $LASTEXITCODE
    [ordered]@{
        set = $Set
        run = $Run
        mameExe = $mame
        mameExeSha256 = (Get-FileHash $mame -Algorithm SHA256).Hash
        romLibrary = $romRoot
        romZip = Join-Path $romRoot "$Set.zip"
        romZipSha256 = (Get-FileHash (Join-Path $romRoot "$Set.zip") -Algorithm SHA256).Hash
        luaScriptSha256 = (Get-FileHash $scriptFile -Algorithm SHA256).Hash
        pinnedExidySourceSha256 = (Get-FileHash (Join-Path $repoRoot 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
        mameVersion = (& $mame -noreadconfig -version | Select-Object -First 1)
        sourceCommit = '27a8d9e85b58058965907d1d8a7a92f8ed039348'
        command = ($mameArgs -join ' ')
        verifyRomExitCode = $verifyCode
        mameExitCode = $runCode
        input = if ($Set -eq 'venture') { 'Coin 1 frames 30-59 active; P1 start frames 120-149 active; RIGHT + BUTTON1 frames 240-419 active; all else released; MAME Lua digital fields set to 1=active' } else { 'zero input for entire attract capture' }
        captureSettings = [ordered]@{
            video = 'none'
            sound = 'auto'
            volumeDb = -32
            throttle = $false
            sleep = $false
            plugins = $false
            secondsToRun = [int]$seconds
            targetFrame = if ($Set -eq 'venture') { 900 } else { 3600 }
        }
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 'run-manifest.json'
    if ($runCode -ne 0) { throw "MAME run failed for $Set (exit $runCode)" }
    Get-Content 'events.log'
}
finally {
    Set-Location $oldLocation
}
