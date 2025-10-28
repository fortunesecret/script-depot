# Test script for init.ps1
# This script tests the functionality of init.ps1 by creating test projects and verifying them

# Parameters for customization
param(
    [switch]$Verbose = $false,
    [switch]$KeepTestDir = $false,
    [switch]$BuildAndRun = $false
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Define colors for output
$successColor = "Green"
$failureColor = "Red"
$infoColor = "Cyan"
$warningColor = "Yellow"

# Test results tracking
$testResults = @()

function Write-TestInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor $infoColor
}

function Write-TestSuccess {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $successColor
    $script:testResults += @{Result = "Success"; Message = $Message}
}

function Write-TestFailure {
    param([string]$Message, [string]$Details = "")
    Write-Host "[FAILURE] $Message" -ForegroundColor $failureColor
    if ($Details) {
        Write-Host "         $Details" -ForegroundColor $failureColor
    }
    $script:testResults += @{Result = "Failure"; Message = $Message; Details = $Details}
}

function Write-TestWarning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $warningColor
}

function Test-ProjectCreation {
    param(
        [string]$ProjectName,
        [switch]$UseTypeScript,
        [string]$TestDir,
        [string[]]$ExtraDependencies = @(),
        [switch]$BuildAndRun = $false
    )
    
    $projectType = if ($UseTypeScript) { "TypeScript" } else { "JavaScript" }
    
    Write-TestInfo "Creating $projectType project: $ProjectName"
    
    # Run the init script
    try {
        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "init.ps1"
        
        # Build parameters as a hashtable instead of a string command
        $params = @{
            ProjectName = $ProjectName
            BaseDirectory = $TestDir
        }
        
        # Only add UseTypeScript if it's false (since true is default)
        if (-not $UseTypeScript) {
            $params.Add("UseTypeScript", $false)
        }
        
        # Add extra dependencies if specified
        if ($ExtraDependencies.Count -gt 0) {
            $params.Add("ExtraDependencies", $ExtraDependencies)
        }
        
        if ($Verbose) {
            $paramsString = ($params.GetEnumerator() | ForEach-Object { "-$($_.Key) '$($_.Value)'" }) -join " "
            Write-Host "Executing: & '$scriptPath' $paramsString" -ForegroundColor $infoColor
        }
        
        # Execute the command with splatting
        & $scriptPath @params
        
        # Verify project was created
        $projectPath = Join-Path -Path $TestDir -ChildPath $ProjectName
        
        if (-not (Test-Path $projectPath)) {
            Write-TestFailure "Project directory was not created: $projectPath"
            return $false
        }
        
        # Verify package.json exists
        $packageJsonPath = Join-Path -Path $projectPath -ChildPath "package.json"
        if (-not (Test-Path $packageJsonPath)) {
            Write-TestFailure "package.json was not created"
            return $false
        }
        
        # Verify index.html exists
        $indexPath = Join-Path -Path $projectPath -ChildPath "index.html"
        if (-not (Test-Path $indexPath)) {
            Write-TestFailure "index.html was not created"
            return $false
        }
        
        # Verify TypeScript-specific files if applicable
        if ($UseTypeScript) {
            # Check tsconfig.json
            $tsconfigPath = Join-Path -Path $projectPath -ChildPath "tsconfig.json"
            if (-not (Test-Path $tsconfigPath)) {
                Write-TestFailure "tsconfig.json was not created for TypeScript project"
                return $false
            }
            
            # Check TypeScript files
            $mainTsPath = Join-Path -Path $projectPath -ChildPath "main.ts"
            if (-not (Test-Path $mainTsPath)) {
                Write-TestFailure "main.ts was not created for TypeScript project"
                return $false
            }
        } else {
            # Check JavaScript files
            $mainJsPath = Join-Path -Path $projectPath -ChildPath "main.js"
            if (-not (Test-Path $mainJsPath)) {
                Write-TestFailure "main.js was not created for JavaScript project"
                return $false
            }
        }
        
        # Check package.json content
        $packageJson = Get-Content $packageJsonPath | ConvertFrom-Json
        
        if ($packageJson.name -ne $ProjectName) {
            Write-TestFailure "Project name in package.json does not match: Expected '$ProjectName', got '$($packageJson.name)'"
            return $false
        }
        
        # Check scripts in package.json
        if ($UseTypeScript -and -not $packageJson.scripts.build) {
            Write-TestFailure "TypeScript project missing 'build' script in package.json"
            return $false
        }
        
        # Check for extra dependencies if specified
        if ($ExtraDependencies.Count -gt 0) {
            $dependenciesFound = $true
            foreach ($dep in $ExtraDependencies) {
                $depFound = $false
                
                # Check in regular dependencies
                if ($packageJson.dependencies -and $packageJson.dependencies.PSObject.Properties.Name -contains $dep) {
                    $depFound = $true
                }
                
                # Check in dev dependencies
                if (-not $depFound -and $packageJson.devDependencies -and $packageJson.devDependencies.PSObject.Properties.Name -contains $dep) {
                    $depFound = $true
                }
                
                if (-not $depFound) {
                    Write-TestFailure "Extra dependency '$dep' was not installed"
                    $dependenciesFound = $false
                }
            }
            
            if (-not $dependenciesFound) {
                return $false
            }
        }
        
        # Test building and running if requested
        if ($BuildAndRun) {
            Write-TestInfo "Testing build and run for $projectType project: $ProjectName"
            
            # Navigate to project directory
            Push-Location $projectPath
            
            try {
                # For TypeScript projects, we need to build first
                if ($UseTypeScript) {
                    Write-TestInfo "Building TypeScript project..."
                    $buildOutput = npm run build 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-TestFailure "Failed to build TypeScript project: $ProjectName"
                        Write-Host $buildOutput -ForegroundColor $failureColor
                        Pop-Location
                        return $false
                    }
                    
                    Write-TestSuccess "Successfully built TypeScript project: $ProjectName"
                }
                
                # Start the app with a timeout to verify it launches
                Write-TestInfo "Starting app with timeout..."
                
                # Start process but kill it after a short time
                # We're just testing if it starts without errors
                $process = Start-Process npm -ArgumentList "start" -PassThru -NoNewWindow
                
                # Wait a moment to let it initialize
                Start-Sleep -Seconds 3
                
                # Check if process is still running (good sign)
                if ($process.HasExited) {
                    $exitCode = $process.ExitCode
                    if ($exitCode -ne 0) {
                        Write-TestFailure "App process exited with code $exitCode"
                        Pop-Location
                        return $false
                    }
                }
                
                # Kill the process and any child processes
                if (-not $process.HasExited) {
                    Write-TestInfo "Terminating app process..."
                    try {
                        # First try to kill it gracefully
                        $process | Stop-Process -Force
                        
                        # Give it a moment to shut down
                        Start-Sleep -Seconds 1
                    }
                    catch {
                        Write-TestWarning "Error terminating process: $_"
                    }
                }
                
                Write-TestSuccess "App started successfully"
            }
            catch {
                Write-TestFailure "Error during build/run test: $_"
                Pop-Location
                return $false
            }
            finally {
                # Return to original directory
                Pop-Location
            }
        }
        
        Write-TestSuccess "$projectType project '$ProjectName' created successfully"
        return $true
    }
    catch {
        Write-TestFailure "Error creating $projectType project: $ProjectName" "$($_.Exception.Message)"
        return $false
    }
}

