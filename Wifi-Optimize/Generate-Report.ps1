# Script to generate a report for a specific run directory
[CmdletBinding()]
param(
    [string]$RunDir
)

# Display the parameters
Write-Host "Parameters:" -ForegroundColor Cyan
Write-Host "  RunDir: $RunDir"

# Import the modules
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

# If no RunDir is specified, find the latest run
if (-not $RunDir) {
    $wifiSuiteDir = Join-Path $HOME "WifiSuite"
    if (-not (Test-Path $wifiSuiteDir)) {
        Write-Host "WifiSuite directory does not exist: $wifiSuiteDir" -ForegroundColor Red
        exit 1
    }
    
    # Find the latest run directory that has both pre and post monitor CSVs
    $runDirs = Get-ChildItem -Path $wifiSuiteDir -Directory | Sort-Object LastWriteTime -Descending
    $foundDir = $false
    
    foreach ($dir in $runDirs) {
        $preCsvPath = Join-Path $dir.FullName "pre-monitor.csv"
        $postCsvPath = Join-Path $dir.FullName "post-monitor.csv"
        
        if ((Test-Path $preCsvPath) -and (Test-Path $postCsvPath)) {
            $RunDir = $dir.FullName
            $foundDir = $true
            Write-Host "Found latest run directory: $RunDir" -ForegroundColor Green
            break
        }
    }
    
    if (-not $foundDir) {
        Write-Host "No run directories found with both pre and post monitor CSVs" -ForegroundColor Red
        exit 1
    }
} else {
    # Check if the specified directory exists
    if (-not (Test-Path $RunDir)) {
        Write-Host "Directory does not exist: $RunDir" -ForegroundColor Red
        exit 1
    }
}

# Check if the required files exist
$preCsvPath = Join-Path $RunDir "pre-monitor.csv"
$postCsvPath = Join-Path $RunDir "post-monitor.csv"

if (-not (Test-Path $preCsvPath)) {
    Write-Host "Pre-monitor CSV does not exist: $preCsvPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $postCsvPath)) {
    Write-Host "Post-monitor CSV does not exist: $postCsvPath" -ForegroundColor Red
    exit 1
}

# Load the CSV files
$preRows = @((Import-CsvSafe -Path $preCsvPath))
$postRows = @((Import-CsvSafe -Path $postCsvPath))

# Generate the summaries
$preSumm = Get-CaptureSummary -Rows $preRows
$postSumm = Get-CaptureSummary -Rows $postRows
$delta = Get-DeltaReport -PreSumm $preSumm -PostSumm $postSumm

# Print the summaries
Write-Host "`n=== Compare-Monitors ===`n" -ForegroundColor Cyan
Write-Host ("Pre:  {0} -> {1}  (samples={2}, duration={3}s)" -f $preSumm.start, $preSumm.end, $preSumm.samples, $preSumm.durationSec)
Write-Host ("Post: {0} -> {1}  (samples={2}, duration={3}s)`n" -f $postSumm.start, $postSumm.end, $postSumm.samples, $postSumm.durationSec)

function Write-SignalBlock($title, $pre, $post) {
  Write-Host ("-- {0} --" -f $title) -ForegroundColor Yellow
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal avg %", $pre.signal.avg, $post.signal.avg, ($post.signal.avg - $pre.signal.avg))
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal min %", $pre.signal.min, $post.signal.min, ($post.signal.min - $pre.signal.min))
  ("{0,-18} {1,8}   ->   {2,-8}   (Delta {3})" -f "Signal max %", $pre.signal.max, $post.signal.max, ($post.signal.max - $pre.signal.max))
  Write-Host ""
}
Write-SignalBlock "Signal" $preSumm $postSumm

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

# Generate the JSON report
$outJson = Join-Path $RunDir "compare-report.json"
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
$delta | ConvertTo-Json -Depth 6 | Set-Content -Path $outJson -Encoding UTF8
$WhatIfPreference = $oldWhatIf
Write-Host ("JSON report written: {0}" -f $outJson)

# Generate the HTML report
$preChart = Get-ChartData -rows $preRows
$postChart = Get-ChartData -rows $postRows
$outHtml = Join-Path $RunDir "compare-report.html"
$html = Get-CompareReportHtml -preSumm $preSumm -postSumm $postSumm -delta $delta -preChart $preChart -postChart $postChart

# Ensure directory exists
$dir = Split-Path -Parent $outHtml
if (-not (Test-Path $dir)) {
    $oldWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $WhatIfPreference = $oldWhatIf
}

# Save the HTML file
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
$html | Set-Content -Path $outHtml -Encoding UTF8
$WhatIfPreference = $oldWhatIf

Write-Host ("HTML report written: {0}" -f $outHtml)

# Open the HTML report
Start-Process $outHtml
