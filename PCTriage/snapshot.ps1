[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Root,
  [string]$RunId 
)

# ----- prep paths -----
$Logs      = Join-Path $Root 'logs'
$Tools     = Join-Path $Root 'tools'
$Stamp = if ($RunId) { $RunId } else { Get-Date -Format 'yyyyMMdd_HHmmss' }
$SnapBase  = Join-Path $Logs 'snapshots'
$OutDir    = Join-Path $SnapBase $Stamp

New-Item -ItemType Directory -Force -Path $Logs, $Tools, $SnapBase, $OutDir | Out-Null

# helper: safe CSV/text writers
# Accepts pipeline input and writes once at the end
function Save-Csv {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Data,                                 # not Mandatory to avoid prompts on empty pipeline
        [Parameter(Mandatory)]
        [string]$Path
    )
    begin { $buf = @() }
    process {
        if ($null -ne $Data) { $buf += $Data }
    }
    end {
        if ($buf.Count -gt 0) {
            try { $buf | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 } catch {}
        }
    }
}

# Also pipeline-friendly for text blobs
function Save-Text {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$Text,                          # not Mandatory; ignore empty input
        [Parameter(Mandatory)]
        [string]$Path
    )
    begin { $sb = New-Object System.Text.StringBuilder }
    process { if ($Text) { [void]$sb.AppendLine($Text) } }
    end {
        if ($sb.Length -gt 0) {
            try { $sb.ToString() | Out-File -FilePath $Path -Encoding UTF8 } catch {}
        }
    }
}
# helper: try/capture wrapper
function Try-Run { param([Parameter(Mandatory)][scriptblock]$Script,[string]$OnError='')
  try { & $Script } catch { if($OnError){ Save-Text $OnError + "`n$($_.Exception.Message)" (Join-Path $OutDir 'errors.txt') } }
}

# ----- basic system info -----
Try-Run { Get-ComputerInfo } | Export-Clixml (Join-Path $OutDir 'computerinfo.xml')
Try-Run { systeminfo }       | Out-File      (Join-Path $OutDir 'systeminfo.txt')
Try-Run { wmic os get Caption,Version,BuildNumber /value } | Out-File (Join-Path $OutDir 'wmic-os.txt')

# ----- processes (hash + guarded StartTime) -----
$procs = Try-Run { Get-Process | Sort-Object CPU -Descending }
if ($procs) {
  $procRows = foreach($p in $procs){
    $path = $null; $hash = $null; $st = $null
    try { $path = $p.Path } catch {}
    if ($path -and (Test-Path $path)) {
      try { $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash } catch {}
    }
    try { $st = $p.StartTime } catch {}
    [PSCustomObject]@{
      Name      = $p.Name
      Id        = $p.Id
      Path      = $path
      SHA256    = $hash
      CPU       = $p.CPU
      StartTime = $st
      WS_MB     = [math]::Round($p.WorkingSet64/1MB,2)
      VM_MB     = [math]::Round($p.VirtualMemorySize64/1MB,2)
    }
  }
  Save-Csv $procRows (Join-Path $OutDir 'processes.csv')
}

# ----- ports / connections -----
Try-Run {
  Get-NetTCPConnection -State Listen,Established |
    Select-Object State,LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess
} | Save-Csv -Path (Join-Path $OutDir 'net-tcp.csv')

Try-Run { arp -a }            | Out-File (Join-Path $OutDir 'arp.txt')
Try-Run { route print }       | Out-File (Join-Path $OutDir 'routes.txt')
Try-Run { ipconfig /all }     | Out-File (Join-Path $OutDir 'ipconfig.txt')

# ----- startup folders & Run keys -----
$runTxt = Join-Path $OutDir 'run-keys.txt'
Try-Run {
  $startup = @()
  $startup += Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" -ErrorAction SilentlyContinue
  $startup += Get-ChildItem "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue
  $startup | Select-Object FullName, LastWriteTime | Format-Table | Out-String
} | Save-Text -Path (Join-Path $OutDir 'startup-folders.txt')

$runKeys = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach($rk in $runKeys){
  if(Test-Path $rk){
    "[$rk]"        | Out-File -Append $runTxt -Encoding UTF8
    (Get-ItemProperty $rk | Out-String) | Out-File -Append $runTxt -Encoding UTF8
    "`n"           | Out-File -Append $runTxt -Encoding UTF8
  }
}

# ----- scheduled tasks & actions (null-safe) -----
Try-Run {
    Get-ScheduledTask | Get-ScheduledTaskInfo |
      Select-Object TaskName,TaskPath,LastRunTime,NextRunTime,LastTaskResult
  } | Save-Csv -Path (Join-Path $OutDir 'scheduled-tasks.csv')

