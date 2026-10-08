param([switch]$Production)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsimBin = 'C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
foreach ($tool in @('vlib.exe', 'vcom.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $modelsimBin $tool))) { throw "Missing ModelSim tool: $tool" }
}
$outRoot = Join-Path $repoRoot 'simulation\pia_return_mailbox'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$runDir = Join-Path $outRoot ('modelsim-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDir | Out-Null
$resolvedOut = (Resolve-Path $outRoot).Path
if (-not $runDir.StartsWith($resolvedOut, [StringComparison]::OrdinalIgnoreCase)) { throw "Run path escaped ignored output: $runDir" }
Push-Location $runDir
try {
    & (Join-Path $modelsimBin 'vlib.exe') work *> vlib.log
    if ($LASTEXITCODE -ne 0) { throw "vlib failed: $LASTEXITCODE" }
    & (Join-Path $modelsimBin 'vcom.exe') -2008 -work work (Join-Path $repoRoot 'modules\pia\pia6821.vhd') *> vcom.log
    if ($LASTEXITCODE -ne 0) { throw "vcom failed: $LASTEXITCODE; see $runDir\vcom.log" }
    $vlogArgs = @('-work','work')
    if ($Production) {
        $prodText = Get-Content -Raw (Join-Path $repoRoot 'rtl\pia_return.v')
        foreach ($required in @('audio_notify','main_notify','overflow')) {
            if ($prodText -notmatch [regex]::Escape($required)) {
                throw "-Production requires the promoted FIFO interface in rtl/pia_return.v (missing $required); legacy exidyPiaReturn is intentionally unsupported."
            }
        }
        $vlogArgs += '+define+PIA_PRODUCTION'
        $vlogArgs += (Join-Path $repoRoot 'rtl\pia_return.v')
    } else {
        $vlogArgs += (Join-Path $repoRoot 'candidates\timing\pia_return_fifo.v')
    }
    $vlogArgs += (Join-Path $repoRoot 'candidates\timing\pia_return_mailbox.v')
    $vlogArgs += (Join-Path $PSScriptRoot 'tb_pia_return_mailbox.sv')
    $vlogArgs += (Join-Path $PSScriptRoot 'tb_pia_fifo_stream.sv')
    & (Join-Path $modelsimBin 'vlog.exe') @vlogArgs *> vlog.log
    if ($LASTEXITCODE -ne 0) { throw "vlog failed: $LASTEXITCODE; see $runDir\vlog.log" }
    $summary = @()
    $kinds = if ($Production) { @(1) } else { @(0,1) }
    foreach ($kind in $kinds) {
        $tag = if ($kind -eq 0) { 'snapshot' } elseif ($Production) { 'production' } else { 'fifo' }
        foreach ($shift in @(0,500)) {
            foreach ($phase in 0..6) {
                $log = "vsim-$tag-phase-$phase-shift-$shift.log"
                & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_pia_return_mailbox "-gPHASE_NS=$phase" "-gSHIFT_PS=$shift" "-gUSE_FIFO=$kind" -do 'run -all; quit -f' *> $log
                if ($LASTEXITCODE -ne 0) { throw "vsim $tag phase $phase shift $shift failed: $LASTEXITCODE; see $runDir\$log" }
                $pass = Select-String -LiteralPath (Join-Path $runDir $log) -SimpleMatch 'PASS actual paired pia6821 +' | Select-Object -First 1
                if ($null -eq $pass) { throw "$tag phase $phase shift $shift exited without PASS marker; see $runDir\$log" }
                $summary += $pass.Line.Trim()
            }
        }
        # Probe one picosecond on either side of the coincident edge at phase 6.
        if ($kind -eq 1) {
            foreach ($shift in @(499,501)) {
                $phase = 6
                $log = "vsim-$tag-phase-$phase-shift-$shift.log"
                & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_pia_return_mailbox "-gPHASE_NS=$phase" "-gSHIFT_PS=$shift" "-gUSE_FIFO=$kind" -do 'run -all; quit -f' *> $log
                if ($LASTEXITCODE -ne 0) { throw "vsim $tag phase $phase shift $shift failed: $LASTEXITCODE; see $runDir\$log" }
                $pass = Select-String -LiteralPath (Join-Path $runDir $log) -SimpleMatch 'PASS actual paired pia6821 +' | Select-Object -First 1
                if ($null -eq $pass) { throw "$tag phase $phase shift $shift exited without PASS marker; see $runDir\$log" }
                $summary += $pass.Line.Trim()
            }
        }
    }
    # The saturating stream always tests the FIFO (or promoted production FIFO),
    # so run it once per phase/shift rather than once for every paired case.
    $streamTag = if ($Production) { 'production' } else { 'fifo' }
    foreach ($shift in @(0,500)) {
        foreach ($phase in 0..6) {
            $streamLog = "vsim-$streamTag-stream-phase-$phase-shift-$shift.log"
            & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_pia_fifo_stream "-gPHASE_NS=$phase" "-gSHIFT_PS=$shift" -do 'run -all; quit -f' *> $streamLog
            if ($LASTEXITCODE -ne 0) { throw "stream $streamTag phase $phase shift $shift failed: $LASTEXITCODE; see $runDir\$streamLog" }
            $streamPass = Select-String -LiteralPath (Join-Path $runDir $streamLog) -SimpleMatch 'PASS FIFO saturated stream' | Select-Object -First 1
            if ($null -eq $streamPass) { throw "stream $streamTag phase $phase shift $shift exited without PASS marker; see $runDir\$streamLog" }
            $summary += $streamPass.Line.Trim()
        }
    }
    foreach ($shift in @(499,501)) {
        $phase = 6
        $streamLog = "vsim-$streamTag-stream-phase-$phase-shift-$shift.log"
        & (Join-Path $modelsimBin 'vsim.exe') -c -lib work work.tb_pia_fifo_stream "-gPHASE_NS=$phase" "-gSHIFT_PS=$shift" -do 'run -all; quit -f' *> $streamLog
        if ($LASTEXITCODE -ne 0) { throw "stream $streamTag phase $phase shift $shift failed: $LASTEXITCODE; see $runDir\$streamLog" }
        $streamPass = Select-String -LiteralPath (Join-Path $runDir $streamLog) -SimpleMatch 'PASS FIFO saturated stream' | Select-Object -First 1
        if ($null -eq $streamPass) { throw "stream $streamTag phase $phase shift $shift exited without PASS marker; see $runDir\$streamLog" }
        $summary += $streamPass.Line.Trim()
      }
    $summary
    "Logs: $runDir"
}
finally { Pop-Location }
