# Script to run Compare-Monitors.ps1 on a specific directory
$runDir = "C:\Users\wille\WifiSuite\20251101-121027"

# Check if the directory exists
Write-Host "Checking if directory exists: $runDir"
if (Test-Path $runDir) {
    Write-Host "Directory exists!" -ForegroundColor Green
    
    # Check if the required files exist
    $preCsv = Join-Path $runDir "pre-monitor.csv"
    $postCsv = Join-Path $runDir "post-monitor.csv"
    
    if (Test-Path $preCsv) {
        Write-Host "Pre-monitor CSV exists: $preCsv" -ForegroundColor Green
    } else {
        Write-Host "Pre-monitor CSV does not exist: $preCsv" -ForegroundColor Red
    }
    
    if (Test-Path $postCsv) {
        Write-Host "Post-monitor CSV exists: $postCsv" -ForegroundColor Green
    } else {
        Write-Host "Post-monitor CSV does not exist: $postCsv" -ForegroundColor Red
    }
    
    # Run Compare-Monitors.ps1
    Write-Host "Running Compare-Monitors.ps1..." -ForegroundColor Yellow
    $comparePath = Join-Path $PSScriptRoot "Compare-Monitors.ps1"
    & $comparePath -RunDir $runDir
    
    # Check if the HTML report was generated
    $htmlPath = Join-Path $runDir "compare-report.html"
    if (Test-Path $htmlPath) {
        Write-Host "HTML report generated: $htmlPath" -ForegroundColor Green
        Start-Process $htmlPath
    } else {
        Write-Host "HTML report was not generated: $htmlPath" -ForegroundColor Red
    }
} else {
    Write-Host "Directory does not exist: $runDir" -ForegroundColor Red
}
