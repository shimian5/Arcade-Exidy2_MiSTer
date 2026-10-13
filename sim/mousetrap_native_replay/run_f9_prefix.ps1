[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$romHex = Join-Path $repoRoot 'simulation\expansion_adapter\rom-images\mtrap.hex'
$romManifestPath = Join-Path $repoRoot 'docs\design\expansion-adapter\increment-07-roms.json'
$romManifest = Get-Content -LiteralPath $romManifestPath -Raw | ConvertFrom-Json
$romBytes = [byte[]]::new(16384)
$hexLines = @(Get-Content -LiteralPath $romHex)
if ($hexLines.Count -ne $romBytes.Length) { throw "Expected 16,384 ROM bytes; got $($hexLines.Count)" }
for ($i=0; $i -lt $hexLines.Count; $i++) { $romBytes[$i]=[Convert]::ToByte($hexLines[$i],16) }
$romHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($romBytes)).ToLowerInvariant()
if ($romHash -ne $romManifest.images.mtrap.sha256.ToLowerInvariant()) { throw 'Staged Mouse Trap ROM hash mismatch' }
foreach ($tool in @('vlib.exe','vcom.exe','vlog.exe','vsim.exe')) { if (-not (Test-Path (Join-Path $modelsimBin $tool))) { throw "Missing ModelSim executable $tool" } }
$outputRoot=Join-Path $repoRoot 'simulation\mousetrap_native_replay'
$runDir=Join-Path $outputRoot ('f9-prefix-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
$regSourceOriginal=Join-Path $repoRoot 'modules\cpu-t80\T80_Reg.vhd'
$originalRegText=Get-Content -LiteralPath $regSourceOriginal -Raw
$results=@()
foreach ($seed in @(0x45,0x46)) {
    $seedDir=Join-Path $runDir ('seed-' + $seed.ToString('X2'))
    New-Item -ItemType Directory -Path $seedDir | Out-Null
    $regText=$originalRegText
    $expected=@{
        'RegsH'="signal RegsH : Register_Image(0 to 7) := (0 => x`"$($seed.ToString('X2'))`", others => x`"00`");"
        'RegsL'='signal RegsL : Register_Image(0 to 7) := (0 => x"BF", others => x"00");'
    }
    foreach ($bank in @('RegsH','RegsL')) {
        $declaration="signal $bank : Register_Image(0 to 7);"
        if ([regex]::Matches($regText,[regex]::Escape($declaration)).Count -ne 1) { throw "Source guard failed for $bank" }
        $regText=$regText.Replace($declaration,$expected[$bank])
    }
    $regSource=Join-Path $seedDir 'T80_Reg_BC_seed.vhd'
    [IO.File]::WriteAllText($regSource,$regText)
    [ordered]@{
        scope='Simulation-only F9 prefix B/C seed control; not full native CPU state restoration or phrase replay'
        seedBC=('0x' + $seed.ToString('X2') + 'BF')
        initialRegisterPolicy='BC high/low bytes seeded; other register-file slots zero; T80 control state follows its reset logic'
        nativeObservedAtF9Release='PC=001A AF=0012 BC=46BF DE=0000 HL=36D3 SP=3A18 IX=00C4 IY=0000; only BC is varied here'
        romPayloadSha256=$romHash
        registerSourceSha256=(Get-FileHash $regSourceOriginal -Algorithm SHA256).Hash
        seededRegisterSourceSha256=(Get-FileHash $regSource -Algorithm SHA256).Hash
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $seedDir 'run-manifest.json') -Encoding utf8
    Push-Location $seedDir
    try {
        & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
        if ($LASTEXITCODE) { throw "vlib failed for B=$($seed.ToString('X2')); see $seedDir\vlib.log" }
        $vhdl=@((Join-Path $repoRoot 'modules\cpu-t80\T80_Pack.vhd'),$regSource,(Join-Path $repoRoot 'modules\cpu-t80\T80_MCode.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80_ALU.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\T80se.vhd'),(Join-Path $repoRoot 'modules\cpu-t80\Z80.vhd'))
        & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work @vhdl *> vcom.log
        if ($LASTEXITCODE) { throw "vcom failed for B=$($seed.ToString('X2')); see $seedDir\vcom.log" }
        & (Join-Path $modelsimBin 'vlog.exe') -work work (Join-Path $repoRoot 'rtl\speech_rom_bus.v') (Join-Path $repoRoot 'rtl\mousetrap_voice_io.v') (Join-Path $PSScriptRoot 'tb_f9_prefix_seed.sv') *> vlog.log
        if ($LASTEXITCODE) { throw "vlog failed for B=$($seed.ToString('X2')); see $seedDir\vlog.log" }
        & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_f9_prefix_seed ("+ROM="+$romHex.Replace('\','/')) ("+IO_LOG="+(Join-Path $seedDir 'io.csv').Replace('\','/')) ("+SEED=$seed") -do 'run -all; quit -f' *> vsim.log
        if ($LASTEXITCODE) { throw "vsim failed for B=$($seed.ToString('X2')); see $seedDir\vsim.log" }
        $rows=@(Import-Csv -LiteralPath (Join-Path $seedDir 'io.csv'))
        $expectedData=if($seed -eq 0x45){@('45','46','55')}else{@('46','47','55')}
        if ($rows.Count -ne 3) { throw "B=$($seed.ToString('X2')) expected 3 writes, got $($rows.Count)" }
        for($i=0;$i -lt 3;$i++) {
            if($rows[$i].data -ne $expectedData[$i] -or $rows[$i].address -ne ($expectedData[$i]+'EF')) { throw "B=$($seed.ToString('X2')) row $($i+1) was $($rows[$i].address)/$($rows[$i].data), expected $($expectedData[$i])" }
        }
        $results += [pscustomobject]@{seedB=$seed.ToString('X2'); outputs=(($rows | ForEach-Object { $_.data }) -join ','); addresses=(($rows | ForEach-Object { $_.address }) -join ','); log=(Join-Path $seedDir 'io.csv')}
        Write-Output (Select-String -LiteralPath (Join-Path $seedDir 'vsim.log') -SimpleMatch 'PREFIX ' | Select-Object -First 1).Line.Trim()
    } finally { Pop-Location }
}
$results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $runDir 'comparison.json') -Encoding utf8
$summary=($results | ForEach-Object { "B=$($_.seedB): $($_.outputs)" }) -join '; '
Write-Output "Comparison: $summary"
Write-Output "Logs: $runDir"
