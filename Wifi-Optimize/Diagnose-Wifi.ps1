<#
.SYNOPSIS
  Wi-Fi diagnostics & reversible optimizer (Intel AX201-friendly). PowerShell 5.1+.

.DESCRIPTION
  - Creates a timestamped run directory under $HOME\WifiSuite\<timestamp>\
  - Snapshots current adapter/driver/advanced/power settings to JSON
  - Runs a pre-change monitor (default 60s @ 1s)
  - If -Optimize: applies recommended settings (admin required), snapshots them, runs post monitor
  - If -RestoreFrom <json>: restores prior advanced settings (admin required), runs post monitor
  - If Compare-Monitors.ps1 is present beside this script, it auto-compares pre/post and opens compare-report.html

.PARAMETER InterfaceName
  Wi-Fi interface alias (default: "Wi-Fi").

.PARAMETER IntervalSeconds
  Sampling interval for monitor (seconds). Default: 1.

.PARAMETER DurationSeconds
  Duration of each monitoring pass (seconds). Default: 60.

.PARAMETER Optimize
  Apply safe optimization preset after the pre-change monitor, then monitor again.

.PARAMETER RestoreFrom
  JSON file produced by a previous run (original-settings.json or applied-settings.json).
  Restores advanced properties from that file, then monitors again.

.PARAMETER ForceAx
  Keep 802.11ax when optimizing (default: off → prefer 802.11ac for stability).

.NOTES
  - Use built-in -WhatIf for dry-runs; this script honors ShouldProcess on changes.
  - Tested with Windows 10/11, Intel Wi-Fi 6 AX201.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$InterfaceName = "Wi-Fi",
    [int]$IntervalSeconds = 1,
    [int]$DurationSeconds = 180,
    [switch]$Optimize,
    [string]$RestoreFrom,
    [switch]$ForceAx
)

# Display information about sample length
if ($DurationSeconds -lt 60) {
    Write-Host "Warning: Sample length of $DurationSeconds seconds might be too short for reliable results." -ForegroundColor Yellow
    Write-Host "Recommended minimum is 60 seconds." -ForegroundColor Yellow
} elseif ($DurationSeconds -gt 300) {
    Write-Host "Note: Sample length of $DurationSeconds seconds is quite long. This will take a while to complete." -ForegroundColor Yellow
} else {
    Write-Host "Sample length of $DurationSeconds seconds should provide good results." -ForegroundColor Green
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import modules
$modulesPath = Join-Path $PSScriptRoot "Modules"
$moduleFiles = @(
    "WifiUtils.psm1",
    "WifiDataProcessing.psm1",
    "HtmlTemplates.psm1"
)

foreach ($module in $moduleFiles) {
    $modulePath = Join-Path $modulesPath $module
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    } else {
        Write-Host "[ERROR] Module not found: $modulePath" -ForegroundColor Red
        exit 1
    }
}

# --------------------------- Setup & Logging --------------------------- #
$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$rootDir = Join-Path $HOME "WifiSuite"
$runDir = Join-Path $rootDir $runStamp
# Create directories even in WhatIf mode
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
foreach ($d in @($rootDir, $runDir)) { 
    if (-not (Test-Path $d)) { 
        New-Item -ItemType Directory -Path $d | Out-Null 
    } 
}
$WhatIfPreference = $oldWhatIf

$logPath = Join-Path $runDir "diagnose.log"

# Create log file even in WhatIf mode
$oldWhatIf = $WhatIfPreference
$WhatIfPreference = $false
if (-not (Test-Path $logPath)) {
    "" | Set-Content -Path $logPath -Force
}
$WhatIfPreference = $oldWhatIf

Write-Log -Message "Run dir: $runDir" -LogPath $logPath
Write-Log -Message "Params: InterfaceName=$InterfaceName Interval=$IntervalSeconds Duration=$DurationSeconds Optimize=$Optimize RestoreFrom=$RestoreFrom ForceAx=$ForceAx WhatIfPref=$WhatIfPreference" -LogPath $logPath

# Non-terminating error safe wrapper for power mgmt (Intel/Modern Standby quirks)
function Get-PowerMgmtSafe([string]$AdapterName) {
    try { Get-NetAdapterPowerManagement -Name $AdapterName -ErrorAction Stop } catch { $null }
}

