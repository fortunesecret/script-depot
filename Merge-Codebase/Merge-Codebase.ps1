<#
.SYNOPSIS
  Merge project files into a single text snapshot for quick review. PS 5.1-compatible.

.DESCRIPTION
  - Generic: start at a configurable root and scan whole tree unless narrowed.
  - Excludes by directory name and glob.
  - Force-include globs override excludes.
  - Config file: merge.config.json next to the script (overridable via -ConfigPath).
#>

[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "merge.config.json"),
  [switch]$InitConfig,
  [string]$Root,           # if not supplied, falls back to config.root or current dir
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
function Write-Log([string]$msg) { Write-Host "[merge] $msg" }

# ---------- Helpers: JSON to hashtable (PS 5.1 safe) ----------
function ConvertTo-Hashtable {
  param([Parameter(Mandatory)][object]$InputObject)
  if ($null -eq $InputObject) { return $null }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $ht = @{}
    foreach ($k in $InputObject.Keys) { $ht[$k] = ConvertTo-Hashtable -InputObject $InputObject[$k] }
    return $ht
  }

  if ($InputObject -is [PSCustomObject]) {
    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) { $ht[$prop.Name] = ConvertTo-Hashtable -InputObject $prop.Value }
    return $ht
  }

  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $list = @()
    foreach ($item in $InputObject) { $list += ,(ConvertTo-Hashtable -InputObject $item) }
    return $list
  }

  return $InputObject
}

function Merge-Hashtable {
  param([hashtable]$Base, [hashtable]$Override)
  $result = @{}
  foreach ($k in $Base.Keys) { $result[$k] = $Base[$k] }
  foreach ($k in $Override.Keys) {
    if ($result.ContainsKey($k) -and ($result[$k] -is [hashtable]) -and ($Override[$k] -is [hashtable])) {
      $result[$k] = Merge-Hashtable -Base $result[$k] -Override $Override[$k]
    } else {
      $result[$k] = $Override[$k]
    }
  }
  return $result
}

# ---------- Defaults (generic) ----------
$DefaultConfig = @{
  root = ""  # optional; if empty, current directory is used (or -Root param overrides)
  output = @{
    directory = "."
    filename  = "merged-codebase.txt"
    encoding  = "utf8"       # utf8, utf8BOM, ascii, unicode, utf32
    headerBar = "=========="
    showGeneratedTimestamp = $true
  }
  # What to scan (empty => scan whole root; all extensions)
  scan = @{
    directories = @()        # e.g., ["src","app"]; empty => whole root
    extensions  = @()        # e.g., ["*.ts","*.cs"]; empty => include all files
  }
  # Explicit files relative to root to add *first* (optional)
  rootFiles = @(
    "package.json","README.md",".gitignore","tsconfig.json","vite.config.ts","vite.config.mts",
    "electron-builder.yml","electron-builder.yaml","env.d.ts"
  )
  excludes = @{
    directoryNames = @("node_modules","dist","dist-electron","dist-build","build",".git",".turbo",".next",".vite",".cache","out")
    globs = @(
      "coverage/**","**/*.map","**/*.min.*","**/.DS_Store","**/Thumbs.db",
      "**/*.png","**/*.jpg","**/*.jpeg","**/*.gif","**/*.webp","**/*.svg","**/*.ico",
      "**/*.pdf","**/*.zip","**/*.7z","**/*.rar","**/*.exe","**/*.dll","**/*.so","**/*.a","**/*.wasm",
      "package-lock.json","yarn.lock","pnpm-lock.yaml","bun.lockb"
    )
  }
  # Files you ALWAYS want included, even if excluded by the above
  forceInclude = @{
    globs = @()  # e.g., ["**/*.md","docs/**"]
  }
  behavior = @{
    followSymlinks   = $false
    maxFileSizeKB    = 1024
    detectBinary     = $true
    sortMode         = "path" # path | none
    addSectionSpacer = $true
    newLine          = "CRLF" # CRLF | LF
  }
}

