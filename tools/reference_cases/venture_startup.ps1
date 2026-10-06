param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run,
    [ValidateRange(1,120)][int]$Seconds = 60,
    [switch]$InputProbe,
    [switch]$RightOnlyProbe
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'
$outDir = Join-Path $repoRoot "simulation/venture_startup/$Run"
$sourceScript = Join-Path $PSScriptRoot 'venture_startup.lua'

if ($InputProbe -and $RightOnlyProbe) { throw 'Choose either -InputProbe or -RightOnlyProbe.' }

if (Test-Path $outDir) { throw "Output already exists at $outDir; choose a fresh Run name." }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$scriptFile = Join-Path $outDir 'venture_startup.lua'
Copy-Item -LiteralPath $sourceScript -Destination $scriptFile
if ($InputProbe) { Set-Content -NoNewline -Encoding ascii -LiteralPath (Join-Path $outDir 'attract-input.flag') -Value "coin-start-right-fire`n" }
if ($RightOnlyProbe) { Set-Content -NoNewline -Encoding ascii -LiteralPath (Join-Path $outDir 'attract-input.flag') -Value "coin-start-right-only`n" }
@('cfg','nvram','input','sta','diff','comment','home') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}

$oldLocation = Get-Location
try {
    Set-Location $outDir
    & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms venture *> 'verifyroms.log'
    $verifyCode = $LASTEXITCODE
    $verifyText = [System.IO.File]::ReadAllText((Join-Path $outDir 'verifyroms.log'))
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $outDir 'verifyroms.log'), $verifyText, $utf8NoBom)
    if ($verifyCode -ne 0 -or (Get-Content 'verifyroms.log' -Raw) -notmatch 'is good') {
        throw "MAME ROM verification failed (exit $verifyCode)"
    }

    $mameArgs = @(
        'venture', '-noreadconfig', '-nowriteconfig', '-skip_gameinfo',
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
        '-seconds_to_run', ($Seconds + 4).ToString()
    )
    & $mame @mameArgs *> 'mame.log'
    $runCode = $LASTEXITCODE
    [ordered]@{
        set = 'venture'
        run = $Run
        emulator = (& $mame -noreadconfig -version | Select-Object -First 1)
        mameExe = $mame
        mameExeSha256 = (Get-FileHash $mame -Algorithm SHA256).Hash
        romLibrary = $romRoot
        romZip = Join-Path $romRoot 'venture.zip'
        romZipSha256 = (Get-FileHash (Join-Path $romRoot 'venture.zip') -Algorithm SHA256).Hash
        luaScriptSha256 = (Get-FileHash $scriptFile -Algorithm SHA256).Hash
        pinnedExidySourceSha256 = (Get-FileHash (Join-Path $repoRoot 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
        sourceCommit = '27a8d9e85b58058965907d1d8a7a92f8ed039348'
        command = ($mameArgs -join ' ')
        verifyRomExitCode = $verifyCode
        mameExitCode = $runCode
        secondsLimit = $Seconds
        input = if ($InputProbe) { 'Coin 1 active 2100-2109; Start 1 active 2160-2189; Right+Button 1 active 2400-2519; fields nonzero=active' } elseif ($RightOnlyProbe) { 'Coin 1 active 2100-2109; Start 1 active 2160-2189; Right active 2400-2519; Button 1 released; fields nonzero=active' } else { 'zero input; no fields are set by Lua' }
        inputProbe = ($InputProbe.IsPresent -or $RightOnlyProbe.IsPresent)
        inputMode = if ($InputProbe) { 'right-and-fire' } elseif ($RightOnlyProbe) { 'right-only' } else { 'zero-input' }
        fireProbe = $InputProbe.IsPresent
        captureSettings = [ordered]@{ video='none'; sound='auto'; volumeDb=-32; throttle=$false; sleep=$false; plugins=$false; seconds=$Seconds; stopFrame=($Seconds * 60); inputMode=$(if ($InputProbe) {'right-and-fire'} elseif ($RightOnlyProbe) {'right-only'} else {'zero-input'}) }
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 'run-manifest.json'
    if ($runCode -ne 0) { throw "MAME run failed (exit $runCode)" }
    Get-Content 'events.log'
}
finally {
    Set-Location $oldLocation
}
