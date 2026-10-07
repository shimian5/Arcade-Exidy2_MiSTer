param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Run,
    [ValidateSet('venture','pepper2','hardhat','mtrap')][string[]]$Set = @('venture','pepper2','hardhat','mtrap'),
    [ValidateRange(1,300)][int]$Seconds = 120
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$mame = 'C:\MiSTerDev\mame\mame.exe'
$romRoot = '\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)'
$luaSource = Join-Path $PSScriptRoot 'mame_pia_capture.lua'
$runRoot = Join-Path $repo "simulation/pia_firmware_timing/$Run"
if (Test-Path -LiteralPath $runRoot) { throw "Output already exists: $runRoot" }
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$mameVersion = (& $mame -noreadconfig -version | Select-Object -First 1)
$mameHash = (Get-FileHash -LiteralPath $mame -Algorithm SHA256).Hash
$romHashes = @{}
$results = @()

foreach ($setName in $Set) {
    $out = Join-Path $runRoot $setName
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $luaCopyPath = Join-Path $out 'mame_pia_capture.lua'
    Copy-Item -LiteralPath $luaSource -Destination $luaCopyPath
    @('cfg','nvram','input','state','diff','comment','home') | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $out $_) | Out-Null
    }
    $rom = Join-Path $romRoot "$setName.zip"
    $verifyLog = Join-Path $out 'verifyroms.log'
    Push-Location $out
    try {
        & $mame -noreadconfig -nowriteconfig -rompath $romRoot -verifyroms $setName *> $verifyLog
        $verify = $LASTEXITCODE
        if ($verify -ne 0 -or (Get-Content -LiteralPath $verifyLog -Raw) -notmatch 'is good') {
            throw "ROM verification failed for $setName (exit $verify); see $verifyLog"
        }
        $args = @(
            $setName, '-noreadconfig', '-nowriteconfig', '-skip_gameinfo',
            '-rompath', $romRoot,
            '-cfg_directory', (Join-Path $out 'cfg'), '-nvram_directory', (Join-Path $out 'nvram'),
            '-input_directory', (Join-Path $out 'input'), '-state_directory', (Join-Path $out 'state'),
            '-diff_directory', (Join-Path $out 'diff'), '-comment_directory', (Join-Path $out 'comment'),
            '-homepath', (Join-Path $out 'home'), '-video', 'none', '-sound', 'none',
            '-nothrottle', '-nosleep', '-noplugins', '-autoboot_delay', '0',
            '-autoboot_script', $luaCopyPath, '-seconds_to_run', ($Seconds + 4).ToString()
        )
        & $mame @args *> (Join-Path $out 'mame.log')
        $runCode = $LASTEXITCODE
        if ($runCode -ne 0) { throw "MAME failed for $setName (exit $runCode); see $(Join-Path $out 'mame.log')" }
        $romHashes[$setName] = (Get-FileHash -LiteralPath $rom -Algorithm SHA256).Hash
        $results += [ordered]@{
            set=$setName; verifyExitCode=$verify; mameExitCode=$runCode
            romZip=$rom; romSha256=$romHashes[$setName]
            scriptSha256=(Get-FileHash -LiteralPath $luaCopyPath -Algorithm SHA256).Hash
            trace=(Join-Path $out 'pia-bus.csv'); events=(Join-Path $out 'pia-events.log')
        }
        Get-Content -LiteralPath (Join-Path $out 'pia-events.log') | Select-Object -Last 12
    }
    finally { Pop-Location }
}

[ordered]@{
    run=$Run; capturedAtUtc=[DateTime]::UtcNow.ToString('o'); mame=$mame
    mameVersion=$mameVersion; mameSha256=$mameHash; romRoot=$romRoot
    pinnedSourceCommit='27a8d9e85b58058965907d1d8a7a92f8ed039348'
    exidyCppSha256=(Get-FileHash (Join-Path $repo 'simulation/reference_sources/exidy.cpp') -Algorithm SHA256).Hash
    exidySoundCppSha256=(Get-FileHash (Join-Path $repo 'simulation/reference_sources/exidysound.cpp') -Algorithm SHA256).Hash
    seconds=$Seconds; inputs='Coin 1 frames 1920-1949 and 1 Player Start frames 2040-2069 active when exposed by game; zero otherwise'
    commandTemplate=('-noreadconfig -nowriteconfig -skip_gameinfo -rompath <NAS split ROM path> -video none -sound none -nothrottle -nosleep -noplugins -autoboot_delay 0 -autoboot_script <copied Lua> -seconds_to_run ' + ($Seconds + 4))
    results=$results
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $runRoot 'manifest.json')