Try-Run {
    Get-ScheduledTask | ForEach-Object {
      # Build Actions text safely
      $acts = @()
      foreach ($a in $_.Actions) {
        if ($null -ne $a) {
          $exe = $a.Execute
          $arg = $a.Arguments
          $line = [string]::Join(' ', (@($exe, $arg) | Where-Object { $_ -and $_.Trim().Length -gt 0 }))
          if ($line) { $acts += $line }
        }
      # Build Triggers text safely
      $trigs = @()
      foreach ($t in $_.Triggers) {
        if ($t) { $trigs += ($t.ToString()) }
      }
      [PSCustomObject]@{
        TaskName = $_.TaskName
        TaskPath = $_.TaskPath
        Actions  = ($acts -join ' | ')
        Triggers = ($trigs -join ' | ')
      }
    }
  } | Save-Csv -Path (Join-Path $OutDir 'scheduled-actions.csv')
}

# ----- services -----
Try-Run {
  Get-CimInstance Win32_Service |
    Select-Object Name,DisplayName,State,StartMode,StartName,PathName |
    Sort-Object State,Name
} | Save-Csv -Path (Join-Path $OutDir 'services.csv')

# ----- drivers -----
Try-Run {
  Get-CimInstance Win32_SystemDriver | Select-Object Name,State,PathName,StartMode
} | Save-Csv -Path (Join-Path $OutDir 'drivers.csv')

# ----- installed programs (x64/x86) -----
$uninstPaths = @(
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
$apps = foreach($p in $uninstPaths){
  if(Test-Path $p){
    Get-ChildItem $p -ErrorAction SilentlyContinue | ForEach-Object {
      $i = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
      if ($i.DisplayName) {
        [PSCustomObject]@{
          DisplayName      = $i.DisplayName
          Publisher        = $i.Publisher
          InstallDate      = $i.InstallDate
          DisplayVersion   = $i.DisplayVersion
          UninstallString  = $i.UninstallString
          InstallLocation  = $i.InstallLocation
          PSPath           = $_.PsPath
        }
      }
    }
  }
}
if ($apps) { $apps | Sort-Object DisplayName | Save-Csv -Path (Join-Path $OutDir 'installed-programs.csv') }

# ----- Windows Security / Defender -----
Try-Run { Get-MpComputerStatus } | Export-Clixml (Join-Path $OutDir 'defender-status.xml')
Try-Run { Get-MpPreference }     | Export-Clixml (Join-Path $OutDir 'defender-prefs.xml')

# registered AV products in Security Center (helps spot fake AV)
Try-Run {
  Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct |
    Select-Object displayName, pathToSignedProductExe, productState
} | Save-Csv -Path (Join-Path $OutDir 'securitycenter-av.csv')

# summarize Defender exclusions (quick view)
try {
  $mp = Get-MpPreference
  [PSCustomObject]@{
    ExclusionPath      = ($mp.ExclusionPath -join '; ')
    ExclusionProcess   = ($mp.ExclusionProcess -join '; ')
    ExclusionExtension = ($mp.ExclusionExtension -join '; ')
  } | Save-Csv -Path (Join-Path $OutDir 'defender-exclusions.csv')
} catch {}

# ----- hosts file -----
Try-Run { Get-Content $env:WINDIR\System32\drivers\etc\hosts -ErrorAction SilentlyContinue } |
  Out-File (Join-Path $OutDir 'hosts.txt') -Encoding UTF8

# ----- firewall rules (brief summary) -----
Try-Run {
  Get-NetFirewallRule -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Enabled, Direction, Action, Profile
} | Save-Csv -Path (Join-Path $OutDir 'firewall-rules.csv')

# ----- proxy & LSA hardening flags -----
try {
  Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
    Select-Object ProxyEnable,ProxyServer |
    Format-List | Out-String | Out-File (Join-Path $OutDir 'proxy.txt') -Encoding UTF8
} catch {}
try {
  Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" |
    Select-Object RunAsPPL,RunAsPPLBoot |
    Format-List | Out-String | Out-File (Join-Path $OutDir 'lsa.txt') -Encoding UTF8
} catch {}

# ----- local admins (quick look) -----
Try-Run {
  net localgroup administrators
} | Out-File (Join-Path $OutDir 'local-admins.txt')

# ----- small index file to help navigate -----
$index = @"
Snapshot: $Stamp
OutputDir: $OutDir

Key files:
- processes.csv, net-tcp.csv, services.csv, drivers.csv
- installed-programs.csv
- scheduled-tasks.csv, scheduled-actions.csv
- defender-status.xml, defender-prefs.xml, defender-exclusions.csv, securitycenter-av.csv
- ipconfig.txt, routes.txt, arp.txt, hosts.txt
- firewall-rules.csv, proxy.txt, lsa.txt
"@
Save-Text $index (Join-Path $OutDir 'INDEX.txt')

Write-Host "Snapshot complete: $OutDir" -ForegroundColor Green
