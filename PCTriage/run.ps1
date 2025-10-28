<#
.SYNOPSIS
  Orchestrates IR steps and bundles per-run outputs.

.EXAMPLE
  .\run.ps1 -All -Root "C:\IncidentResponse"
  .\run.ps1 -Snapshot -Recon -BundleOutRoot "D:\IR-Outputs"
  .\run.ps1 -Triage -SkipDownloads -NoZip
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$Root,

  [switch]$Snapshot,
  [switch]$Recon,
  [switch]$DeepAutoruns,
  [switch]$Defender,
  [switch]$MSERT,
  [switch]$Triage,
  [switch]$All,

  # triage passthroughs
  [switch]$SkipDownloads,
  [switch]$DefenderOnly,
  [switch]$MSERTOnly,
  [switch]$AutorunsOnly,

  # bundling
  [string]$BundleOutRoot,
  [switch]$NoZip
)

# ---------- Resolve $Root (robust) ----------
function Resolve-IRRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = if ($PSScriptRoot) { $PSScriptRoot }
                elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path -Parent }
                else { (Get-Location).Path }
    }
    $Path = $Path.Trim("`"", "'"," ")
    if ($Path -match '^[\w\.\-]+::') { $Path = $Path.Split('::',2)[1] }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $Path = Split-Path -Path $Path -Parent }
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path -Path (Get-Location).Path -ChildPath $Path }
    $invalid = [IO.Path]::GetInvalidPathChars()
    if ($Path.IndexOfAny($invalid) -ge 0) { throw "Root contains invalid path characters: $Path" }
    return [IO.Path]::GetFullPath($Path)
}
$Root = Resolve-IRRoot $Root

# ---------- Admin check ----------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw "Please run this script as Administrator." }

# ---------- Folders + transcript ----------
$Logs  = Join-Path $Root 'logs'
$Tools = Join-Path $Root 'tools'
New-Item -ItemType Directory -Force -Path $Root, $Logs, $Tools | Out-Null
$TranscriptPath = Join-Path $Logs 'ir-transcript.txt'
if (-not (Get-Variable -Name __TranscriptStarted -Scope Script -ErrorAction SilentlyContinue)) {
  Start-Transcript -Path $TranscriptPath -Append | Out-Null
  Set-Variable -Name __TranscriptStarted -Value $true -Scope Script
}

# ---------- RunId & bundle target ----------
$RunId = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($BundleOutRoot)) { $BundleOutRoot = Join-Path $Root 'output' }
$BundleDir = Join-Path $BundleOutRoot $RunId
New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null

Write-Host "Root: $Root`nLogs: $Logs`nTools: $Tools`nRunId: $RunId`nBundle: $BundleDir" -ForegroundColor Cyan

# ---------- Helper: run a step with timing + capture output ----------
function Invoke-Step {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Action,
    [ref]$Output
  )
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "==> $Name" -ForegroundColor Yellow
  try {
    $res = $null
    if ($PSCmdlet.ShouldProcess($Name, "Execute")) { $res = & $Action }
    if ($PSBoundParameters.ContainsKey('Output')) { $Output.Value = $res }
    Write-Host "<== $Name OK ($($sw.Elapsed.ToString()))" -ForegroundColor Green
  }
  catch {
    Write-Host "<!! $Name FAILED: $($_.Exception.Message)" -ForegroundColor Red
    "$((Get-Date).ToString('s')) [$Name] ERROR: $($_ | Out-String)" |
      Out-File (Join-Path $Logs 'errors.txt') -Append
  }
  finally { $sw.Stop() }
}
function Coalesce {
    param([object[]]$Values)
    foreach ($v in $Values) {
      if ($null -ne $v -and ($v -isnot [string] -or $v.Trim() -ne '')) { return $v }
    }
    return $null
  }
# ---------- Locate step scripts (assumed same folder) ----------
$Here = $PSScriptRoot
$Paths = @{
  Snapshot     = Join-Path $Here 'snapshot.ps1'
  Recon        = Join-Path $Here 'recon.ps1'
  DeepAutoruns = Join-Path $Here 'deepautoruns.ps1'
  Defender     = Join-Path $Here 'defender.ps1'
  MSERT        = Join-Path $Here 'msert.ps1'
  Triage       = Join-Path $Here 'triage.ps1'
}

function Assert-ScriptExists { param([string]$Key)
  if (-not (Test-Path $Paths[$Key])) { Write-Warning "$Key not found at $($Paths[$Key]). Skipping."; return $false }
  return $true
}

# ---------- Decide what to run ----------
if ($All) { $Snapshot = $Recon = $DeepAutoruns = $Defender = $MSERT = $true }