# Create test directory
$testDir = Join-Path -Path $PSScriptRoot -ChildPath "testdir"

# Clean up any existing test directory
if (Test-Path $testDir) {
    Write-TestInfo "Removing existing test directory: $testDir"
    try {
        # Try to remove the directory
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-TestWarning "Could not completely remove test directory. Some files may be locked: $($_.Exception.Message)"
        Write-TestWarning "Will proceed with testing anyway."
    }
}

# Create fresh test directory
Write-TestInfo "Creating test directory: $testDir"
New-Item -ItemType Directory -Path $testDir | Out-Null

# Store original location
$originalLocation = Get-Location

try {
    # Test TypeScript project creation
    Test-ProjectCreation -ProjectName "ts-test-project" -UseTypeScript -TestDir $testDir -BuildAndRun:$BuildAndRun
    
    # Test JavaScript project creation
    Test-ProjectCreation -ProjectName "js-test-project" -UseTypeScript:$false -TestDir $testDir -BuildAndRun:$BuildAndRun
    
    # Test TypeScript project with extra dependencies
    Test-ProjectCreation -ProjectName "ts-extra-deps" -UseTypeScript -TestDir $testDir -ExtraDependencies @("electron-store") -BuildAndRun:$BuildAndRun
    
    # Test JavaScript project with extra dependencies
    Test-ProjectCreation -ProjectName "js-extra-deps" -UseTypeScript:$false -TestDir $testDir -ExtraDependencies @("electron-store") -BuildAndRun:$BuildAndRun
    
    # Print summary
    Write-Host ""
    Write-Host "=== TEST SUMMARY ===" -ForegroundColor $infoColor
    Write-Host "Total tests: $($testResults.Count)" -ForegroundColor $infoColor
    $successCount = ($testResults | Where-Object { $_.Result -eq 'Success' } | Measure-Object).Count
    $failureCount = ($testResults | Where-Object { $_.Result -eq 'Failure' } | Measure-Object).Count
    Write-Host "Successes: $successCount" -ForegroundColor $successColor
    Write-Host "Failures: $failureCount" -ForegroundColor $failureColor
    
    # Print failures if any
    $failures = $testResults | Where-Object { $_.Result -eq 'Failure' }
    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "=== FAILURES ===" -ForegroundColor $failureColor
        foreach ($failure in $failures) {
            Write-Host "- $($failure.Message)" -ForegroundColor $failureColor
            if ($failure.Details) {
                Write-Host "  $($failure.Details)" -ForegroundColor $failureColor
            }
        }
    }
}
finally {
    # Return to original location
    Set-Location $originalLocation
    
    # Clean up test directory if not keeping it
    if (-not $KeepTestDir) {
        Write-TestInfo "Cleaning up test directory"
        
        # First ensure all Electron processes are terminated
        Write-TestInfo "Ensuring all Electron processes are terminated..."
        
        # Find and kill any electron processes that might be related to our tests
        try {
            $electronProcesses = Get-Process | Where-Object { 
                $_.Name -like "*electron*" -or 
                $_.Path -like "*$testDir*" -or 
                $_.CommandLine -like "*$testDir*" 
            } | Where-Object { $_.Id -ne $PID }
            
            if ($electronProcesses) {
                Write-TestInfo "Found $($electronProcesses.Count) Electron processes to terminate"
                foreach ($proc in $electronProcesses) {
                    Write-TestInfo "Terminating process: $($proc.Name) (ID: $($proc.Id))"
                    try {
                        $proc | Stop-Process -Force
                    } catch {
                        Write-TestWarning "Failed to terminate process $($proc.Id): $_"
                    }
                }
                
                # Give processes time to fully terminate
                Start-Sleep -Seconds 3
            } else {
                Write-TestInfo "No Electron processes found to terminate"
            }
        } catch {
            Write-TestWarning "Error while trying to terminate Electron processes: $_"
        }
        
        # Try multiple times to remove the directory (to handle locked files)
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction Stop
                $success = $true
            } catch {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-TestWarning "Cleanup attempt $retryCount failed. Waiting before retry..."
                    # Try to identify and kill any processes that might be locking files
                    try {
                        $lockingProcesses = Get-Process | Where-Object { 
                            $_.Path -like "*$testDir*" -or 
                            $_.CommandLine -like "*$testDir*" 
                        } | Where-Object { $_.Id -ne $PID }
                        
                        if ($lockingProcesses) {
                            Write-TestWarning "Found processes that might be locking files. Attempting to terminate..."
                            $lockingProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        Write-TestWarning "Error identifying locking processes: $_"
                    }
                    
                    Start-Sleep -Seconds 3
                } else {
                    Write-TestWarning "Could not completely remove test directory after $maxRetries attempts."
                    Write-TestWarning "Some files may be locked by another process: $($_.Exception.Message)"
                    Write-TestWarning "You may need to manually delete: $testDir"
                }
            }
        }
    } elseif ($KeepTestDir) {
        Write-TestInfo "Test directory kept at: $testDir"
    }
}

# Return overall success/failure
$failureCount = ($testResults | Where-Object { $_.Result -eq 'Failure' } | Measure-Object).Count
if ($failureCount -gt 0) {
    Write-Host ""
    Write-Host "❌ Tests completed with $failureCount failures" -ForegroundColor $failureColor
    exit 1
} else {
    Write-Host ""
    Write-Host "✅ All tests passed successfully!" -ForegroundColor $successColor
    exit 0
}
