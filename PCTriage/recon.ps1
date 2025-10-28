[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Root,
  [string]$RunId
)

# ===== Paths =====
$Logs     = Join-Path $Root 'logs'
$Tools    = Join-Path $Root 'tools'
$Stamp = if ($RunId) { $RunId } else { Get-Date -Format 'yyyyMMdd_HHmmss' }
$ReconDir = Join-Path $Logs  ("recon\" + $Stamp)

New-Item -ItemType Directory -Force -Path $Logs, $Tools, $ReconDir | Out-Null

# ===== Helpers =====
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

function Try-Run {
  param([Parameter(Mandatory)][scriptblock]$Script,[string]$ErrTag='recon')
  try { & $Script } catch {
    $msg = "$((Get-Date).ToString('s')) [$ErrTag] $($_.Exception.Message)"
    $errFile = Join-Path $ReconDir 'errors.txt'
    $msg | Out-File -Append $errFile -Encoding UTF8
    return $null
  }
}

# ===== Security Center (registered AV) =====
Try-Run {
  Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct |
    Select-Object displayName, pathToSignedProductExe, productState
} | Save-Csv -Path (Join-Path $ReconDir 'securitycenter-av.csv')

# ===== Defender status & exclusions (quick view) =====
Try-Run { Get-MpComputerStatus } | Export-Clixml (Join-Path $ReconDir 'defender-status.xml')

try {
  $mp = Get-MpPreference
  [PSCustomObject]@{
    ExclusionPath       = ($mp.ExclusionPath -join '; ')
    ExclusionProcess    = ($mp.ExclusionProcess -join '; ')
    ExclusionExtension  = ($mp.ExclusionExtension -join '; ')
    PUAProtection       = $mp.PUAProtection
    MAPSReporting       = $mp.MAPSReporting
    SubmitSamplesConsent= $mp.SubmitSamplesConsent
    RealTimeScanDirection = $mp.RealTimeScanDirection
  } | Save-Csv -Path (Join-Path $ReconDir 'defender-exclusions.csv')
} catch {}

# ===== Proxies (User + WinHTTP) =====
Try-Run {
  Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
    Select-Object ProxyEnable,ProxyServer,AutoConfigURL
} | Save-Csv -Path (Join-Path $ReconDir 'proxy-user.csv')

Try-Run { netsh winhttp show proxy } |
  Out-File (Join-Path $ReconDir 'proxy-winhttp.txt') -Encoding UTF8

# ===== LSA / Credential hardening flags =====
try {
  $lsa = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
  [PSCustomObject]@{
    RunAsPPL     = $lsa.RunAsPPL
    RunAsPPLBoot = $lsa.RunAsPPLBoot
    LsaCfgFlags  = $lsa.LsaCfgFlags
  } | Save-Csv -Path (Join-Path $ReconDir 'lsa-hardening.csv')
} catch {}

# Device Guard / Credential Guard summary (if present)
Try-Run {
  Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
} | Export-Clixml (Join-Path $ReconDir 'deviceguard.xml')

# ===== Firewall posture =====
Try-Run {
  Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen, AllowInboundRules, AllowLocalFirewallRules
} | Save-Csv -Path (Join-Path $ReconDir 'firewall-profiles.csv')

# Quick count of enabled inbound allow rules (potential exposure)
Try-Run {
  Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True |
    Group-Object Profile | Select-Object Name,Count
} | Save-Csv -Path (Join-Path $ReconDir 'firewall-inbound-allow-counts.csv')

# ===== RDP exposure =====
# fDenyTSConnections=1 means RDP is disabled; 0 means enabled
try {
  $rdp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
  [PSCustomObject]@{ fDenyTSConnections = $rdp.fDenyTSConnections } |
    Save-Csv -Path (Join-Path $ReconDir 'rdp-status.csv')
} catch {}

# RDP firewall rule state
Try-Run {
  Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Enabled, Direction, Action, Profile
} | Save-Csv -Path (Join-Path $ReconDir 'rdp-firewall.csv')

# ===== Local Admins (who’s effectively privileged) =====
Try-Run { net localgroup administrators } |
  Out-File (Join-Path $ReconDir 'local-admins.txt') -Encoding UTF8

# ===== UAC posture =====
try {
  $uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
  [PSCustomObject]@{
    EnableLUA                 = $uac.EnableLUA
    ConsentPromptBehaviorAdmin= $uac.ConsentPromptBehaviorAdmin
    PromptOnSecureDesktop     = $uac.PromptOnSecureDesktop
  } | Save-Csv -Path (Join-Path $ReconDir 'uac-policy.csv')
} catch {}

# ===== DNS servers (active interfaces) =====
Try-Run {
  Get-DnsClientServerAddress -AddressFamily IPv4 |
    Where-Object {$_.ServerAddresses} |
    Select-Object InterfaceAlias,ServerAddresses
} | Save-Csv -Path (Join-Path $ReconDir 'dns-servers.csv')

# ===== Startup impact quick check: Run keys echoes (for diff vs snapshot) =====
$runKeys = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)
$runOut = Join-Path $ReconDir 'run-keys.txt'
foreach($rk in $runKeys){
  if(Test-Path $rk){
    "[$rk]" | Out-File -Append $runOut -Encoding UTF8
    (Get-ItemProperty $rk | Out-String) | Out-File -Append $runOut -Encoding UTF8
    "`n" | Out-File -Append $runOut -Encoding UTF8
  }
}

# ===== Index =====
$index = @"
Recon: $Stamp
OutDir: $ReconDir

Key outputs:
- securitycenter-av.csv
- defender-status.xml, defender-exclusions.csv
- proxy-user.csv, proxy-winhttp.txt
- lsa-hardening.csv, deviceguard.xml
- firewall-profiles.csv, firewall-inbound-allow-counts.csv
- rdp-status.csv, rdp-firewall.csv
- local-admins.txt, uac-policy.csv
- dns-servers.csv, run-keys.txt
"@
Save-Text $index (Join-Path $ReconDir 'INDEX.txt')

Write-Host "Recon complete: $ReconDir" -ForegroundColor Cyan