# ---------- Init config ----------
if ($InitConfig) {
  if (Test-Path $ConfigPath) {
    Write-Log "Config already exists at '$ConfigPath'. Not overwriting."
  } else {
    $DefaultConfig | ConvertTo-Json -Depth 8 | Out-File -FilePath $ConfigPath -Encoding utf8
    Write-Log "Wrote default config to '$ConfigPath'."
  }
  return
}

# ---------- Load config ----------
$config = $DefaultConfig
if (Test-Path $ConfigPath) {
  Write-Log "Using config: $ConfigPath"
  $raw = Get-Content -Path $ConfigPath -Raw
  $userCfgObj = $raw | ConvertFrom-Json
  $userCfg = ConvertTo-Hashtable -InputObject $userCfgObj
  $config = Merge-Hashtable -Base $config -Override $userCfg
} else {
  Write-Log "No config found at '$ConfigPath'. Using built-in defaults."
}

# ---------- Resolve root ----------
$rootCandidate = if ($PSBoundParameters.ContainsKey('Root') -and $Root) { $Root } elseif ($config.root) { $config.root } else { (Get-Location).Path }
$rootFull = (Resolve-Path -LiteralPath $rootCandidate).Path
Write-Log "Root: $rootFull"

# ---------- Misc setup ----------
$nl = if ($config.behavior.newLine -eq "LF") { "`n" } else { "`r`n" }
$encMap = @{ "utf8"="utf8"; "utf8bom"="utf8BOM"; "ascii"="ascii"; "unicode"="unicode"; "utf32"="utf32" }
$encodingKey = [string]$config.output.encoding
if ([string]::IsNullOrWhiteSpace($encodingKey)) { $encodingKey = "utf8" } else { $encodingKey = $encodingKey.ToLower() }
$encoding = $encMap[$encodingKey]; if (-not $encoding) { $encoding = "utf8" }

$outDir = if ([IO.Path]::IsPathRooted($config.output.directory)) { $config.output.directory } else { Join-Path $rootFull $config.output.directory }
$outFile = Join-Path $outDir $config.output.filename
if (-not (Test-Path $outDir)) { if ($WhatIf) { Write-Log "Would create directory: $outDir" } else { New-Item -ItemType Directory -Force -Path $outDir | Out-Null } }
if (Test-Path $outFile) { if ($WhatIf) { Write-Log "Would remove existing: $outFile" } else { Remove-Item -Path $outFile -Force } }

