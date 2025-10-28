# Get-YouTube.ps1
A PowerShell script for downloading YouTube videos or audio at the best available quality using **yt-dlp** and **FFmpeg**.

---

## Requirements

### 1) PowerShell 5.1 or later
Check your version:
```powershell
$PSVersionTable.PSVersion
```

If below 5.1, install the latest version:

- Microsoft Store: https://aka.ms/PowerShell  
- Winget:
```powershell
winget install --id Microsoft.PowerShell
```

---

### 2) yt-dlp (Required)
yt-dlp is the maintained fork of youtube-dl.

Install with one of the following methods.

**Option A – Winget (Recommended)**
```powershell
winget install -e --id yt-dlp.yt-dlp
```

**Option B – Chocolatey**
```powershell
choco install yt-dlp
```

**Option C – Manual**
1. Download the latest yt-dlp.exe from  
   https://github.com/yt-dlp/yt-dlp/releases/latest  
2. Place it in a directory in your PATH (for example, `C:\Tools` or `C:\Windows`).

Verify:
```powershell
yt-dlp --version
```

---

### 3) FFmpeg (Required for merging or audio extraction)

**Option A – Winget**
```powershell
winget install -e --id Gyan.FFmpeg
```

**Option B – Chocolatey**
```powershell
choco install ffmpeg
```

Verify:
```powershell
ffmpeg -version
```

---

## Usage

```powershell
.\Get-YouTube.ps1 -Url "<YouTube URL>" -Output "<FolderOrFile>" [options]
```

---

## Examples

**Best video + audio**
```powershell
.\Get-YouTube.ps1 -Url "https://youtu.be/dQw4w9WgXcQ" -Output "C:\Media"
```
Downloads the video and saves it as:
```
C:\Media\<title>-<id>.mp4
```

**Audio-only (MP3, 48 kHz)**
```powershell
.\Get-YouTube.ps1 -Url "https://youtu.be/dQw4w9WgXcQ" -Output "C:\Audio\song.mp3" -AudioOnly -AudioFormat mp3 -SampleRate 48000
```

**List available formats**
```powershell
.\Get-YouTube.ps1 -Url "https://youtu.be/dQw4w9WgXcQ" -Output "." -ListFormats
```

---

## Parameters

| Parameter       | Description                                                                                  |
|-----------------|----------------------------------------------------------------------------------------------|
| `-Url`          | YouTube video URL (required).                                                                |
| `-Output`       | Directory or full path to save the file.                                                     |
| `-AudioOnly`    | Extracts audio only.                                                                          |
| `-AudioFormat`  | Output format: `wav`, `mp3`, `m4a`, `flac`, `opus`. Default is `wav`.                        |
| `-SampleRate`   | Audio sample rate in Hz (8000–192000). Default is `44100`.                                   |
| `-Overwrite`    | Allows overwriting existing files.                                                           |
| `-NoThumbnail`  | Skips embedding thumbnails.                                                                  |
| `-VerboseLogs`  | Prints full yt-dlp command output.                                                           |
| `-ListFormats`  | Lists available formats for a video and exits.                                               |
| `-Client`       | Sets the extractor client (`android`, `web`, `ios`, `mweb`, etc.) to avoid SABR/nsig issues. |

---

## Troubleshooting

**nsig extraction failed / Only images available**  
YouTube changed its player signing. Update yt-dlp:
```powershell
yt-dlp -U
```
The script also retries with alternative client modes (`android`, `web`, `ios`, `mweb`).

**ffmpeg not found**  
Install FFmpeg as shown above and ensure it is in your PATH.

**Execution Policy blocks the script**  
Right-click the script, choose Properties, and select Unblock.  
Or allow local scripts:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Optional Features

**Use cookies for private or unlisted videos**  
Add this to the yt-dlp invocation inside the script as needed:
```
--cookies-from-browser chrome
```

**Batch download from a list**  
Create `urls.txt` with one URL per line:
```powershell
Get-Content .\urls.txt | ForEach-Object {
    .\Get-YouTube.ps1 -Url $_ -Output "C:\Downloads"
}
```

---

## Verify Installation
Run these commands to ensure everything is available:
```powershell
yt-dlp --version
ffmpeg -version
$PSVersionTable.PSVersion
```

All three should return valid output.

---

## Metadata
Author: Chase  
License: MIT  
Dependencies: yt-dlp, FFmpeg  
Version: 1.1.0