# ---------- Helpers: resolve output dir for a step ----------
function Get-LatestChildDir {
  param([string]$BaseDir)
  if (-not (Test-Path $BaseDir)) { return $null }
  Get-ChildItem -LiteralPath $BaseDir -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
function Coerce-OutDirFromResult {
  param($Result)
  # Accept hashtable/object with OutDir, or a plain string path
  if ($Result -is [System.Collections.IDictionary] -and $Result.Contains('OutDir')) { return $Result['OutDir'] }
  if ($Result -and (Test-Path -LiteralPath $Result)) { return $Result }
  return $null
}

# Track step outputs by name
$StepOut = @{}
# ---------- Kick off steps (pass RunId when possible) ----------

# --- PRE-BASELINE: Snapshot ---
if ($Snapshot -and (Assert-ScriptExists 'Snapshot')) {
    $snapRes = $null
    Invoke-Step -Name "Snapshot" -Action { & $Paths.Snapshot -Root $Root -RunId $RunId } -Output ([ref]$snapRes)
    $StepOut['Snapshot'] = Coalesce @(
      (Coerce-OutDirFromResult $snapRes),
      (Join-Path (Join-Path $Logs 'snapshots') $RunId),
      (Get-LatestChildDir (Join-Path $Logs 'snapshots'))
    )
  }
  
  # --- PRE-BASELINE: Recon ---
  if ($Recon -and (Assert-ScriptExists 'Recon')) {
    $reconRes = $null
    Invoke-Step -Name "Recon" -Action { & $Paths.Recon -Root $Root -RunId $RunId } -Output ([ref]$reconRes)
    $StepOut['Recon'] = Coalesce @(
      (Coerce-OutDirFromResult $reconRes),
      (Join-Path (Join-Path $Logs 'recon') $RunId),
      (Get-LatestChildDir (Join-Path $Logs 'recon'))
    )
  }
  
  # --- Optional standalone tools if you're NOT using -Triage ---
  if ($DeepAutoruns -and -not $Triage -and (Assert-ScriptExists 'DeepAutoruns')) {
    $autorRes = $null
    Invoke-Step -Name "DeepAutoruns" -Action { & $Paths.DeepAutoruns -Root $Root -RunId $RunId } -Output ([ref]$autorRes)
    # If script writes a folder, great; else capture known CSV location
    $StepOut['Autoruns'] = (Coerce-OutDirFromResult $autorRes)
    if (-not $StepOut['Autoruns']) {
      $csv = Join-Path $Logs 'autoruns.csv'
      if (Test-Path $csv) { $StepOut['Autoruns'] = Split-Path -Path $csv -Parent }
    }
  }
  if ($Defender -and -not $Triage -and (Assert-ScriptExists 'Defender')) {
    $defRes = $null
    Invoke-Step -Name "Defender Scan" -Action { & $Paths.Defender -Root $Root -RunId $RunId } -Output ([ref]$defRes)
    $StepOut['Defender'] = Coalesce @(
      (Coerce-OutDirFromResult $defRes),
      (Get-LatestChildDir (Join-Path $Logs 'defender'))
    )
  }
  if ($MSERT -and -not $Triage -and (Assert-ScriptExists 'MSERT')) {
    $msRes = $null
    Invoke-Step -Name "MSERT Scan" -Action { & $Paths.MSERT -Root $Root -RunId $RunId } -Output ([ref]$msRes)
    $StepOut['MSERT'] = Coalesce @(
      (Coerce-OutDirFromResult $msRes),
      (Get-LatestChildDir (Join-Path $Logs 'msert'))
    )
  }
  
  # --- TRIAGE (tools+scans) — run AFTER baseline capture ---
  if ($Triage -and (Assert-ScriptExists 'Triage')) {
    Invoke-Step -Name "Triage (tools+scans)" -Action {
      & $Paths.Triage -Root $Root `
        -SkipDownloads:$SkipDownloads -DefenderOnly:$DefenderOnly `
        -MSERTOnly:$MSERTOnly -AutorunsOnly:$AutorunsOnly
    } -Output ([ref]$null)
    # triage writes logs\triage\<timestamp>; grab latest
    $StepOut['Triage'] = Get-LatestChildDir (Join-Path $Logs 'triage')
  }
  
  # --- POST-BASELINE (optional): Snapshot + Recon again to capture state after triage ---
  if ($BeforeAfter) {
    $RunIdAfter = "${RunId}_after"
  
    if ($Snapshot -and (Assert-ScriptExists 'Snapshot')) {
      $snapAfter = $null
      Invoke-Step -Name "Snapshot (after triage)" -Action { & $Paths.Snapshot -Root $Root -RunId $RunIdAfter } -Output ([ref]$snapAfter)
      $StepOut['Snapshot_After'] = Coalesce @(
        (Coerce-OutDirFromResult $snapAfter),
        (Join-Path (Join-Path $Logs 'snapshots') $RunIdAfter),
        (Get-LatestChildDir (Join-Path $Logs 'snapshots'))
      )
    }
  
    if ($Recon -and (Assert-ScriptExists 'Recon')) {
      $reconAfter = $null
      Invoke-Step -Name "Recon (after triage)" -Action { & $Paths.Recon -Root $Root -RunId $RunIdAfter } -Output ([ref]$reconAfter)
      $StepOut['Recon_After'] = Coalesce @(
        (Coerce-OutDirFromResult $reconAfter),
        (Join-Path (Join-Path $Logs 'recon') $RunIdAfter),
        (Get-LatestChildDir (Join-Path $Logs 'recon'))
      )
    }
  }

# ---------- Bundle: copy each step output under one roof ----------
foreach ($key in $StepOut.Keys) {
  $src = $StepOut[$key]
  if ($src -and (Test-Path $src)) {
    $dst = Join-Path $BundleDir $key
    Write-Host "Bundling $key -> $dst" -ForegroundColor DarkCyan
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item -LiteralPath $src\* -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# ---------- Optional ZIP ----------
if (-not $NoZip) {
  New-Item -ItemType Directory -Force -Path $BundleOutRoot | Out-Null
  $zipPath = Join-Path $BundleOutRoot ("IR_" + $RunId + ".zip")
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path (Join-Path $BundleDir '*') -DestinationPath $zipPath -Force
  Write-Host "Bundle ZIP: $zipPath" -ForegroundColor Green
}

Write-Host "Done. Bundle folder: $BundleDir`nTranscript: $TranscriptPath" -ForegroundColor Cyan
