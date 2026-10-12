param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run,
    [ValidateRange(600,3600)][int]$Frames = 3600,
    [ValidateSet('late','early')][string]$InputProfile = 'late'
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = (Resolve-Path (Join-Path $repoRoot 'simulation/a2-local/roms')).Path
$outDir = Join-Path $repoRoot "simulation/mousetrap_voice_gameplay_$Run"
$lua = Join-Path $PSScriptRoot 'mousetrap_voice_gameplay.lua'
if (Test-Path -LiteralPath $outDir) { throw "Output already exists: $outDir" }
if (-not (Test-Path -LiteralPath (Join-Path $romRoot 'mtrap.zip'))) { throw "Staged mtrap.zip not found in $romRoot" }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
@('cfg','nvram','input','sta','diff','comment','home','snap') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}
$env:MTRAP_VOICE_OUT = Join-Path $outDir 'bus.csv'
$env:MTRAP_VOICE_EVENTS = Join-Path $outDir 'events.log'
$env:MTRAP_VOICE_SNAPSHOT_DIR = Join-Path $outDir 'snap'
$env:MTRAP_VOICE_FRAMES = [string]$Frames
$env:MTRAP_VOICE_INPUT_PROFILE = $InputProfile
$seconds = [string]([Math]::Ceiling($Frames / 60.0) + 1)

$oldLocation = Get-Location
try {
    Set-Location $outDir
    $arguments = @(
        'mtrap', '-noreadconfig', '-nowriteconfig', '-skip_gameinfo',
        '-rompath', $romRoot,
        '-cfg_directory', (Join-Path $outDir 'cfg'),
        '-nvram_directory', (Join-Path $outDir 'nvram'),
        '-input_directory', (Join-Path $outDir 'input'),
        '-state_directory', (Join-Path $outDir 'sta'),
        '-diff_directory', (Join-Path $outDir 'diff'),
        '-comment_directory', (Join-Path $outDir 'comment'),
        '-homepath', (Join-Path $outDir 'home'),
        '-snapshot_directory', (Join-Path $outDir 'snap'),
        '-video', 'none', '-sound', 'none', '-nothrottle', '-nosleep', '-noplugins',
        '-autoboot_delay', '0', '-autoboot_script', $lua,
        '-seconds_to_run', $seconds
    )
    & $mame @arguments *> 'mame.log'
    $exitCode = $LASTEXITCODE
    [ordered]@{
        set = 'mtrap'
        frames = $Frames
        inputProfile = $InputProfile
        executable = $mame
        executableSha256 = (Get-FileHash -LiteralPath $mame -Algorithm SHA256).Hash
        rom = Join-Path $romRoot 'mtrap.zip'
        romSha256 = (Get-FileHash -LiteralPath (Join-Path $romRoot 'mtrap.zip') -Algorithm SHA256).Hash
        luaSha256 = (Get-FileHash -LiteralPath $lua -Algorithm SHA256).Hash
        runnerSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
        arguments = ($arguments -join ' ')
        exitCode = $exitCode
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $outDir 'run-manifest.json')
    if ($exitCode -ne 0) { throw "MAME exited with code $exitCode; see $outDir\mame.log" }
    Get-Content (Join-Path $outDir 'events.log')
}
finally {
    Set-Location $oldLocation
}
