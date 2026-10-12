$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    $toolPath = Join-Path $modelsimBin $tool
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "Required ModelSim executable is missing: $toolPath" }
}
$hexPath = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$romManifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$romManifest = Get-Content -LiteralPath $romManifestPath -Raw | ConvertFrom-Json
$hexLines = @(Get-Content -LiteralPath $hexPath)
if ($hexLines.Count -ne 16384) { throw "Expected 16,384 staged ROM bytes; found $($hexLines.Count)" }
$romBytes = [byte[]]::new($hexLines.Count)
for ($i = 0; $i -lt $hexLines.Count; $i++) {
    if ($hexLines[$i] -notmatch '^[0-9a-fA-F]{2}$') { throw "Invalid ROM hex at line $($i + 1)" }
    $romBytes[$i] = [Convert]::ToByte($hexLines[$i],16)
}
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $romHash = [Convert]::ToHexString($sha.ComputeHash($romBytes)).ToLowerInvariant() }
finally { $sha.Dispose() }
if ($romHash -ne $romManifest.images.mtrap.sha256.ToLowerInvariant()) { throw "Staged ROM hash mismatch: $romHash" }

$outputRoot = Join-Path $repoRoot 'simulation\mousetrap_boot'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$runDir = Join-Path $outputRoot ('modelsim-boot-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$resolvedOutputRoot = (Resolve-Path $outputRoot).Path
New-Item -ItemType Directory -Path $runDir | Out-Null
if (-not $runDir.StartsWith($resolvedOutputRoot,[StringComparison]::OrdinalIgnoreCase)) { throw "Run directory escaped ignored simulation output: $runDir" }

$packSource = Join-Path $repoRoot 'modules\cpu-t80\T80_Pack.vhd'
$regSource = Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'
$mcodeSource = Join-Path $repoRoot 'modules\cpu-t80\T80_MCode.vhd'
$aluSource = Join-Path $repoRoot 'modules\cpu-t80\T80_ALU.vhd'
$coreSource = Join-Path $repoRoot 'modules\cpu-t80\T80.vhd'
$t80seOriginal = Join-Path $repoRoot 'modules\cpu-t80\T80se.vhd'
$z80Original = Join-Path $repoRoot 'modules\cpu-t80\Z80.vhd'
$sourceHashes = [ordered]@{}
foreach ($source in @($packSource,$regSource,$mcodeSource,$aluSource,$coreSource,$t80seOriginal,$z80Original)) {
    $sourceHashes[[IO.Path]::GetFileName($source)] = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
}

$cases = @('raw','zero','seed_a','seed_b','seed_odd')
$results = @()
foreach ($caseName in $cases) {
    $caseDir = Join-Path $runDir $caseName
    New-Item -ItemType Directory -Path $caseDir | Out-Null
    Push-Location $caseDir
    try {
        & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
        if ($LASTEXITCODE -ne 0) { throw "$caseName vlib failed; see $caseDir\vlib.log" }

        $regText = Get-Content -LiteralPath $regSource -Raw
        if ($caseName -ne 'raw') {
            $hInit = @(); $lInit = @()
            for ($bank = 0; $bank -lt 8; $bank++) {
                if ($caseName -eq 'zero') { $hValue=0; $lValue=0 }
                elseif ($caseName -eq 'seed_a') { $hValue=0x20+$bank; $lValue=0x80+$bank }
                elseif ($caseName -eq 'seed_b') { $hValue=0xd0+$bank; $lValue=0x30+(3*$bank) }
                else { $hValue=0x21+$bank; $lValue=0x81+$bank }
                $hInit += ('{0} => x"{1:X2}"' -f $bank,$hValue)
                $lInit += ('{0} => x"{1:X2}"' -f $bank,$lValue)
            }
            foreach ($bank in @('RegsH','RegsL')) {
                $needle = "signal $bank : Register_Image(0 to 7);"
                if ([regex]::Matches($regText,[regex]::Escape($needle)).Count -ne 1) { throw "Seed source guard failed for $bank" }
            }
            $regText = $regText.Replace('signal RegsH : Register_Image(0 to 7);',
                ('signal RegsH : Register_Image(0 to 7) := (' + ($hInit -join ', ') + ');'))
            $regText = $regText.Replace('signal RegsL : Register_Image(0 to 7);',
                ('signal RegsL : Register_Image(0 to 7) := (' + ($lInit -join ', ') + ');'))
        }
        $regBoot = Join-Path $caseDir 'T80_Reg_boot.vhd'
        [IO.File]::WriteAllText($regBoot,$regText)

        $t80seText = Get-Content -LiteralPath $t80seOriginal -Raw
        foreach ($guard in @('entity T80se is','end T80se;','architecture rtl of T80se is',
                              'DO              : out std_logic_vector(7 downto 0)',
                              'DO         => DO,')) {
            if (-not $t80seText.Contains($guard)) { throw "T80se debug-copy source guard failed: $guard" }
        }
        $t80seText = $t80seText.Replace('entity T80se is','entity T80se_boot is')
        $t80seText = $t80seText.Replace('end T80se;','end T80se_boot;')
        $t80seText = $t80seText.Replace('architecture rtl of T80se is','architecture rtl of T80se_boot is')
        $t80seText = $t80seText.Replace('DO              : out std_logic_vector(7 downto 0)',
            "DO              : out std_logic_vector(7 downto 0);`r`n`t`tREG             : out std_logic_vector(211 downto 0)")
        $t80seText = $t80seText.Replace('DO         => DO,',"DO         => DO,`r`n`t`t`tREG        => REG,")
        $t80seBoot = Join-Path $caseDir 'T80se_boot.vhd'
        [IO.File]::WriteAllText($t80seBoot,$t80seText)

        $z80Text = Get-Content -LiteralPath $z80Original -Raw
        foreach ($guard in @('entity Z80 is','end Z80;','architecture SYN of Z80 is',
                              'T80se is','DO          : out std_logic_vector(7 downto 0)',
                              'datao        : out std_logic_vector(7 downto 0);',
                              'Z80_uP : T80se','DO          => datao')) {
            if (-not $z80Text.Contains($guard)) { throw "Z80 debug-copy source guard failed: $guard" }
        }
        $z80Text = $z80Text.Replace('entity Z80 is','entity Z80_boot is')
        $z80Text = $z80Text.Replace('end Z80;','end Z80_boot;')
        $z80Text = $z80Text.Replace('architecture SYN of Z80 is','architecture SYN of Z80_boot is')
        $z80Text = $z80Text.Replace('T80se','T80se_boot')
        $dataoPattern = [regex]'(datao\s+:\s+out\s+std_logic_vector\(7 downto 0\);)'
        if ($dataoPattern.Matches($z80Text).Count -ne 1) { throw 'Z80 datao declaration guard failed' }
        $z80Text = $dataoPattern.Replace($z80Text,
            '$1' + "`r`n     REG          : out std_logic_vector(211 downto 0);",1)
        $z80Text = $z80Text.Replace('DO          : out std_logic_vector(7 downto 0)',
            "DO          : out std_logic_vector(7 downto 0);`r`n`t    REG         : out std_logic_vector(211 downto 0)")
        $z80Text = $z80Text.Replace('DO          => datao',"DO          => datao,`r`n`t      REG         => REG")
        $z80Boot = Join-Path $caseDir 'Z80_boot.vhd'
        [IO.File]::WriteAllText($z80Boot,$z80Text)

        [ordered]@{
            case = $caseName
            rom_payload_sha256 = $romHash
            source_hashes = $sourceHashes
            generated_register_initialization = if ($caseName -eq 'raw') { 'none; original uninitialized declarations' } else { $caseName }
            debug_wrapper = 'Generated simulation-only Z80/T80se copies expose T80.REG; instruction and register-file behavior otherwise source-identical.'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $caseDir 'run-manifest.json') -Encoding utf8

        $vhdl = @($packSource,$regBoot,$mcodeSource,$aluSource,$coreSource,$t80seBoot,$z80Boot)
        & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
        if ($LASTEXITCODE -ne 0) { throw "$caseName vcom failed; see $caseDir\vcom.log" }
        & (Join-Path $modelsimBin 'vlog.exe') -work work `
            (Join-Path $repoRoot 'rtl\speech_rom_bus.v') `
            (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') `
            (Join-Path $PSScriptRoot 'tb_mousetrap_boot.sv') *> vlog.log
        if ($LASTEXITCODE -ne 0) { throw "$caseName vlog failed; see $caseDir\vlog.log" }
        $ioPath = (Join-Path $caseDir 'io.csv').Replace('\','/')
        & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mousetrap_boot `
            ('+ROM=' + $hexPath.Replace('\','/')) ('+IO_LOG=' + $ioPath) ('+CASE=' + $caseName) `
            -do 'run -all; quit -f' *> vsim.log
        if ($LASTEXITCODE -ne 0) { throw "$caseName vsim failed; see $caseDir\vsim.log" }
        if ($caseName -eq 'raw') {
            $marker = Select-String -LiteralPath (Join-Path $caseDir 'vsim.log') -Pattern 'EXPECTED_(UNKNOWN_RAW_FIRST_IO|RAW_UNINITIALIZED_NO_DIGITS)' | Select-Object -First 1
            if ($null -eq $marker) { throw 'Raw uninitialized-bank negative control did not reach its expected diagnostic' }
        } else {
            foreach ($required in @('PASS PA4 warm reset retained all 128 physical bank bits','PASS seeded firmware startup')) {
                $marker = Select-String -LiteralPath (Join-Path $caseDir 'vsim.log') -SimpleMatch $required | Select-Object -First 1
                if ($null -eq $marker) { throw "$caseName missing marker '$required'" }
            }
        }
        $results += [pscustomobject]@{case=$caseName;log=(Join-Path $caseDir 'vsim.log')}
        Write-Output "PASS $caseName startup/reset fixture; logs: $caseDir"
    }
    finally { Pop-Location }
}

$evenDigitSequences = @()
foreach ($caseName in @('zero','seed_a','seed_b')) {
    $digitRows = @(Import-Csv -LiteralPath (Join-Path $runDir "$caseName\io.csv") |
        Where-Object { $_.digit -eq '0' -or $_.digit -eq '1' } | Select-Object -First 20)
    if ($digitRows.Count -ne 20) { throw "$caseName did not capture 20 binary digit samples" }
    $evenDigitSequences += ,(($digitRows | ForEach-Object { $_.digit }) -join '')
}
if (($evenDigitSequences | Select-Object -Unique).Count -ne 1) {
    throw 'Even bank seeds changed the first 20 speech digit bits'
}
$zeroRows = @(Import-Csv -LiteralPath (Join-Path $runDir 'zero\io.csv') |
    Where-Object { $_.digit -eq '0' -or $_.digit -eq '1' } | Select-Object -First 20)
$oddRows = @(Import-Csv -LiteralPath (Join-Path $runDir 'seed_odd\io.csv') |
    Where-Object { $_.digit -eq '0' -or $_.digit -eq '1' } | Select-Object -First 20)
if ($oddRows.Count -ne 20) { throw 'Odd bank seed did not capture 20 binary digit samples' }
$differentPositions = @()
for ($i = 0; $i -lt 20; $i++) {
    if ($zeroRows[$i].digit -ne $oddRows[$i].digit) {
        $differentPositions += ($i + 1)
        if ($zeroRows[$i].epoch -ne $oddRows[$i].epoch) { throw "Seed mismatch at digit $($i + 1) crossed epochs" }
    }
}
if (($differentPositions -join ',') -ne '1,2') {
    throw "Expected odd seed to differ at D0 positions 1,2 only; found $($differentPositions -join ',')"
}
Write-Output "PASS speech-bit controls: zero/seed_a/seed_b share 20 bits ($($evenDigitSequences[0])); seed_odd differs at D0 positions 1,2 only"

@{ rom_payload_sha256=$romHash; cases=$results; even_seed_digit_bits=$evenDigitSequences[0]; odd_seed_digit_bits=(($oddRows | ForEach-Object { $_.digit }) -join ''); odd_seed_mismatch_positions=$differentPositions } | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $runDir 'suite-manifest.json') -Encoding utf8
Write-Output "Suite logs: $runDir"