# ---------- Path helpers ----------
function Get-RelativePath([string]$fullPath, [string]$rootPath) {
  $rootFixed = ($rootPath.TrimEnd('\','/')) + '\'
  $uRoot = New-Object System.Uri $rootFixed
  $uFull = New-Object System.Uri $fullPath
  $rel = $uRoot.MakeRelativeUri($uFull).ToString()
  return ($rel -replace '/','\')
}

# ---------- Exclusion/force-include logic ----------
$globExcludePatterns = @()
foreach ($g in $config.excludes.globs) {
  $globExcludePatterns += [System.Management.Automation.WildcardPattern]::new($g, [System.Management.Automation.WildcardOptions]::IgnoreCase)
}
$globForcePatterns = @()
foreach ($g in $config.forceInclude.globs) {
  $globForcePatterns += [System.Management.Automation.WildcardPattern]::new($g, [System.Management.Automation.WildcardOptions]::IgnoreCase)
}

function Is-ExcludedByDirName([string]$fullPath, [string[]]$dirNames) {
    $parts = $fullPath.TrimEnd('\','/').Split(@('\','/'))
    foreach ($p in $parts) {
        if ($dirNames -contains $p) { return $true }
    }
    return $false
}

function Match-AnyGlob([string]$relPath, $patterns) {
  $unixRel = $relPath -replace '\\','/'
  foreach ($pat in $patterns) { if ($pat.IsMatch($unixRel)) { return $true } }
  return $false
}

function Should-IncludeFile([IO.FileInfo]$file) {
  $rel = Get-RelativePath $file.FullName $rootFull

  # Force-include overrides everything
  if (Match-AnyGlob -relPath $rel -patterns $globForcePatterns) { return $true }

  # Exclude by directory names
  if (Is-ExcludedByDirName -fullPath $file.FullName -dirNames $config.excludes.directoryNames) { return $false }

  # Exclude by glob
  if (Match-AnyGlob -relPath $rel -patterns $globExcludePatterns) { return $false }

  # Size limit
  if ($config.behavior.maxFileSizeKB -gt 0) {
    $maxB = [int64]$config.behavior.maxFileSizeKB * 1024
    if ($file.Length -gt $maxB) { return $false }
  }

  # Binary detection (first 64KB)
  if ($config.behavior.detectBinary) {
    try {
      $fs = [IO.File]::OpenRead($file.FullName)
      try {
        $buf = New-Object byte[] 65536
        $read = $fs.Read($buf, 0, $buf.Length)
        for ($i = 0; $i -lt $read; $i++) { if ($buf[$i] -eq 0) { return $false } }
      } finally { $fs.Dispose() }
    } catch { return $false }
  }

  return $true
}

function Write-Line([string]$text) { if (-not $WhatIf) { $text | Out-File -FilePath $outFile -Encoding $encoding -Append } }
function Write-Header([string]$text) { $bar = $config.output.headerBar; Write-Line "$bar $text $bar" }
function Add-File([string]$fullPath) {
  $rel = Get-RelativePath $fullPath $rootFull
  Write-Header ("FILE: " + $rel)
  if ($config.behavior.addSectionSpacer) { Write-Line "" }
  if ($WhatIf) { return }
  try { Write-Line (Get-Content -Path $fullPath -Raw -ErrorAction Stop) } catch { Write-Log "Skipping unreadable file: $rel ($($_.Exception.Message))" }
  if ($config.behavior.addSectionSpacer) { Write-Line "" }
}

# ---------- Banner ----------
$ts = Get-Date
if (-not $WhatIf -and $config.output.showGeneratedTimestamp) {
  Write-Header "MERGED CODEBASE SNAPSHOT"
  Write-Line ("Generated on: " + $ts.ToString("yyyy-MM-dd HH:mm:ss K"))
  Write-Line ""
} elseif ($WhatIf) {
  Write-Log "Dry-run enabled. No output will be written."
}

# ---------- Collect candidates ----------
# Roots to scan: either explicit subdirs or the root itself
$scanDirs = @()
if ($config.scan.directories -and $config.scan.directories.Count -gt 0) {
  foreach ($d in $config.scan.directories) {
    $p = Join-Path $rootFull $d
    if (Test-Path -LiteralPath $p -PathType Container) { $scanDirs += $p }
  }
} else {
  $scanDirs = @($rootFull)
}

# Baseline collection
$collected = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($base in $scanDirs) {
  # Recurse everything and filter later; -Include has quirks in PS 5.1
  $items = Get-ChildItem -LiteralPath $base -Recurse -Force -File -ErrorAction SilentlyContinue
  foreach ($it in $items) {
    if (-not $config.behavior.followSymlinks) { if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue } }
    $collected.Add($it)
  }
}

# Filter by extensions if provided
if ($config.scan.extensions -and $config.scan.extensions.Count -gt 0) {
  $extSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  foreach ($pat in $config.scan.extensions) {
    # Support patterns like *.ts; extract extension part when possible
    if ($pat -match '\*\.(.+)$') { [void]$extSet.Add("." + $Matches[1]) }
  }
  if ($extSet.Count -gt 0) {
    $collected = $collected | Where-Object { $extSet.Contains($_.Extension) }
  }
}

# Apply include/exclude + force-include logic
$final = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($f in ($collected | Sort-Object FullName -Unique)) {
  if (Should-IncludeFile $f) { $final.Add($f) }
}

# Exclude the output file itself if it appears
$resolvedOut = if (Test-Path -LiteralPath $outFile) { (Resolve-Path -LiteralPath $outFile).Path } else { $outFile }
$final = $final | Where-Object { $_.FullName -ne $resolvedOut }

# Sort mode
if ($config.behavior.sortMode -eq "path") { $final = $final | Sort-Object FullName }

# Write files
foreach ($f in $final) {
  $rel = Get-RelativePath $f.FullName $rootFull
  Write-Log "Include: $rel"
  Add-File -fullPath $f.FullName
}

if ($WhatIf) { Write-Log "Dry-run complete." } else { Write-Log "Merged file created: $outFile" }
