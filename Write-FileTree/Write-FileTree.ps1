# Write-FileTree.ps1
<#
.SYNOPSIS
  Emit a directory tree to a file. Windows PowerShell 5.1 compatible.

.DESCRIPTION
  - Works from the current directory by default, or use -Root to override.
  - Configurable via write-filetree.config.json (next to the script) or -ConfigPath.
  - Excludes by name (supports wildcards) and/or by glob patterns.
  - Switch -NoMeta writes just the tree (no header/footer), ideal for appending
    into the merged-codebase output.
  - Switches/params override config values when provided.

.PARAMETER Root
  Root folder to tree. Default: current directory.

.PARAMETER ConfigPath
  Path to JSON config. Default: "<script folder>\write-filetree.config.json".

.PARAMETER InitConfig
  Write a default config file and exit.

.PARAMETER NoMeta
  Suppress header/footer; output only the tree body.

.PARAMETER IncludeHidden
  Include hidden/system items (overrides config).

.PARAMETER ASCII
  Use ASCII branches (+--, |) instead of Unicode (overrides config).

.PARAMETER MaxDepth
  Limit recursion depth (overrides config).

.PARAMETER Exclude
  Extra exclude name patterns (wildcards) to merge with config excludes.

.PARAMETER WhatIf
  Preview actions without writing the file.

.EXAMPLES
  .\Write-FileTree.ps1
  .\Write-FileTree.ps1 -Root C:\code\myrepo -NoMeta -ASCII
  .\Write-FileTree.ps1 -InitConfig
#>

[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "write-filetree.config.json"),
  [switch]$InitConfig,
  [string]$Root,
  [switch]$NoMeta,
  [switch]$IncludeHidden,
  [switch]$ASCII,
  [int]$MaxDepth,
  [string[]]$Exclude = @(),
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
function Write-Log([string]$m) { Write-Host "[tree] $m" }

# ---------------- JSON helpers (PS 5.1 safe) ----------------
function ConvertTo-Hashtable {
  param([Parameter(Mandatory)][object]$InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $ht = @{}; foreach ($k in $InputObject.Keys) { $ht[$k] = ConvertTo-Hashtable $InputObject[$k] }; return $ht
  }
  if ($InputObject -is [PSCustomObject]) {
    $ht = @{}; foreach ($p in $InputObject.PSObject.Properties) { $ht[$p.Name] = ConvertTo-Hashtable $p.Value }; return $ht
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $list = @(); foreach ($i in $InputObject) { $list += ,(ConvertTo-Hashtable $i) }; return $list
  }
  return $InputObject
}

function Merge-Hashtable {
  param([hashtable]$Base, [hashtable]$Override)
  $r = @{}
  foreach ($k in $Base.Keys) { $r[$k] = $Base[$k] }
  foreach ($k in $Override.Keys) {
    if ($r.ContainsKey($k) -and ($r[$k] -is [hashtable]) -and ($Override[$k] -is [hashtable])) {
      $r[$k] = Merge-Hashtable $r[$k] $Override[$k]
    } else { $r[$k] = $Override[$k] }
  }
  return $r
}

# ---------------- Defaults ----------------
$DefaultConfig = @{
  output = @{
    directory = "."              # relative to Root unless absolute
    filename  = "file_structure.txt"
    encoding  = "utf8"           # utf8, utf8BOM, ascii, unicode, utf32
    newLine   = "CRLF"           # CRLF | LF (affects our own header/lines only)
    overwrite = $true            # false => append
  }
  tree = @{
    asciiBranches   = $false     # default Unicode ├─ │ └
    includeHidden   = $false
    maxDepth        = [int]::MaxValue
    sortDirsFirst   = $true      # dirs first, then files
    showSymlinkInfo = $true      # "name -> target"
  }
  exclude = @{
    namePatterns = @('node_modules', '.git', '.vs', 'bin', 'obj', 'packages')
    globs        = @()           # e.g., ["**/dist/**","**/*.min.js"]
  }
}

# ---------------- Init config ----------------
if ($InitConfig) {
  if (Test-Path $ConfigPath) {
    Write-Log "Config already exists at '$ConfigPath'. Not overwriting."
  } else {
    $DefaultConfig | ConvertTo-Json -Depth 8 | Out-File -FilePath $ConfigPath -Encoding utf8
    Write-Log "Wrote default config to '$ConfigPath'."
  }
  return
}

# ---------------- Load config ----------------
$config = $DefaultConfig
if (Test-Path $ConfigPath) {
  Write-Log "Using config: $ConfigPath"
  $raw = Get-Content -Path $ConfigPath -Raw
  $userCfg = ConvertTo-Hashtable ($raw | ConvertFrom-Json)
  $config = Merge-Hashtable $config $userCfg
} else {
  Write-Log "No config found at '$ConfigPath'. Using built-in defaults."
}

# ---------------- Resolve Root ----------------
$rootCandidate = if ($PSBoundParameters.ContainsKey('Root') -and $Root) { $Root } else { (Get-Location).Path }
$Root = (Resolve-Path -LiteralPath $rootCandidate).Path
Write-Log "Root: $Root"

# ---------------- Apply param overrides ----------------
if ($PSBoundParameters.ContainsKey('IncludeHidden')) { $config.tree.includeHidden = [bool]$IncludeHidden }
if ($PSBoundParameters.ContainsKey('ASCII'))         { $config.tree.asciiBranches = [bool]$ASCII }
if ($PSBoundParameters.ContainsKey('MaxDepth') -and $MaxDepth) { $config.tree.maxDepth = [int]$MaxDepth }
if ($Exclude -and $Exclude.Count -gt 0) { $config.exclude.namePatterns += $Exclude }

