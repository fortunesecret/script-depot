# Wifi-Optimize Suite

A collection of PowerShell scripts for diagnosing and optimizing Wi-Fi connections on Windows.

## Scripts

### Diagnose-Wifi.ps1

Diagnoses Wi-Fi issues and applies optimizations:

- Creates a timestamped run directory under `$HOME\WifiSuite\<timestamp>\`
- Snapshots current adapter/driver/advanced/power settings to JSON
- Runs a pre-change monitor (default 180s @ 1s)
- If `-Optimize`: applies recommended settings (admin required), snapshots them, runs post monitor
- If `-RestoreFrom <json>`: restores prior advanced settings (admin required), runs post monitor
- Auto-compares pre/post and opens compare-report.html

```powershell
# Examples
.\Diagnose-Wifi.ps1
.\Diagnose-Wifi.ps1 -Optimize
.\Diagnose-Wifi.ps1 -IntervalSeconds 1 -DurationSeconds 180 -Optimize
.\Diagnose-Wifi.ps1 -RestoreFrom "$HOME\WifiSuite\20251101-104750\original-settings.json"
```

### Parameters

- **InterfaceName**: Wi-Fi interface alias (default: "Wi-Fi")
- **IntervalSeconds**: Sampling interval for monitor in seconds (default: 1)
- **DurationSeconds**: Duration of each monitoring pass in seconds (default: 180)
- **Optimize**: Apply safe optimization preset after the pre-change monitor, then monitor again
- **RestoreFrom**: JSON file produced by a previous run to restore advanced properties from
- **ForceAx**: Keep 802.11ax when optimizing (default: off → prefer 802.11ac for stability)

### Compare-Monitors.ps1

Compares two Wi-Fi monitor CSVs (pre vs post), prints deltas, and emits JSON + HTML reports:

- Reads monitor CSVs produced by Diagnose-Wifi.ps1 (pre-monitor.csv/post-monitor.csv)
- Summarizes time window, signal avg/min/max, loss %, avg latency, longest fail streak
- Writes compare-report.json and compare-report.html

```powershell
# Examples
.\Compare-Monitors.ps1
.\Compare-Monitors.ps1 -RunDir "$HOME\WifiSuite\20251101-104750"
```

### Generate-Report.ps1

Generates HTML and JSON reports for Wi-Fi monitoring results:

- Automatically finds the latest run with pre/post monitor CSVs if no RunDir is specified
- Analyzes signal strength, ping loss, and latency
- Generates detailed HTML report with interactive charts
- Provides verdict on whether Wi-Fi performance improved or worsened

```powershell
# Examples
.\Generate-Report.ps1                                # Uses latest run
.\Generate-Report.ps1 -RunDir "$HOME\WifiSuite\20251101-121027"
.\Generate-Report.ps1 -Interval 1 -SampleLength 180  # Specify interval and sample length
```

#### Parameters

- **RunDir**: Directory containing pre/post monitor CSVs (optional, auto-detects latest if omitted)
- **Interval**: Sampling interval in seconds (default: 1)
- **SampleLength**: Duration of monitoring in seconds (default: 180)

### Get-WifiAdapterReport.ps1

Collects Wi-Fi adapter configuration and capabilities:

- Driver: version, date, provider
- Power management settings
- Advanced properties
- Capabilities from netsh
- Current link information
- Outputs a summary to console and a JSON report

```powershell
# Examples
.\Get-WifiAdapterReport.ps1
.\Get-WifiAdapterReport.ps1 -InterfaceName "Wi-Fi 2"
```

## Modules

The suite has been refactored to use modular PowerShell modules:

### WifiUtils.psm1

Common utility functions:

- Type conversion functions
- Logging functions
- File operations
- Execution helpers

### WifiDataProcessing.psm1

Data processing functions:

- Ping statistics
- Capture summary
- Delta reporting
- Chart data generation

### HtmlTemplates.psm1

HTML templates for reports:

- Compare report HTML template

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator privileges for optimization and restore operations
