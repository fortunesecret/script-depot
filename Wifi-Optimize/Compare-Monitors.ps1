<#
.SYNOPSIS
  Compare two Wi-Fi monitor CSVs (pre vs post), print deltas, and emit JSON + HTML reports.
  If called with no params, auto-picks the latest run under $HOME\WifiSuite that has both CSVs.

.DESCRIPTION
  - Reads monitor CSVs produced by Diagnose-Wifi.ps1 (pre-monitor.csv/post-monitor.csv)
  - Summarizes time window, signal avg/min/max, loss %, avg latency, longest fail streak
  - Writes:
      compare-report.json
      compare-report.html  (standalone: inline CSS + JS, no external dependencies)

.PARAMETER RunDir
  Directory that contains pre/post CSVs (pre-monitor.csv + post-monitor.csv).
  Optional; if omitted we auto-select the most recent valid run under $HOME\WifiSuite.

.EXAMPLES
  .\Compare-Monitors.ps1
  .\Compare-Monitors.ps1 -RunDir "$HOME\WifiSuite\20251101-104750"
#>
[CmdletBinding()]
param(
  [string]$RunDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import modules
$modulesPath = Join-Path $PSScriptRoot "Modules"
$moduleFiles = @(
    "WifiUtils.psm1",
    "WifiDataProcessing.psm1",
    "HtmlTemplates.psm1"
)

foreach ($module in $moduleFiles) {
    $modulePath = Join-Path $modulesPath $module
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    } else {
        Write-Host "[ERROR] Module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
}

function Resolve-LatestRun([string]$root) {
  if (-not (Test-Path $root)) { return $null }
  $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  foreach ($d in $dirs) {
    $pre  = Join-Path $d.FullName "pre-monitor.csv"
    $post = Join-Path $d.FullName "post-monitor.csv"
    if ((Test-Path $pre) -and (Test-Path $post)) {
      return @{ Pre=$pre; Post=$post; OutDir=$d.FullName }
    }
  }
  return $null
}

function Resolve-Inputs([string]$RunDir) {
  if ($RunDir) {
    $pre  = Join-Path $RunDir "pre-monitor.csv"
    $post = Join-Path $RunDir "post-monitor.csv"
    if (-not (Test-Path $pre))  { throw "Could not find $pre" }
    if (-not (Test-Path $post)) { throw "Could not find $post" }
    return @{ Pre=$pre; Post=$post; OutDir=$RunDir }
  }
  $root   = Join-Path $HOME "WifiSuite"
  $latest = Resolve-LatestRun -root $root
  if ($latest) { return $latest }
  throw "No inputs. Provide -RunDir or ensure $root contains a run with pre/post CSVs."
}

function Emit-Html([string]$OutPath, $preSumm, $postSumm, $delta, $preChart, $postChart) {
  $html = Get-CompareReportHtml -preSumm $preSumm -postSumm $postSumm -delta $delta -preChart $preChart -postChart $postChart
  
  # Ensure directory exists
  $dir = Split-Path -Parent $OutPath
  if (-not (Test-Path $dir)) {
    $oldWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $WhatIfPreference = $oldWhatIf
  }
  
  # Save the file
  $oldWhatIf = $WhatIfPreference
  $WhatIfPreference = $false
  $html | Set-Content -Path $OutPath -Encoding UTF8
  $WhatIfPreference = $oldWhatIf
}

# ---------------- Main ----------------
$paths    = Resolve-Inputs -RunDir $RunDir
$preRows  = @((Import-CsvSafe -Path $paths.Pre))
$postRows = @((Import-CsvSafe -Path $paths.Post))

$preSumm  = Get-CaptureSummary -Rows $preRows
$postSumm = Get-CaptureSummary -Rows $postRows
$delta    = Get-DeltaReport -PreSumm $preSumm -PostSumm $postSumm

Write-Host "`n=== Compare-Monitors ===`n" -ForegroundColor Cyan
Write-Host ("Pre:  {0} -> {1}  (samples={2}, duration={3}s)" -f $preSumm.start, $preSumm.end, $preSumm.samples, $preSumm.durationSec)
Write-Host ("Post: {0} -> {1}  (samples={2}, duration={3}s)`n" -f $postSumm.start, $postSumm.end, $postSumm.samples, $postSumm.durationSec)

function Print-Block($title, $pre, $post) {
  Write-Host ("-- {0} --" -f $title) -ForegroundColor Yellow
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal avg %", $pre.signal.avg, $post.signal.avg, ($post.signal.avg - $pre.signal.avg))
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal min %", $pre.signal.min, $post.signal.min, ($post.signal.min - $pre.signal.min))
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal max %", $pre.signal.max, $post.signal.max, ($post.signal.max - $pre.signal.max))
  Write-Host ""
}
Print-Block "Signal" $preSumm $postSumm

Write-Host "-- Local (192.168.1.1) --" -ForegroundColor Yellow
("{0,-18} {1,8}% -> {2,-8}% (Delta {3}%)" -f "Loss", $preSumm.local.lossPct, $postSumm.local.lossPct, ($postSumm.local.lossPct - $preSumm.local.lossPct))
("{0,-18} {1,8}ms -> {2,-8}ms (Delta {3}ms)" -f "Avg latency", $preSumm.local.avgMs, $postSumm.local.avgMs, ($postSumm.local.avgMs - $preSumm.local.avgMs))
("{0,-18} {1,8}  -> {2,-8}  (Delta {3})" -f "Longest streak", $preSumm.local.longestFail, $postSumm.local.longestFail, ($postSumm.local.longestFail - $preSumm.local.longestFail))
Write-Host ""

Write-Host "-- Upstream (8.8.8.8) --" -ForegroundColor Yellow
("{0,-18} {1,8}% -> {2,-8}% (Delta {3}%)" -f "Loss", $preSumm.upstream.lossPct, $postSumm.upstream.lossPct, ($postSumm.upstream.lossPct - $preSumm.upstream.lossPct))
("{0,-18} {1,8}ms -> {2,-8}ms (Delta {3}ms)" -f "Avg latency", $preSumm.upstream.avgMs, $postSumm.upstream.avgMs, ($postSumm.upstream.avgMs - $preSumm.upstream.avgMs))
("{0,-18}  {1,6} -> {2,-6}  (Delta {3})" -f "Longest streak", $preSumm.upstream.longestFail, $postSumm.upstream.longestFail, ($postSumm.upstream.longestFail - $preSumm.upstream.longestFail))
Write-Host ""

$verdict = Get-Verdict -pre $preSumm -post $postSumm
Write-Host ("Verdict: {0}" -f $verdict) -ForegroundColor Green

# Outputs
$outJson = Join-Path $paths.OutDir "compare-report.json"
# Ensure directory exists
$jsonDir = Split-Path -Parent $outJson
if (-not (Test-Path $jsonDir)) {
  $oldWhatIf = $WhatIfPreference
  $WhatIfPreference = $false
  New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
  $WhatIfPreference = $oldWhatIf
}

# Save the file
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
$delta | ConvertTo-Json -Depth 6 | Set-Content -Path $outJson -Encoding UTF8
$WhatIfPreference = $oldWhatIf
Write-Info ("JSON report written: {0}" -f $outJson)

# Build chart data + HTML
$preChart  = Get-ChartData -rows $preRows
$postChart = Get-ChartData -rows $postRows
$outHtml = Join-Path $paths.OutDir "compare-report.html"
Emit-Html -OutPath $outHtml -preSumm $preSumm -postSumm $postSumm -delta $delta -preChart $preChart -postChart $postChart
Write-Info ("HTML report written: {0}" -f $outHtml)
