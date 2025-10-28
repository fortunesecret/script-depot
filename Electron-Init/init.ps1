param(
    [string]$BaseDirectory = "C:\source\repos",
    [string]$ProjectName = "my-electron-app",
    [string]$Author = "",
    [string]$Version = "0.0.1",
    [bool]$UseTypeScript = $true,
    [string[]]$ExtraDependencies = @()
)

# Create project directory in the base directory
$fullProjectPath = Join-Path -Path $BaseDirectory -ChildPath $ProjectName
New-Item -ItemType Directory -Path $fullProjectPath -Force | Out-Null
Set-Location $fullProjectPath

# Initialize npm project
npm init -y | Out-Null

# Update package.json with metadata
$packageJson = Get-Content package.json | ConvertFrom-Json
$packageJson.name = $ProjectName
$packageJson.author = $Author
$packageJson.version = $Version
if ($UseTypeScript) {
    $packageJson.main = "dist/main.js"
} else {
    $packageJson.main = "main.js"
}

# Safely replace the scripts block
$scripts = $packageJson.PSObject.Properties.Match("scripts")
if ($scripts) {
    $packageJson.PSObject.Properties.Remove("scripts")
}
if ($UseTypeScript) {
    $packageJson | Add-Member -MemberType NoteProperty -Name scripts -Value (@{
        build = "tsc"
        start = "npm run build && electron ."
    })
} else {
    $packageJson | Add-Member -MemberType NoteProperty -Name scripts -Value (@{
        start = "electron ."
    })
}

$packageJson | ConvertTo-Json -Depth 10 | Set-Content package.json

# Install core dependencies
if ($UseTypeScript) {
    Write-Host "Setting up TypeScript environment..."
    npm install --save-dev electron typescript @types/node
} else {
    Write-Host "Setting up JavaScript environment..."
    npm install --save-dev electron
}

# Install any extra dependencies passed in
if ($ExtraDependencies.Count -gt 0) {
    Write-Host "Installing additional dependencies: $($ExtraDependencies -join ', ')"
    npm install --save $ExtraDependencies
}

# Create tsconfig.json if using TypeScript
if ($UseTypeScript) {
    @"
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020", "DOM"],
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "moduleResolution": "node",
    "types": ["node", "electron"]
  },
  "include": ["*.ts"]
}
"@ | Set-Content -Encoding UTF8 "tsconfig.json"
}

# Copy boilerplate source files from script directory and interpolate variables
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent

# Select appropriate template files based on TypeScript setting
if ($UseTypeScript) {
    $templates = @("index.html", "main.ts", "preload.ts", "renderer.ts")
    $mainFile = "main.ts"
    $preloadFile = "preload.ts"
    $rendererFile = "renderer.ts"
} else {
    $templates = @("index.html", "main.js", "preload.js", "renderer.js")
    # If JS files don't exist, use TS files and rename them
    if (-not (Test-Path (Join-Path $scriptDir "main.js"))) {
        $templates = @("index.html")
        $mainFile = "main.ts"
        $preloadFile = "preload.ts"
        $rendererFile = "renderer.ts"
    } else {
        $mainFile = "main.js"
        $preloadFile = "preload.js"
        $rendererFile = "renderer.js"
    }
}

# Refresh package data after installs
$finalPackageJson = Get-Content package.json | ConvertFrom-Json
$allDependencies = @()

if ($finalPackageJson.dependencies) {
    $allDependencies += $finalPackageJson.dependencies.PSObject.Properties | ForEach-Object {
        "$_=$($finalPackageJson.dependencies[$_.Name])"
    }
}
if ($finalPackageJson.devDependencies) {
    $allDependencies += $finalPackageJson.devDependencies.PSObject.Properties | ForEach-Object {
        "$_=$($finalPackageJson.devDependencies[$_.Name]) (dev)"
    }
}

$dependencyString = "<ul>`n" + ($allDependencies | ForEach-Object {
    $name, $ver = $_ -split '='
    $name = $name.replace("string", "").replace("string ", "").Trim()
    $ver = $ver.replace("^", "Version ").Trim()
    "  <li>$name -- $ver</li>"
}) -join "`n" + "`n</ul>"

# Process HTML template first
foreach ($file in $templates) {
    $source = Join-Path $scriptDir $file
    $destination = Join-Path (Get-Location) $file

    if (Test-Path $source) {
        $content = Get-Content $source -Raw
        $content = $content -replace "\$\{ProjectName\}", $ProjectName
        $content = $content -replace "\$\{Author\}", $Author
        $content = $content -replace "\$\{Version\}", $Version
        $content = $content -replace "\$\{Dependencies\}", $dependencyString
        Set-Content -Path $destination -Value $content -Encoding UTF8
    } else {
        Write-Host "Warning: Template file '$file' not found in script directory."
    }
}

# If using JavaScript but only TypeScript templates exist, convert TS files to JS
if (-not $UseTypeScript) {
    # Process main file
    if (-not (Test-Path "main.js") -and (Test-Path (Join-Path $scriptDir $mainFile))) {
        $source = Join-Path $scriptDir $mainFile
        $content = Get-Content $source -Raw
        $content = $content -replace "\$\{ProjectName\}", $ProjectName
        $content = $content -replace "\$\{Author\}", $Author
        $content = $content -replace "\$\{Version\}", $Version
        $content = $content -replace "\$\{Dependencies\}", $dependencyString
        Set-Content -Path "main.js" -Value $content -Encoding UTF8
    }
    
    # Process preload file
    if (-not (Test-Path "preload.js") -and (Test-Path (Join-Path $scriptDir $preloadFile))) {
        $source = Join-Path $scriptDir $preloadFile
        $content = Get-Content $source -Raw
        $content = $content -replace "\$\{ProjectName\}", $ProjectName
        $content = $content -replace "\$\{Author\}", $Author
        $content = $content -replace "\$\{Version\}", $Version
        $content = $content -replace "\$\{Dependencies\}", $dependencyString
        # Convert TypeScript syntax to JavaScript
        $content = $content -replace "\: string", ""
        Set-Content -Path "preload.js" -Value $content -Encoding UTF8
    }
    
    # Process renderer file
    if (-not (Test-Path "renderer.js") -and (Test-Path (Join-Path $scriptDir $rendererFile))) {
        $source = Join-Path $scriptDir $rendererFile
        $content = Get-Content $source -Raw
        $content = $content -replace "\$\{ProjectName\}", $ProjectName
        $content = $content -replace "\$\{Author\}", $Author
        $content = $content -replace "\$\{Version\}", $Version
        $content = $content -replace "\$\{Dependencies\}", $dependencyString
        Set-Content -Path "renderer.js" -Value $content -Encoding UTF8
    }
}

if ($UseTypeScript) {
    Write-Host "TypeScript Electron project '$ProjectName' created successfully in '$fullProjectPath'."
    Write-Host "Run 'npm start' to build and launch the app."
} else {
    Write-Host "JavaScript Electron project '$ProjectName' created successfully in '$fullProjectPath'."
    Write-Host "Run 'npm start' to launch the app."
}
