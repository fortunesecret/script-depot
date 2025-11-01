# Simple script to check if a directory exists
$runDir = "C:\Users\wille\WifiSuite\20251101-121027"
Write-Host "Checking if directory exists: $runDir"
if (Test-Path -Path $runDir) {
    Write-Host "Directory exists!" -ForegroundColor Green
    
    # List the contents of the directory
    Write-Host "Directory contents:"
    Get-ChildItem -Path $runDir | ForEach-Object {
        Write-Host "  $($_.Name)"
    }
} else {
    Write-Host "Directory does not exist!" -ForegroundColor Red
}