# --------------------------- Helpers: Adapter & Reporting --------------------------- #
function Get-Adapter() {
    $ad = Invoke-SafeCommand -Block { Get-NetAdapter -Name $InterfaceName -ErrorAction Stop } -Context "Get-NetAdapter($InterfaceName)"
    if (-not $ad) {
        $cand = Invoke-SafeCommand -Block { Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -and $_.Status -eq "Up" } } -Context "Get-NetAdapter(*Wi-Fi*)"
        if ($cand) { $ad = $cand | Select-Object -First 1 }
    }
    if (-not $ad) { throw "Wi-Fi adapter '$InterfaceName' not found or not Up." }
    return $ad
}

# Save-Json is now imported from WifiUtils module

function Get-DriverReport([Microsoft.Management.Infrastructure.CimInstance]$Adapter) {
    # --- Capabilities (netsh drivers)
    $drv = Invoke-SafeCommand -Block { netsh wlan show drivers } -Context "netsh wlan show drivers"
    $caps = [ordered]@{}
    if ($drv) {
        $caps.RadioTypesSupported = ($drv | Select-String -Pattern "Radio types supported\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
        $caps.ChannelWidthsSupported = ($drv | Select-String -Pattern "Channel widths supported\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
    }

    # --- Power management (defensive)
    $pm = Get-PowerMgmtSafe -AdapterName $Adapter.Name
    $pmReport = $null
    if ($pm) {
        if ($pm -is [System.Array]) { $pm = $pm | Select-Object -First 1 }
        $pmReport = [ordered]@{}
        foreach ($name in @(
                'AllowComputerToTurnOffDevice',
                'DeviceSleepOnDisconnect',
                'WakeOnMagicPacket',
                'WakeOnPattern',
                'PacketCoalescing' # may be absent
            )) {
            if ($pm | Get-Member -Name $name -ErrorAction SilentlyContinue) {
                $pmReport[$name] = $pm.$name
            }
        }
        if ($pmReport.Count -eq 0) { $pmReport.Note = "Power mgmt properties not exposed by this driver/OS." }
    }
    else {
        $pmReport = @{ Note = "Power mgmt info unavailable (OS/driver quirk)." }
    }

    # --- Advanced properties
    $adv = Invoke-SafeCommand -Block { Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction Stop } -Context "Get-NetAdapterAdvancedProperty"
    $advReport = @()
    if ($adv) { $advReport = $adv | Select-Object InterfaceDescription, DisplayName, DisplayValue, RegistryKeyword, RegistryValue }

    # --- Current Wi-Fi link (netsh interfaces)
    $wifiInfoRaw = Invoke-SafeCommand -Block { netsh wlan show interfaces } -Context "netsh wlan show interfaces"
    $wifi = $null
    if ($wifiInfoRaw) {
        $wifi = [pscustomobject]@{
            SSID       = ($wifiInfoRaw | Select-String "^\s*SSID\s*:\s*(.+)$" -AllMatches | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
            BSSID      = ($wifiInfoRaw | Select-String "^\s*BSSID\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
            SignalPct  = ($wifiInfoRaw | Select-String "^\s*Signal\s*:\s*(\d+)%" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
            RadioType  = ($wifiInfoRaw | Select-String "^\s*Radio\s*type\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
            Channel    = ($wifiInfoRaw | Select-String "^\s*Channel\s*:\s*(\d+)$" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
            RxRateMbps = ($wifiInfoRaw | Select-String "^\s*Receive\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
            TxRateMbps = ($wifiInfoRaw | Select-String "^\s*Transmit\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
        }
    }

    # --- IP info (defensive; DhcpServer not always present)
    function Get-DhcpServerFromIpconfig([string]$Alias) {
        $lines = Invoke-SafeCommand -Block { ipconfig /all } -Context "ipconfig /all"
        if (-not $lines) { return $null }
        $inBlock = $false
        foreach ($line in $lines) {
            if ($line -match "adapter\s+(.+?):\s*$") { $inBlock = ($Matches[1].Trim() -eq $Alias); continue }
            if ($inBlock -and $line -match "^\s*DHCP Server.*:\s*(.+)\s*$") { return $Matches[1].Trim() }
            if ($inBlock -and $line -match "^\s*$") { $inBlock = $false }
        }
        return $null
    }

    $ipcfg = Invoke-SafeCommand -Block { Get-NetIPConfiguration -InterfaceAlias $Adapter.Name } -Context "Get-NetIPConfiguration"
    $ipReport = $null
    if ($ipcfg) {
        if ($ipcfg -is [System.Array]) { $ipcfg = $ipcfg | Select-Object -First 1 }

        $ipv4 = $null; $ipv6 = $null; $gw4 = $null; $gw6 = $null; $dns = $null; $dhcpSrv = $null
        try { if ($ipcfg.IPv4Address) { $ipv4 = $ipcfg.IPv4Address.IPAddress | Select-Object -First 1 } } catch {}
        try { if ($ipcfg.IPv6Address) { $ipv6 = ($ipcfg.IPv6Address.IPAddress | Where-Object { $_ -notmatch '^fe80:' } | Select-Object -First 1) } } catch {}
        try { if ($ipcfg.IPv4DefaultGateway) { $gw4 = $ipcfg.IPv4DefaultGateway.NextHop | Select-Object -First 1 } } catch {}
        try { if ($ipcfg.IPv6DefaultGateway) { $gw6 = $ipcfg.IPv6DefaultGateway.NextHop | Select-Object -First 1 } } catch {}
        try { if ($ipcfg.DNSServer) { $dns = (@($ipcfg.DNSServer.ServerAddresses) -join ';') } } catch {}

        if ($ipcfg | Get-Member -Name DhcpServer -ErrorAction SilentlyContinue) {
            try { $dhcpSrv = ($ipcfg.DhcpServer | Select-Object -First 1) } catch {}
        }
        if (-not $dhcpSrv) { $dhcpSrv = Get-DhcpServerFromIpconfig -Alias $Adapter.Name }

        $ipReport = [ordered]@{
            IPv4      = $ipv4
            IPv6      = $ipv6
            GatewayV4 = $gw4
            GatewayV6 = $gw6
            DNS       = $dns
            DHCP      = $dhcpSrv
        }
    }

    return [ordered]@{
        Timestamp    = (Get-Date).ToString("o")
        Adapter      = [ordered]@{
            Name          = $Adapter.Name
            InterfaceDesc = $Adapter.InterfaceDescription
            DriverVersion = $Adapter.DriverVersion
            DriverInfo    = $Adapter.DriverInformation
        }
        PowerMgmt    = $pmReport
        Advanced     = $advReport
        Capabilities = $caps
        WifiLink     = $wifi
        IP           = $ipReport
    }
}

# --------------------------- Settings Backup / Restore --------------------------- #
function Backup-Settings([Microsoft.Management.Infrastructure.CimInstance]$Adapter, [string]$OutPath) {
    $adv = Invoke-SafeCommand -Block { Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction Stop } -Context "Get-NetAdapterAdvancedProperty"
    $pm = Get-PowerMgmtSafe -AdapterName $Adapter.Name
    if ($pm -and $pm -is [System.Array]) { $pm = $pm | Select-Object -First 1 }

    $data = [ordered]@{
        Interface   = $Adapter.InterfaceDescription
        AdvancedMap = @{}
        PowerMgmt   = $null
    }

    if ($adv) {
        foreach ($row in $adv) { $data.AdvancedMap[$row.DisplayName] = [string]$row.DisplayValue }
    }

    if ($pm) {
        $pmMap = [ordered]@{}
        foreach ($name in @(
                'AllowComputerToTurnOffDevice',
                'DeviceSleepOnDisconnect',
                'WakeOnMagicPacket',
                'WakeOnPattern',
                'PacketCoalescing'
            )) {
            if ($pm | Get-Member -Name $name -ErrorAction SilentlyContinue) {
                $pmMap[$name] = $pm.$name
            }
        }
        if ($pmMap.Count -eq 0) { $pmMap.Note = "Power mgmt properties not exposed by this driver/OS." }
        $data.PowerMgmt = $pmMap
    }
    else {
        $data.PowerMgmt = @{ Note = "Unavailable in this environment" }
    }

    Save-Json $data $OutPath
}

function Set-AdvPropSafe {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$AdapterName,
        [string]$DisplayName,
        [string]$Desired,
        [ref]$ChangedList,
        [hashtable]$OrigMap
    )
    # $ChangedList: [ref] to a list of @{Name=..; From=..; To=..}
    $prop = Invoke-SafeCommand -Block { Get-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName -ErrorAction Stop } -Context "Get-NetAdapterAdvancedProperty:$DisplayName"
    if (-not $prop) { Write-Log -Message "Property '$DisplayName' not found; skipping." -Level "WARN" -LogPath $logPath; return }

    $current = [string]$prop.DisplayValue
    $choices = @($prop.ValidDisplayValues) ; if (-not $choices -or $choices.Count -eq 0) { $choices = @($current) }

    function Normalize([string]$s) { if ($null -eq $s) { "" } else { ($s -replace '[^a-zA-Z0-9]', '').ToLowerInvariant() } }
    $normDesired = Normalize $Desired
    $normChoices = $choices | ForEach-Object { @{ Raw = $_; Norm = (Normalize $_) } }

    # First, exact normalized match
    $match = $normChoices | Where-Object { $_.Norm -eq $normDesired } | Select-Object -First 1
    # Then, contains (normalized)
    if (-not $match -and $normDesired) { $match = $normChoices | Where-Object { $_.Norm -like "*$normDesired*" } | Select-Object -First 1 }
    # Finally, regex of desired without spaces
    if (-not $match -and $normDesired) { $match = $normChoices | Where-Object { $_.Norm -match [regex]::Escape($normDesired) } | Select-Object -First 1 }

    if (-not $match) {
        Write-Log -Message "No matching value for '$DisplayName'. Choices: $($choices -join ', ')" -Level "WARN" -LogPath $logPath
        return
    }

    $target = [string]$match.Raw
    if ($current -eq $target) {
        Write-Log -Message "OK: '$DisplayName' already '$current'." -LogPath $logPath
        return
    }

    Write-Log -Message "SET '$DisplayName': '$current' -> '$target'" -LogPath $logPath
    if ($PSCmdlet.ShouldProcess("$AdapterName", "Set '$DisplayName' to '$target'")) {
        try {
            Set-NetAdapterAdvancedProperty -Name $AdapterName -DisplayName $DisplayName -DisplayValue $target -NoRestart -ErrorAction Stop
            # Remember what we changed so we can roll it back on failure later
            $prev = if ($OrigMap.ContainsKey($DisplayName)) { $OrigMap[$DisplayName] } else { $current }
            $ChangedList.Value += , (@{ Name = $DisplayName; From = $prev; To = $target })
        }
        catch {
            Write-Log -Message "Failed setting '$DisplayName': $($_.Exception.Message)" -Level "ERROR" -LogPath $logPath
            throw
        }
    }
}

function Set-WifiOptimization {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Microsoft.Management.Infrastructure.CimInstance]$Adapter,
        [switch]$ForceAx
    )
    if (-not (Test-IsAdmin)) {
        throw "Administrator privileges are required to change adapter advanced properties. Right-click PowerShell → Run as administrator."
    }

    Write-Log -Message "Applying optimization profile..." -LogPath $logPath
    # Build original map once
    $origAdv = @{}
    $snap = Invoke-SafeCommand -Block { Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction Stop } -Context "Get-NetAdapterAdvancedProperty"
    if ($snap) { foreach ($row in $snap) { $origAdv[$row.DisplayName] = [string]$row.DisplayValue } }

    $changed = New-Object System.Collections.ArrayList

    try {
        # Preferred Band → prefer 5 GHz (driver presents as "3. Prefer 5GHz band")
        Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "Preferred Band" -Desired "Prefer 5GHz band" -ChangedList ([ref]$changed) -OrigMap $origAdv

        # Channel Width for 5GHz → try 80; else "Auto" (your driver has {Auto, 20 MHz Only})
        $propCW = Invoke-SafeCommand -Block { Get-NetAdapterAdvancedProperty -Name $Adapter.Name -DisplayName "Channel Width for 5GHz" -ErrorAction Stop } -Context "Get-NetAdapterAdvancedProperty:ChannelWidth5G"
        if ($propCW -and ($propCW.ValidDisplayValues -contains "80 MHz")) {
            Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "Channel Width for 5GHz" -Desired "80 MHz" -ChangedList ([ref]$changed) -OrigMap $origAdv
        }
        else {
            Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "Channel Width for 5GHz" -Desired "Auto" -ChangedList ([ref]$changed) -OrigMap $origAdv
        }

        # MIMO Power Save → No SMPS
        Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "MIMO Power Save Mode" -Desired "No SMPS" -ChangedList ([ref]$changed) -OrigMap $origAdv

        # Roaming Aggressiveness → Medium-Low (variants: "2. Medium-Low", "3. Medium", etc.)
        Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "Roaming Aggressiveness" -Desired "Medium-Low" -ChangedList ([ref]$changed) -OrigMap $origAdv

        # Transmit Power → Highest
        Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "Transmit Power" -Desired "Highest" -ChangedList ([ref]$changed) -OrigMap $origAdv

        # 802.11n/ac/ax Wireless Mode
        if ($ForceAx) {
            Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "802.11n/ac/ax Wireless Mode" -Desired "802.11ax" -ChangedList ([ref]$changed) -OrigMap $origAdv
        }
        else {
            Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName "802.11n/ac/ax Wireless Mode" -Desired "802.11ac" -ChangedList ([ref]$changed) -OrigMap $origAdv
        }

        Write-Log -Message "Restarting adapter to apply changes..." -LogPath $logPath
        if ($PSCmdlet.ShouldProcess($Adapter.Name, "Restart adapter")) {
            Disable-NetAdapter -Name $Adapter.Name -Confirm:$false
            Start-Sleep 3
            Enable-NetAdapter  -Name $Adapter.Name -Confirm:$false
            Start-Sleep 5
        }
    }
    catch {
        Write-Log -Message "Optimization failed; rolling back $($changed.Count) change(s)..." -Level "WARN" -LogPath $logPath
        for ($i = $changed.Count - 1; $i -ge 0; $i--) {
            $it = $changed[$i]
            Invoke-SafeCommand -Block { 
                Set-NetAdapterAdvancedProperty -Name $Adapter.Name -DisplayName $it.Name -DisplayValue $it.From -NoRestart -ErrorAction Stop
                Write-Log -Message "Rolled back '$($it.Name)' to '$($it.From)'." -LogPath $logPath
            } -Context "rollback:$($it.Name)"
        }
        throw
    }
}

function Restore-FromJson {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Microsoft.Management.Infrastructure.CimInstance]$Adapter,
        [string]$JsonPath
    )
    if (-not (Test-IsAdmin)) {
        throw "Administrator privileges are required to restore adapter advanced properties. Run PowerShell as Administrator."
    }
    if (-not (Test-Path $JsonPath)) { throw "Restore file not found: $JsonPath" }
    $data = Get-Content -Raw -Path $JsonPath | ConvertFrom-Json
    if (-not $data.AdvancedMap) { throw "No AdvancedMap in restore file." }

    Write-Log -Message "Restoring advanced properties from '$JsonPath'..." -LogPath $logPath
    foreach ($k in $data.AdvancedMap.PSObject.Properties.Name) {
        $desired = $data.AdvancedMap.$k
        $dummy = New-Object System.Collections.ArrayList # not tracking in restore
        Set-AdvPropSafe -AdapterName $Adapter.Name -DisplayName $k -Desired $desired -ChangedList ([ref]$dummy) -OrigMap @{}
    }

    Write-Log -Message "Restarting adapter after restore..." -LogPath $logPath
    if ($PSCmdlet.ShouldProcess($Adapter.Name, "Restart adapter")) {
        Disable-NetAdapter -Name $Adapter.Name -Confirm:$false
        Start-Sleep 3
        Enable-NetAdapter  -Name $Adapter.Name -Confirm:$false
        Start-Sleep 5
    }
}

# --------------------------- Monitor (embedded) --------------------------- #
function Start-WifiMonitor([string]$CsvPath, [int]$IntervalSec, [int]$DurationSec) {
    Write-Log -Message "Monitor starting: Interval=${IntervalSec}s Duration=${DurationSec}s -> $CsvPath" -LogPath $logPath
    $header = @(
        'Timestamp', 'SSID', 'BSSID', 'Channel', 'RadioType', 'SignalPct', 'TxMbps', 'RxMbps',
        'IPv4', 'GatewayV4', 'PingTarget', 'PingOk', 'PingMs'
    ) -join ','
    
    # Ensure directory exists
    $csvDir = Split-Path -Parent $CsvPath
    if (-not (Test-Path $csvDir)) {
        $oldWhatIf = $WhatIfPreference
        $WhatIfPreference = $false
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
        $WhatIfPreference = $oldWhatIf
    }
    
    # Create CSV file
    $oldWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    Set-Content -Path $CsvPath -Value $header
    $WhatIfPreference = $oldWhatIf

    $targets = @("192.168.1.1", "8.8.8.8")
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $DurationSec) {
        $raw = Invoke-SafeCommand -Block { netsh wlan show interfaces } -Context "netsh wlan show interfaces"
        $wifi = [pscustomobject]@{ SSID = $null; BSSID = $null; Channel = $null; RadioType = $null; SignalPct = $null; TxRateMbps = $null; RxRateMbps = $null }
        if ($raw) {
            $wifi = [pscustomobject]@{
                SSID       = ($raw | Select-String "^\s*SSID\s*:\s*(.+)$" -AllMatches | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
                BSSID      = ($raw | Select-String "^\s*BSSID\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
                Channel    = ($raw | Select-String "^\s*Channel\s*:\s*(\d+)$" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
                RadioType  = ($raw | Select-String "^\s*Radio\s*type\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
                SignalPct  = ($raw | Select-String "^\s*Signal\s*:\s*(\d+)%" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
                TxRateMbps = ($raw | Select-String "^\s*Transmit\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
                RxRateMbps = ($raw | Select-String "^\s*Receive\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
            }
        }

        $ipcfg = Invoke-SafeCommand -Block { Get-NetIPConfiguration -InterfaceAlias $InterfaceName } -Context "Get-NetIPConfiguration"
        $ipv4 = $null; $gw4 = $null
        if ($ipcfg) {
            try { if ($ipcfg.IPv4Address) { $ipv4 = $ipcfg.IPv4Address.IPAddress | Select-Object -First 1 } } catch {}
            try { if ($ipcfg.IPv4DefaultGateway) { $gw4 = $ipcfg.IPv4DefaultGateway.NextHop | Select-Object -First 1 } } catch {}
        }

        foreach ($t in $targets) {
            $ok = $false; $lat = $null
            try {
                $resp = Test-Connection -TargetName $t -Count 1 -ErrorAction Stop | Select-Object -First 1
                if ($null -ne (Get-Member -InputObject $resp -Name Latency -ErrorAction SilentlyContinue)) {
                    $lat = [int]$resp.Latency
                }
                elseif ($null -ne (Get-Member -InputObject $resp -Name ResponseTime -ErrorAction SilentlyContinue)) {
                    $lat = [int]$resp.ResponseTime
                }
                $ok = $true
            }
            catch { $ok = $false }

            $row = @(
                (Get-Date).ToString("o"),
                ($wifi.SSID -replace ',', ';'),
                ($wifi.BSSID -replace ',', ';'),
                $wifi.Channel,
                ($wifi.RadioType -replace ',', ';'),
                $wifi.SignalPct,
                $wifi.TxRateMbps,
                $wifi.RxRateMbps,
                $ipv4,
                $gw4,
                $t, $ok, $lat
            ) -join ','
            $oldWhatIf = $WhatIfPreference
            $WhatIfPreference = $false
            Add-Content -Path $CsvPath -Value $row
            $WhatIfPreference = $oldWhatIf
        }

        Start-Sleep -Seconds $IntervalSec
    }
    Write-Log -Message "Monitor complete: $CsvPath" -LogPath $logPath
}

# --------------------------- Compare report hook --------------------------- #
function Invoke-CompareReport([string]$RunDir) {
  try {
    # Check if the RunDir exists and contains the required files
    if (-not (Test-Path $RunDir)) {
      Write-Log -Message "Run directory not found: $RunDir" -Level "ERROR" -LogPath $logPath
      return
    }
    
    $preCsv = Join-Path $RunDir "pre-monitor.csv"
    $postCsv = Join-Path $RunDir "post-monitor.csv"
    
    if (-not (Test-Path $preCsv)) {
      Write-Log -Message "Pre-monitor CSV not found: $preCsv" -Level "ERROR" -LogPath $logPath
      return
    }
    
    if (-not (Test-Path $postCsv)) {
      Write-Log -Message "Post-monitor CSV not found: $postCsv" -Level "ERROR" -LogPath $logPath
      return
    }
    
    $thisScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $generateReportPath = Join-Path $thisScriptDir "Generate-Report.ps1"
    
    if (Test-Path $generateReportPath) {
      Write-Log -Message "Running Generate-Report.ps1 for run dir: $RunDir ..." -LogPath $logPath
      
      # Run the Generate-Report.ps1 script with the RunDir, Interval, and SampleLength parameters
      $oldWhatIf = $WhatIfPreference
      $WhatIfPreference = $false
      & $generateReportPath -RunDir $RunDir -Interval $IntervalSeconds -SampleLength $DurationSeconds
      $WhatIfPreference = $oldWhatIf
      
      $htmlPath = Join-Path $RunDir "compare-report.html"
      if (Test-Path $htmlPath) {
        Write-Log -Message "Opening HTML report: $htmlPath" -LogPath $logPath
        Start-Process $htmlPath
      } else {
        Write-Log -Message "compare-report.html not found in $RunDir." -Level "WARN" -LogPath $logPath
      }
    } else {
      # Fall back to the old Compare-Monitors.ps1 script
      $comparePath = Join-Path $thisScriptDir "Compare-Monitors.ps1"
      if (-not (Test-Path $comparePath)) {
        Write-Log -Message "Neither Generate-Report.ps1 nor Compare-Monitors.ps1 found; skipping auto-compare." -Level "WARN" -LogPath $logPath
        return
      }
      
      Write-Log -Message "Running Compare-Monitors.ps1 for run dir: $RunDir ..." -LogPath $logPath
      
      # Run the Compare-Monitors.ps1 script directly with the RunDir parameter
      $oldWhatIf = $WhatIfPreference
      $WhatIfPreference = $false
      & $comparePath -RunDir $RunDir
      $WhatIfPreference = $oldWhatIf
      
      $htmlPath = Join-Path $RunDir "compare-report.html"
      if (Test-Path $htmlPath) {
        Write-Log -Message "Opening HTML report: $htmlPath" -LogPath $logPath
        Start-Process $htmlPath
      } else {
        Write-Log -Message "compare-report.html not found in $RunDir." -Level "WARN" -LogPath $logPath
      }
    }
  }
  catch {
    Write-Log -Message "Compare step failed: $($_.Exception.Message)" -Level "ERROR" -LogPath $logPath
  }
}

# --------------------------- Main Flow --------------------------- #
$adapter = Get-Adapter
Write-Log -Message "Using adapter: $($adapter.InterfaceDescription) (alias: $($adapter.Name))" -LogPath $logPath

# Driver/report snapshot
$driverRep = Get-DriverReport -Adapter $adapter
Save-Json $driverRep (Join-Path $runDir "driver-report.json")

# Backup current settings
$origJson = Join-Path $runDir "original-settings.json"
Backup-Settings -Adapter $adapter -OutPath $origJson

# Pre-change monitor (always)
$preCsv = Join-Path $runDir "pre-monitor.csv"
Start-WifiMonitor -CsvPath $preCsv -IntervalSec $IntervalSeconds -DurationSec $DurationSeconds

# Restore-only flow -> produce standard post-monitor.csv then compare
if ($RestoreFrom) {
    Write-Log -Message "Restore requested from: $RestoreFrom" -LogPath $logPath
    Restore-FromJson -Adapter $adapter -JsonPath $RestoreFrom

    $postRestoreCsv = Join-Path $runDir "post-monitor.csv"
    Start-WifiMonitor -CsvPath $postRestoreCsv -IntervalSec $IntervalSeconds -DurationSec $DurationSeconds

    Invoke-CompareReport -RunDir $runDir

    Write-Log -Message "Restore flow complete." -LogPath $logPath
    Write-Host "`nArtifacts:`n  $runDir" -ForegroundColor Cyan
    exit 0
}

# Optimization flow -> apply, snapshot, post-monitor, compare
if ($Optimize) {
    Set-WifiOptimization -Adapter $adapter -ForceAx:$ForceAx

    $appliedJson = Join-Path $runDir "applied-settings.json"
    Backup-Settings -Adapter $adapter -OutPath $appliedJson

    $postCsv = Join-Path $runDir "post-monitor.csv"
    Start-WifiMonitor -CsvPath $postCsv -IntervalSec $IntervalSeconds -DurationSec $DurationSeconds

    Invoke-CompareReport -RunDir $runDir

    Write-Log -Message "Optimization flow complete." -LogPath $logPath
}
else {
    Write-Log -Message "Optimize flag not set; skipping optimization." -LogPath $logPath
}

Write-Host "`nArtifacts:`n  $runDir" -ForegroundColor Cyan