# ---------------- Output paths & encoding ----------------
$encMap = @{ "utf8"="utf8"; "utf8bom"="utf8BOM"; "ascii"="ascii"; "unicode"="unicode"; "utf32"="utf32" }
$encKey = [string]$config.output.encoding; if ([string]::IsNullOrWhiteSpace($encKey)) { $encKey = "utf8" } else { $encKey = $encKey.ToLower() }
$encoding = $encMap[$encKey]; if (-not $encoding) { $encoding = "utf8" }
$nl = if ($config.output.newLine -eq "LF") { "`n" } else { "`r`n" }

$outDir = if ([IO.Path]::IsPathRooted($config.output.directory)) { $config.output.directory } else { Join-Path $Root $config.output.directory }
$OutFile = Join-Path $outDir $config.output.filename
if (-not (Test-Path $outDir)) { if ($WhatIf) { Write-Log "Would create $outDir" } else { New-Item -ItemType Directory -Force -Path $outDir | Out-Null } }
if ($config.output.overwrite -and (Test-Path $OutFile)) { if ($WhatIf) { Write-Log "Would remove $OutFile" } else { Remove-Item -LiteralPath $OutFile -Force } }

# ---------------- Branch characters ----------------
if ($config.tree.asciiBranches) {
  $H='-'; $V='|'; $T='+'; $L='\'
} else {
  $H=[char]0x2500; $V=[char]0x2502; $T=[char]0x251C; $L=[char]0x2514
}

# ---------------- Globs ----------------
$globExcludePatterns = @()
foreach ($g in $config.exclude.globs) {
  $globExcludePatterns += [System.Management.Automation.WildcardPattern]::new($g, [System.Management.Automation.WildcardOptions]::IgnoreCase)
}

# ---------------- Utils ----------------
function Should-SkipName([string]$name, [string[]]$patterns) {
  foreach ($p in $patterns) { if ($name -like $p) { return $true } }
  return $false
}

function Match-AnyGlob([string]$relPath, $patterns) {
  $unixRel = $relPath -replace '\\','/'
  foreach ($p in $patterns) { if ($p.IsMatch($unixRel)) { return $true } }
  return $false
}

function Get-RelativePath([string]$fullPath, [string]$rootPath) {
  $rootFixed = ($rootPath.TrimEnd('\','/')) + '\'
  $uRoot = New-Object System.Uri $rootFixed
  $uFull = New-Object System.Uri $fullPath
  $rel = $uRoot.MakeRelativeUri($uFull).ToString()
  return ($rel -replace '/','\')
}

function Format-Name($item) {
  if ($config.tree.showSymlinkInfo -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    $target = $null; try { $target = $item.Target } catch {}
    if ($target) { return ("{0} -> {1}" -f $item.Name, $target) }
    return ("{0} (link)" -f $item.Name)
  }
  return $item.Name
}

function Write-Line([string]$text) { if (-not $WhatIf) { $text | Out-File -FilePath $OutFile -Encoding $encoding -Append } }

# ---------------- Core ----------------
function Get-OrderedChildren($path) {
  $items = Get-ChildItem -LiteralPath $path -Force:$config.tree.includeHidden -ErrorAction SilentlyContinue `
           | Where-Object { -not (Should-SkipName $_.Name $config.exclude.namePatterns) }
  # glob excludes work on relative paths
  $items = $items | Where-Object {
    $rel = Get-RelativePath $_.FullName $Root
    -not (Match-AnyGlob $rel $globExcludePatterns)
  }
  if ($config.tree.sortDirsFirst) {
    $items = $items | Sort-Object @{Expression = { -not $_.PSIsContainer }}, Name
  } else {
    $items = $items | Sort-Object Name
  }
  return ,$items
}

function Write-Tree($path, $prefix = '', $currentDepth = 0) {
  if ($currentDepth -ge $config.tree.maxDepth) { return }
  $children = Get-OrderedChildren $path
  for ($i = 0; $i -lt $children.Count; $i++) {
    $child = $children[$i]
    $isLast = ($i -eq $children.Count - 1)
    $branch = if ($isLast) { "$L$H$H " } else { "$T$H$H " }
    $nextPre = if ($isLast) { "$prefix    " } else { "$prefix$V   " }

    Write-Line ("{0}{1}{2}" -f $prefix, $branch, (Format-Name $child))

    if ($child.PSIsContainer) {
      Write-Tree -path $child.FullName -prefix $nextPre -currentDepth ($currentDepth + 1)
    }
  }
}

# ---------------- Start ----------------
if (-not $NoMeta) {
  Write-Line ("Directory tree for: {0}" -f $Root)
  Write-Line ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"))
  Write-Line ("MaxDepth: {0} | IncludeHidden: {1} | ASCII: {2}" -f $config.tree.maxDepth, $config.tree.includeHidden, $config.tree.asciiBranches)
  Write-Line ("Exclude(name): {0}" -f ($config.exclude.namePatterns -join ", "))
  if ($config.exclude.globs -and $config.exclude.globs.Count -gt 0) {
    Write-Line ("Exclude(globs): {0}" -f ($config.exclude.globs -join ", "))
  }
  Write-Line ("===============================================")
  Write-Line "."
}

Write-Tree -path $Root

if (-not $NoMeta) {
  Write-Line ""
  Write-Line ("Done. Wrote: {0}" -f $OutFile)
}

if ($WhatIf) { Write-Log "Dry-run complete." } else { Write-Log "Wrote: $OutFile" }
