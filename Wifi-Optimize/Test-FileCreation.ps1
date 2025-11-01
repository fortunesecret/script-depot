# Test script to verify file creation works properly
$testDir = Join-Path $HOME "WifiSuite\TestDir"
$testFile = Join-Path $testDir "test.txt"

Write-Host "Creating directory: $testDir"
if (-not (Test-Path $testDir)) {
    $oldWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    $WhatIfPreference = $oldWhatIf
}

Write-Host "Creating file: $testFile"
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
"Test content" | Set-Content -Path $testFile -Force
$WhatIfPreference = $oldWhatIf

Write-Host "Checking if file exists: $testFile"
if (Test-Path $testFile) {
    Write-Host "File exists!" -ForegroundColor Green
    $content = Get-Content -Path $testFile
    Write-Host "Content: $content"
} else {
    Write-Host "File does not exist!" -ForegroundColor Red
}
