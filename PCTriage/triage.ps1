[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory)][string]$Root,
  [switch]$SkipDownloads,          # if you want to use whatever is already in tools/
  [switch]$DefenderOnly,           # run only Defender
  [switch]$MSERTOnly,              # run only MSERT
  [switch]$AutorunsOnly            # run only Autoruns export
)

# ========= Paths =========
$Tools     = Join-Path $Root 'tools'
$Logs      = Join-Path $Root 'logs'
$Stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutDir    = Join-Path $Logs  ("triage\" + $Stamp)
$Wrk       = Join-Path $Tools 'work'
New-Item -ItemType Directory -Force -Path $Tools, $Logs, $OutDir, $Wrk | Out-Null

# ========= Helpers =========
function Save-Text { param([string]$Text,[string]$Path) try { $Text | Out-File -FilePath $Path -Encoding UTF8 } catch {} }
function Save-Csv  { param($Data,[string]$Path) try { $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 } catch {} }
function Log       { param([string]$Msg) $line = "$(Get-Date -Format s) $Msg"; $line | Out-File -FilePath (Join-Path $OutDir 'triage.log') -Append -Encoding UTF8; Write-Host $line }

function Test-Authenticode {
  param([Parameter(Mandatory)][string]$Path,[string]$RequiredPublisherSubstring)
  if (-not (Test-Path $Path)) { return $false }
  try {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne 'Valid') { Log "WARN: Signature on $Path is $($sig.Status)"; return $false }
    if ($RequiredPublisherSubstring -and ($sig.SignerCertificate.Subject -notmatch [regex]::Escape($RequiredPublisherSubstring))) {
      Log "WARN: Unexpected publisher for $Path : $($sig.SignerCertificate.Subject)"
      return $false
    }
    return $true
  } catch { Log "ERR: Authenticode check failed for $Path : $($_.Exception.Message)"; return $false }
}

function SafeDownload {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$OutFile,
    [string]$PublisherLike # optional substring to verify publisher after download
  )
  if ($SkipDownloads -and (Test-Path $OutFile)) { return $OutFile }
  try {
    Log "Downloading $Uri -> $OutFile"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    if ($PublisherLike) {
      if (-not (Test-Authenticode -Path $OutFile -RequiredPublisherSubstring $PublisherLike)) {
        throw "Authenticode validation failed for $OutFile"
      }
    }
    return $OutFile
  } catch {
    Log "ERR: Download failed for $Uri : $($_.Exception.Message)"
    throw
  }
}

# ========= 1) Microsoft Defender scan =========
function Invoke-DefenderFullScan {
  $mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
  if (-not (Test-Path $mp)) { $mp = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" } # fallback same path
  if (-not (Test-Path $mp)) { throw "MpCmdRun.exe not found." }

  if ($PSCmdlet.ShouldProcess("Defender", "SignatureUpdate")) {
    Log "Defender: updating signatures..."
    & $mp -SignatureUpdate | Out-Null
  }
  if ($PSCmdlet.ShouldProcess("Defender", "Full Scan")) {
    Log "Defender: starting Full Scan..."
    & $mp -Scan -ScanType 2 | Out-Null  # 2 = Full
  }

  # Save quick status + threats if any
  try {
    Get-MpComputerStatus | Export-Clixml (Join-Path $OutDir 'defender-status.xml')
  } catch {}
  try {
    $threats = Get-MpThreat -ErrorAction SilentlyContinue
    if ($threats) { Save-Csv $threats (Join-Path $OutDir 'defender-threats.csv') }
  } catch {}
  Log "Defender: completed."
}

# ========= 2) MSERT (Microsoft Safety Scanner) =========
function Invoke-MSERTFullScan {
  $msertPath = Join-Path $Tools 'msert.exe'
  if (-not $SkipDownloads -or -not (Test-Path $msertPath)) {
    # MSERT link is an evergreen FWLink to the latest build
    SafeDownload -Uri "https://go.microsoft.com/fwlink/?LinkId=212732" -OutFile $msertPath -PublisherLike "Microsoft Corporation" | Out-Null
  } else {
    if (-not (Test-Authenticode -Path $msertPath -RequiredPublisherSubstring "Microsoft Corporation")) {
      throw "Existing msert.exe failed signature validation."
    }
  }

  # Run quiet full scan. MSERT writes %WINDIR%\debug\msert.log
  if ($PSCmdlet.ShouldProcess("MSERT", "Full Scan")) {
    Log "MSERT: starting Full Scan (quiet)..."
    & $msertPath /f /q | Out-Null
    Log "MSERT: scan finished. Collecting log..."
  }
  $msLog = Join-Path $env:WINDIR "debug\msert.log"
  if (Test-Path $msLog) {
    Copy-Item $msLog (Join-Path $OutDir 'msert.log') -Force
  } else {
    Log "WARN: msert.log not found at $msLog (scan may not have produced a log yet)."
  }
}

# ========= 3) Sysinternals Autoruns export =========
function Invoke-AutorunsDump {
  $zip     = Join-Path $Wrk   'Autoruns.zip'
  $destDir = Join-Path $Tools 'Autoruns'
  $csvOut  = Join-Path $OutDir 'autoruns.csv'

  if (-not $SkipDownloads -or -not (Test-Path (Join-Path $destDir 'autorunsc64.exe'))) {
    SafeDownload -Uri "https://download.sysinternals.com/files/Autoruns.zip" -OutFile $zip | Out-Null
    if (Test-Path $destDir) { Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue }
    Expand-Archive -LiteralPath $zip -DestinationPath $destDir -Force
  }
  $autorunsc = Get-ChildItem $destDir -Filter 'autorunsc*.exe' | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $autorunsc) { throw "autorunsc.exe not found after extract." }

  if (-not (Test-Authenticode -Path $autorunsc -RequiredPublisherSubstring "Microsoft")) {
    throw "Autoruns command-line binary failed signature validation."
  }

  if ($PSCmdlet.ShouldProcess("Autoruns", "Export CSV")) {
    Log "Autoruns: exporting all autostarts to CSV..."
    & $autorunsc -accepteula -nobanner -a * -ct -h -m -s -u -vt -c -o $csvOut * | Out-Null
    Log "Autoruns: CSV written -> $csvOut"
  }
}

# ========= Decide what to run =========
$doDefender = $true; $doMSERT = $true; $doAutor  = $true
if ($DefenderOnly -or $MSERTOnly -or $AutorunsOnly) {
  $doDefender = $DefenderOnly
  $doMSERT    = $MSERTOnly
  $doAutor    = $AutorunsOnly
}

# ========= Execute =========
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  if ($doDefender) { Invoke-DefenderFullScan }
  if ($doMSERT)    { Invoke-MSERTFullScan }
  if ($doAutor)    { Invoke-AutorunsDump }
}
catch {
  Log "ERR: Triage step failed: $($_.Exception.Message)"
}
finally {
  $sw.Stop()
  Save-Text ("Completed in: " + $sw.Elapsed.ToString()) (Join-Path $OutDir 'DURATION.txt')
  Log "Triage complete. Output: $OutDir"
}
