$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modelsim='C:\MiSTerDev\intelFPGA_lite\17.0\modelsim_ase\win32aloem'
$pll=Get-Content (Join-Path $repo 'sys\pll_cfg\altera_pll_reconfig_core.v') -Raw
if($pll -notmatch '(?s)usr_m_cnt_lo\s*<=\s*slave_writedata\[7:0\].*?usr_m_cnt_hi\s*<=\s*slave_writedata\[15:8\].*?usr_m_cnt_bypass_en\s*<=\s*slave_writedata\[16\].*?usr_m_cnt_odd_duty_div_en\s*<=\s*slave_writedata\[17\]') { throw 'PLL M register packing guard failed' }
if($pll -notmatch '(?s)usr_c_cnt_lo\s*<=\s*slave_writedata\[7:0\].*?usr_c_cnt_hi\s*<=\s*slave_writedata\[15:8\].*?usr_c_cnt_bypass_en\s*<=\s*slave_writedata\[16\].*?usr_c_cnt_odd_duty_div_en\s*<=\s*slave_writedata\[17\].*?usr_cnt_sel\s*<=\s*slave_writedata\[22:18\]') { throw 'PLL C register packing guard failed' }
$out=Join-Path $repo 'simulation\exidy_output_control'
New-Item -ItemType Directory -Force $out | Out-Null
$run=Join-Path $out ('run-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory $run | Out-Null
$sources=[ordered]@{
  controller=Join-Path $repo 'candidates\video\exidy_output_control.sv'
  fixture=Join-Path $PSScriptRoot 'tb_exidy_output_control.sv'
  pllRegisterSource=Join-Path $repo 'sys\pll_cfg\altera_pll_reconfig_core.v'
}
$audit=[ordered]@{
  purpose='Isolated reconfigurable-output-PLL controller candidate; not production integration or silicon validation.'
  testedModes='Native M128/C32 and CRT M131/C35; N=1, source is the fixed native master/4 clock, no fractional K.'
  registerPacking='M address4: lo[7:0], hi[15:8], bypass[16], odd[17]; C address5 adds selector[22:18]; START address2 data1.'
  expectedWords=@('native M 0x00004040','native C0 0x00001010','CRT M 0x00024241','CRT C0 0x00021211')
  exercised=@('pre-acceptance waitrequest stalls','M/C accepted-write guard gaps of at least 256 clocks','START busy/done handshake','startup blank and configuration','two-frame output warmup','user reset preserves selected mode','lock-loss blank and lock-recovery warmup','bypass and odd-duty bits')
  sha256=[ordered]@{}
}
foreach($item in $sources.GetEnumerator()){$audit.sha256[$item.Key]=(Get-FileHash -LiteralPath $item.Value -Algorithm SHA256).Hash}
$audit | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'source-audit.json') -Encoding utf8
Push-Location $run
try {
  & (Join-Path $modelsim 'vlib.exe') work *> vlib.log
  & (Join-Path $modelsim 'vlog.exe') -sv -work work (Join-Path $repo 'candidates\video\exidy_output_control.sv') (Join-Path $PSScriptRoot 'tb_exidy_output_control.sv') *> vlog.log
  if($LASTEXITCODE){throw "vlog failed: $run\vlog.log"}
  & (Join-Path $modelsim 'vsim.exe') -c -lib work work.tb_exidy_output_control -do 'run -all; quit -f' *> vsim.log
  if($LASTEXITCODE){throw "vsim failed: $run\vsim.log"}
  $pass=Select-String -LiteralPath (Join-Path $run 'vsim.log') -SimpleMatch 'PASS output controller' | Select-Object -First 1
  if($null -eq $pass){throw "Simulation did not report PASS: $run\vsim.log"}
  $pass.Line.Trim()
  "Logs: $run"
} finally {Pop-Location}
