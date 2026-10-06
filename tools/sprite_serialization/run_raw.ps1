param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run,
    [Parameter(Mandatory=$true)][ValidateSet('right-fire','right-only')][string]$Mode,
    [ValidateRange(1,120)][int]$Seconds = 60
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'
$outDir = Join-Path $repoRoot "simulation/sprite_serialization/$Run"
$sourceScript = Join-Path $PSScriptRoot 'venture_raw.lua'
if (Test-Path $outDir) { throw "Output already exists at $outDir; choose a fresh Run name." }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$scriptFile = Join-Path $outDir 'venture_raw.lua'
Copy-Item -LiteralPath $sourceScript -Destination $scriptFile
if ($Mode -eq 'right-fire') { $inputMode = 'coin-start-right-fire' } else { $inputMode = 'coin-start-right-only' }
[IO.File]::WriteAllText((Join-Path $outDir 'attract-input.flag'), $inputMode + "`n", [Text.Encoding]::ASCII)
@('cfg','nvram','input','sta','diff','comment','home') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}

$oldLocation = Get-Location
try {
    Set-Location $outDir
    & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms venture *> 'verifyroms.log'
    $verifyCode = $LASTEXITCODE
    $verifyText = [IO.File]::ReadAllText((Join-Path $outDir 'verifyroms.log'))
    [IO.File]::WriteAllText((Join-Path $outDir 'verifyroms.log'), $verifyText, [Text.UTF8Encoding]::new($false))
    if ($verifyCode -ne 0 -or (Get-Content 'verifyroms.log' -Raw) -notmatch 'is good') {
        throw "MAME ROM verification failed (exit $verifyCode)"
    }
    $mameArgs = @(
        'venture','-noreadconfig','-nowriteconfig','-skip_gameinfo','-rompath',$romRoot,
        '-cfg_directory',(Join-Path $outDir 'cfg'),'-nvram_directory',(Join-Path $outDir 'nvram'),
        '-input_directory',(Join-Path $outDir 'input'),'-state_directory',(Join-Path $outDir 'sta'),
        '-diff_directory',(Join-Path $outDir 'diff'),'-comment_directory',(Join-Path $outDir 'comment'),
        '-homepath',(Join-Path $outDir 'home'),'-snapshot_directory',$outDir,
        '-video','none','-sound','auto','-volume','-32','-nothrottle','-nosleep','-noplugins',
        '-autoboot_delay','0','-autoboot_script',$scriptFile,'-seconds_to_run',($Seconds + 4).ToString()
    )
    & $mame @mameArgs *> 'mame.log'
    $runCode = $LASTEXITCODE
    $exeHash = (Get-FileHash -LiteralPath $mame -Algorithm SHA256).Hash
    $zip = Join-Path $romRoot 'venture.zip'
    $romHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $luaHash = (Get-FileHash -LiteralPath $scriptFile -Algorithm SHA256).Hash
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
    [ordered]@{
        set='venture'; run=$Run; mode=$Mode; emulator=(& $mame -noreadconfig -version | Select-Object -First 1)
        mameExeSha256=$exeHash; romZip=$zip; romZipSha256=$romHash; rawLuaScriptSha256=$luaHash
        sourceCommit='27a8d9e85b58058965907d1d8a7a92f8ed039348'; exidyCppSha256=$sourceHash
        command=($mameArgs -join ' '); verifyRomExitCode=$verifyCode; mameExitCode=$runCode
        secondsLimit=$Seconds; targetFrame=($Seconds * 60)
        inputTimeline='coin 2100-2109; start 2160-2189; right 2400-2519; Button 1 2400-2519 only in right-fire mode; nonzero active'
        captureSettings=[ordered]@{video='none';sound='auto';volumeDb=-32;throttle=$false;sleep=$false;plugins=$false;seconds=$Seconds;targetFrame=($Seconds*60);mode=$Mode}
        capturedAtUtc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 'run-manifest.json'
    if ($runCode -ne 0) { throw "MAME run failed (exit $runCode)" }
    Get-Content 'events.log'
}
finally { Set-Location $oldLocation }
