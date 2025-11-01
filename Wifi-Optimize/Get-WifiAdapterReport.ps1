<# 
.SYNOPSIS
  Collects Wi-Fi adapter (Intel AX201 or any Wi-Fi NIC) configuration/capabilities.

.DESCRIPTION
  - Driver: version, date, provider
  - Power management: AllowComputerToTurnOffDevice, wake settings (if available)
  - Advanced properties: 802.11n/ac/ax mode, Preferred Band, Channel Width (5GHz), Roaming Aggressiveness,
                        MIMO Power Save, Transmit Power (if exposed by the driver)
  - Capabilities: Radio types supported, Channel widths supported (from netsh)
  - Current link: SSID, BSSID, channel, Tx/Rx rates, signal, IPv4/IPv6, gateways, DNS
  - Outputs a summary to console and a JSON report alongside the script
#>

[CmdletBinding()]
param(
  [string]$InterfaceName = "Wi-Fi",
  [string]$ReportPath = "$PSScriptRoot\wifi-adapter-report.json"
)

$ErrorActionPreference = "Stop"

function Try-Exec([scriptblock]$Block) {
  try { & $Block } catch { $null }
}

# --- Locate adapter ---
$adapter = Try-Exec { Get-NetAdapter -Name $InterfaceName -ErrorAction Stop }
if (-not $adapter) {
  $wifiCandidates = Try-Exec { Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" -and $_.Status -eq "Up" } }
  if ($wifiCandidates -and $wifiCandidates.Count -ge 1) { $adapter = $wifiCandidates[0] }
}
if (-not $adapter) {
  Write-Host "Wi-Fi adapter not found. Try -InterfaceName <your Wi-Fi interface alias>." -ForegroundColor Yellow
  return
}

# --- Driver info ---
$driverInfo = [ordered]@{
  Name          = $adapter.Name
  InterfaceDesc = $adapter.InterfaceDescription
  DriverVersion = $adapter.DriverVersion
  DriverDate    = $adapter.DriverInformation.Split(';') | Where-Object { $_ -match 'Date' } | Select-Object -First 1
  DriverProvider= ($adapter.DriverInformation.Split(';') | Where-Object { $_ -match 'Provider' } | Select-Object -First 1)
}

# --- Power management (preferred API) ---
$pm = Try-Exec { Get-NetAdapterPowerManagement -Name $adapter.Name }
$pmReport = $null
if ($pm) {
  $pmReport = [ordered]@{
    AllowComputerToTurnOffDevice = $pm.AllowComputerToTurnOffDevice
    DeviceSleepOnDisconnect      = $pm.DeviceSleepOnDisconnect
    WakeOnMagicPacket            = $pm.WakeOnMagicPacket
    WakeOnPattern                = $pm.WakeOnPattern
    PacketCoalescing             = $pm.PacketCoalescing
  }
} else {
  # Fallback (older builds): cannot reliably fetch the “Allow computer to turn off” state without enumerating PnP instance registry.
  $pmReport = @{ Note = "Get-NetAdapterPowerManagement not available; cannot query power checkbox on this OS/PowerShell." }
}

# --- Advanced properties of interest ---
$wantedProps = @(
  "802.11n/ac/ax Wireless Mode",
  "Preferred Band",
  "Channel Width for 5GHz",
  "Roaming Aggressiveness",
  "MIMO Power Save Mode",
  "Transmit Power"
)

$advRaw = Try-Exec { Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction Stop }
$advReport = @{}
if ($advRaw) {
  foreach ($n in $wantedProps) {
    $hit = $advRaw | Where-Object { $_.DisplayName -eq $n } | Select-Object -First 1
    if ($hit) { $advReport[$n] = $hit.DisplayValue } else { $advReport[$n] = $null }
  }
} else {
  $advReport = @{ Note = "Advanced properties not available (driver/OEM may limit or PowerShell module missing)." }
}

# --- netsh capabilities (channel width support, radio types) ---
$drvTxt = Try-Exec { netsh wlan show drivers }
$capReport = @{}
if ($drvTxt) {
  $radioTypes = ($drvTxt | Select-String -Pattern "Radio types supported\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
  $chanWidths = ($drvTxt | Select-String -Pattern "Channel widths supported\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
  $capReport = [ordered]@{
    RadioTypesSupported   = $radioTypes
    ChannelWidthsSupported= $chanWidths
  }
} else {
  $capReport = @{ Note = "Could not read netsh capabilities (non-fatal)." }
}

# --- Current link snapshot ---
function Get-WifiInfo {
  $raw = Try-Exec { netsh wlan show interfaces }
  if (-not $raw) { return $null }
  $o = [ordered]@{}
  $o.SSID        = ($raw | Select-String "^\s*SSID\s*:\s*(.+)$" -AllMatches | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
  $o.BSSID       = ($raw | Select-String "^\s*BSSID\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
  $o.SignalPct   = ($raw | Select-String "^\s*Signal\s*:\s*(\d+)%" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
  $o.RadioType   = ($raw | Select-String "^\s*Radio\s*type\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Select-Object -First 1)
  $o.Channel     = ($raw | Select-String "^\s*Channel\s*:\s*(\d+)$" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
  $o.RxRateMbps  = ($raw | Select-String "^\s*Receive\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
  $o.TxRateMbps  = ($raw | Select-String "^\s*Transmit\s*rate\s*\(Mbps\)\s*:\s*(\d+)" | ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -First 1)
  if ($o.SignalPct -is [int]) { $o.EstRssiDbm = [int](($o.SignalPct / 2) - 100) } else { $o.EstRssiDbm = $null }
  return [pscustomobject]$o
}

$wifi = Get-WifiInfo

# IP layer snapshot
$netcfg = Try-Exec { Get-NetIPConfiguration -InterfaceAlias $adapter.Name }
$ipReport = $null
if ($netcfg) {
  $ipv4 = $null; $ipv6 = $null; $gw4 = $null; $gw6 = $null; $dnsList = @(); $dhcp = $null
  if ($netcfg.IPv4Address) { $ipv4 = $netcfg.IPv4Address.IPAddress | Select-Object -First 1 }
  if ($netcfg.IPv6Address) { $ipv6 = ($netcfg.IPv6Address.IPAddress | Where-Object { $_ -notmatch "^fe80:" } | Select-Object -First 1) }
  if ($netcfg.IPv4DefaultGateway) { $gw4 = $netcfg.IPv4DefaultGateway.NextHop | Select-Object -First 1 }
  if ($netcfg.IPv6DefaultGateway) { $gw6 = $netcfg.IPv6DefaultGateway.NextHop | Select-Object -First 1 }
  if ($netcfg.DNSServer) { $dnsList = @($netcfg.DNSServer.ServerAddresses) }
  $dhcp = $netcfg.DhcpServer | Select-Object -First 1

  $ipReport = [ordered]@{
    IPv4       = $ipv4
    IPv6       = $ipv6
    GatewayV4  = $gw4
    GatewayV6  = $gw6
    DnsServers = ($dnsList -join ";")
    DhcpServer = $dhcp
  }
}

# --- Build final report ---
$report = [ordered]@{
  Timestamp        = (Get-Date).ToString("o")
  Adapter          = $driverInfo
  PowerManagement  = $pmReport
  AdvancedProps    = $advReport
  Capabilities     = $capReport
  CurrentWifiLink  = $wifi
  CurrentIP        = $ipReport
}

# Output
$report | ConvertTo-Json -Depth 6 | Tee-Object -FilePath $ReportPath | Out-Null

Write-Host "`n==== Wi-Fi Adapter Report Summary ====" -ForegroundColor Cyan
"{0,-22} {1}" -f "Adapter:", $driverInfo.Name
"{0,-22} {1}" -f "Driver Version:", $driverInfo.DriverVersion
"{0,-22} {1}" -f "Power Mgmt (allow off):", ($pmReport.AllowComputerToTurnOffDevice)
"{0,-22} {1}" -f "802.11 Mode:", $advReport.'802.11n/ac/ax Wireless Mode'
"{0,-22} {1}" -f "Preferred Band:", $advReport.'Preferred Band'
"{0,-22} {1}" -f "5 GHz Width:", $advReport.'Channel Width for 5GHz'
"{0,-22} {1}" -f "Roaming Aggress.:", $advReport.'Roaming Aggressiveness'
"{0,-22} {1}" -f "MIMO Power Save:", $advReport.'MIMO Power Save Mode'
"{0,-22} {1}" -f "Transmit Power:", $advReport.'Transmit Power'
"{0,-22} {1}" -f "Radio types:", $capReport.RadioTypesSupported
"{0,-22} {1}" -f "Widths supported:", $capReport.ChannelWidthsSupported
if ($wifi) {
  "{0,-22} {1}" -f "SSID / BSSID:", "$($wifi.SSID) / $($wifi.BSSID)"
  "{0,-22} {1}" -f "Channel / Radio:", "$($wifi.Channel) / $($wifi.RadioType)"
  "{0,-22} {1}" -f "Sig% / RSSI:", "$($wifi.SignalPct)% / $($wifi.EstRssiDbm) dBm"
  "{0,-22} {1}" -f "Tx/Rx Mbps:", "$($wifi.TxRateMbps)/$($wifi.RxRateMbps)"
}
if ($ipReport) {
  "{0,-22} {1}" -f "IPv4 / GWv4:", "$($ipReport.IPv4) / $($ipReport.GatewayV4)"
  "{0,-22} {1}" -f "IPv6 / GWv6:", "$($ipReport.IPv6) / $($ipReport.GatewayV6)"
  "{0,-22} {1}" -f "DNS:", $ipReport.DnsServers
}
Write-Host "`nFull JSON written to: $ReportPath"
