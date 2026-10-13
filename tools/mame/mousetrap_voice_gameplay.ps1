param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run,
    [ValidateRange(600,3600)][int]$Frames = 3600,
    [ValidateSet('late','early','freeplay','active','sync','postdelay')][string]$InputProfile = 'late',
    [switch]$CaptureWav,
    [switch]$CaptureVoiceState
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = (Resolve-Path (Join-Path $repoRoot 'simulation/a2-local/roms')).Path
$outDir = Join-Path $repoRoot "simulation/mousetrap_voice_gameplay_$Run"
$lua = Join-Path $PSScriptRoot 'mousetrap_voice_gameplay.lua'
if (Test-Path -LiteralPath $outDir) { throw "Output already exists: $outDir" }
if (-not (Test-Path -LiteralPath (Join-Path $romRoot 'mtrap.zip'))) { throw "Staged mtrap.zip not found in $romRoot" }
if ($CaptureVoiceState -and $InputProfile -ne 'postdelay') { throw 'CaptureVoiceState requires the normal-input postdelay profile' }
if ($CaptureVoiceState -and $Frames -lt 2375) { throw 'CaptureVoiceState requires at least 2375 frames to include the F9 release and first voice writes' }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
@('cfg','nvram','input','sta','diff','comment','home','snap') | ForEach-Object {
    New-Item -ItemType Directory -Force -Path (Join-Path $outDir $_) | Out-Null
}
$env:MTRAP_VOICE_OUT = Join-Path $outDir 'bus.csv'
$env:MTRAP_VOICE_EVENTS = Join-Path $outDir 'events.log'
$env:MTRAP_VOICE_SNAPSHOT_DIR = Join-Path $outDir 'snap'
$env:MTRAP_VOICE_FRAMES = [string]$Frames
$env:MTRAP_VOICE_INPUT_PROFILE = $InputProfile
$env:MTRAP_VOICE_STATE_TRACE = if ($CaptureVoiceState) { '1' } else { '0' }
if ($CaptureVoiceState) { $env:MTRAP_VOICE_STATE_OUT = Join-Path $outDir 'voice-state.csv' }
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
    if ($CaptureWav) {
        $arguments += @('-wavwrite', (Join-Path $outDir 'native.wav'))
    }
    & $mame @arguments *> 'mame.log'
    $exitCode = $LASTEXITCODE
    [ordered]@{
        set = 'mtrap'
        frames = $Frames
        inputProfile = $InputProfile
        voiceStateTrace = [bool]$CaptureVoiceState
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
    $eventPath = Join-Path $outDir 'events.log'
    if ($CaptureVoiceState) {
        $eventText = Get-Content -Raw -LiteralPath $eventPath
        if ($eventText -notmatch 'voice_state_api probe_BC=[0-9A-F]{4}') { throw "Voice CPU debugger state probe failed; see $eventPath and mame.log" }
        if ($eventText -match 'ERROR') { throw "Voice state capture reported an error; see $eventPath and mame.log" }
        if ($eventText -notmatch "complete frame=$Frames(?:\r?\n|$)") { throw "Voice state capture did not complete at frame $Frames; see $eventPath and mame.log" }
        $statePath = Join-Path $outDir 'voice-state.csv'
        if (-not (Test-Path -LiteralPath $statePath)) { throw "Voice state CSV is missing: $statePath" }
        $stateRows = @(Import-Csv -LiteralPath $statePath)
        if ($stateRows.Count -lt 10) { throw "Voice state capture has only $($stateRows.Count) rows; see $statePath" }
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $outDir 'run-manifest.json') | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName voiceStateRows -NotePropertyValue $stateRows.Count
        $manifest | Add-Member -NotePropertyName voiceStateSha256 -NotePropertyValue (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $outDir 'run-manifest.json')
    }
    Get-Content $eventPath
}
finally {
    Set-Location $oldLocation
}
