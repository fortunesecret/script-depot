<# 
Writes a tree of the directory (where this script lives) to file_structure.txt.

Examples:
  .\Write-Tree.ps1                   # Unicode branches
  .\Write-Tree.ps1 -ASCII          #ASCII branches
#>

[CmdletBinding()]
param(
  [int]$MaxDepth = [int]::MaxValue,
  [string[]]$Exclude = @('node_modules', '.git', '.vs', 'bin', 'obj', 'packages', 'Write-Tree.ps1', "file_structure.txt", "Rename-ToTS.ps1"),
  [string]$Root = (Get-Location).Path,
  [switch]$IncludeHidden,
  [switch]$ASCII
)

# Root: script directory if available; else current dir
$OutFile = Join-Path $Root 'file_structure.txt'

# Branch characters (ASCII by default). If -Unicode, use numeric code points (no literal glyphs in file).
if ($ASCII) {
  $H = '-'
  $V = '|'
  $T = '+'
  $L = '\'
} else {
  $H = [char]0x2500  # ─
  $V = [char]0x2502  # │
  $T = [char]0x251C  # ├
  $L = [char]0x2514  # └
}

# Helper: exclude by name (supports wildcards)
function Should-SkipName([string]$name, [string[]]$patterns) {
  foreach ($p in $patterns) { if ($name -like $p) { return $true } }
  return $false
}

# Write a line to the output file
function Write-Line([string]$text) {
  $text | Out-File -FilePath $OutFile -Encoding utf8 -Append
}

# Show link targets (symlinks/junctions)
function Format-Name($item) {
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    $tgt = $null
    try { $tgt = $item.Target } catch {}
    if ($tgt) { return ("{0} -> {1}" -f $item.Name, $tgt) }
    return ("{0} (link)" -f $item.Name)
  }
  return $item.Name
}

function Write-Tree($path, $prefix = '', $currentDepth = 0) {
  if ($currentDepth -ge $MaxDepth) { return }

  $children = Get-ChildItem -LiteralPath $path -Force:$IncludeHidden `
    | Where-Object { -not (Should-SkipName $_.Name $Exclude) } `
    | Sort-Object @{Expression = { -not $_.PSIsContainer }}, Name

  for ($i = 0; $i -lt $children.Count; $i++) {
    $child   = $children[$i]
    $isLast  = ($i -eq $children.Count - 1)
    $branch  = if ($isLast) { "$L$H$H " } else { "$T$H$H " }
    $nextPre = if ($isLast) { "$prefix    " } else { "$prefix$V   " }

    Write-Line ("{0}{1}{2}" -f $prefix, $branch, (Format-Name $child))

    if ($child.PSIsContainer) {
      Write-Tree -path $child.FullName -prefix $nextPre -currentDepth ($currentDepth + 1)
    }
  }
}

# Start fresh & header
"" | Out-File -FilePath $OutFile -Encoding utf8
@(
  "Directory tree for: $Root"
  ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"))
  ("MaxDepth: {0} | IncludeHidden: {1} | Exclude: {2}" -f $MaxDepth, $IncludeHidden, ($Exclude -join ', '))
  "==============================================="
  "."
) | Out-File -FilePath $OutFile -Encoding utf8

# Go
Write-Tree -path $Root

# Done
Write-Line ""
Write-Line ("Done. Wrote: {0}" -f $OutFile)
