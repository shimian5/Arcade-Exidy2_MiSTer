param([string]$FirmwarePcm)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$prepare = Join-Path $repoRoot 'tools\mc3417_filter\prepare_reference.py'
$biquad = Join-Path $repoRoot 'rtl\exidy_biquad.v'
$filter = Join-Path $repoRoot 'rtl\mc3417_filter.v'
foreach ($path in @($prepare, $biquad, $filter)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required fixture input missing: $path" }
}

Push-Location $repoRoot
try {
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'simulation\mc3417_filter') -Force | Out-Null
    $linuxRepo = '/mnt/' + $repoRoot.Substring(0,1).ToLower() + '/' + $repoRoot.Substring(3).Replace('\','/')
    $prepareArgs = @('-d', 'archlinux', '--', 'python3', "$linuxRepo/tools/mc3417_filter/prepare_reference.py")
    if ($FirmwarePcm) {
        $resolvedPcm = (Resolve-Path -LiteralPath $FirmwarePcm).Path
        $linuxPcm = '/mnt/' + $resolvedPcm.Substring(0,1).ToLower() + '/' + $resolvedPcm.Substring(3).Replace('\','/')
        $prepareArgs += @('--firmware-pcm', $linuxPcm)
    }
    & wsl.exe @prepareArgs *> (Join-Path $repoRoot 'simulation\mc3417_filter\prepare.log')
    if ($LASTEXITCODE -ne 0) { throw 'Reference vector preparation failed' }
}
finally { Pop-Location }

$sourceVectors = Join-Path $repoRoot 'simulation\reference_sources\mc3417_filter_generated\vectors.tsv'
if (-not (Test-Path -LiteralPath $sourceVectors)) { throw "Generated vectors missing: $sourceVectors" }
$runRoot = Join-Path $repoRoot 'simulation\mc3417_filter'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$runDir = Join-Path $runRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Copy-Item -LiteralPath $sourceVectors -Destination (Join-Path $runDir 'vectors.tsv')
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & (Join-Path $modelsimBin 'vlog.exe') -work work $biquad $filter `
        (Join-Path $PSScriptRoot 'tb_mc3417_filter.sv') *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed; see $runDir" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_mc3417_filter `
        -do 'run -all; quit -f' *> vsim.log
    if ($LASTEXITCODE -ne 0) { throw "vsim failed; see $runDir" }
    $pass = Select-String -LiteralPath (Join-Path $runDir 'vsim.log') `
        -SimpleMatch 'PASS mc3417_filter oracle fixture' | Select-Object -First 1
    if ($null -eq $pass) { throw "Missing oracle fixture PASS; see $runDir" }

    # A deliberately wrong B1 coefficient must disagree with the separately
    # generated MAME recurrence vectors. The checked-out source stays intact.
    $badBiquad = Join-Path $runDir 'exidy_biquad_bad.v'
    $rtlText = [System.IO.File]::ReadAllText($biquad)
    $wrongText = $rtlText.Replace("B1=-32'sd2012388", "B1=-32'sd1006194")
    if ($wrongText -ceq $rtlText) { throw 'Could not apply fixture B1 negative-control mutation' }
    [System.IO.File]::WriteAllText($badBiquad, $wrongText)
    & (Join-Path $modelsimBin 'vlib.exe') work_bad *> vlib-bad.log
    if ($LASTEXITCODE -ne 0) { throw 'vlib negative-control library failed' }
    & (Join-Path $modelsimBin 'vlog.exe') -work work_bad $badBiquad $filter `
        (Join-Path $PSScriptRoot 'tb_mc3417_filter.sv') *> vlog-bad.log
    if ($LASTEXITCODE -ne 0) { throw "Negative-control vlog failed; see $runDir" }
    & (Join-Path $modelsimBin 'vsim.exe') -c -lib work_bad work_bad.tb_mc3417_filter `
        -do 'run -all; quit -f' *> negative-b1.log
    $caught = Select-String -LiteralPath (Join-Path $runDir 'negative-b1.log') `
        -SimpleMatch 'Fatal: oracle mismatch' | Select-Object -First 1
    if ($null -eq $caught) { throw "B1 negative control was not rejected; see $runDir" }

    Write-Output $pass.Line.Trim()
    Write-Output 'PASS negative control: incorrect B1 coefficient rejected by independent vectors'
    Write-Output "Logs: $runDir"
}
finally { Pop-Location }
