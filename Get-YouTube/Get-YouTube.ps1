<#
.SYNOPSIS
  Download a YouTube video at best quality (video or audio-only) and save/convert to a given path.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Url,

  [Parameter(Mandatory=$true,
             HelpMessage="Either a directory (auto filename) or an explicit output file path.")]
  [string]$Output,

  [switch]$AudioOnly,

  [ValidateSet('wav','mp3','m4a','flac','opus')]
  [string]$AudioFormat = 'wav',

  [ValidateRange(8000, 192000)]
  [int]$SampleRate = 44100,

  [switch]$Overwrite,        # Allow overwriting existing files
  [switch]$NoThumbnail,      # Skip embedding thumbnails
  [switch]$VerboseLogs,      # Print full yt-dlp command
  [switch]$ListFormats,      # Show formats yt-dlp sees then exit
  [ValidateSet('android','web','ios','mweb','tvhtml5')]
  [string]$Client = 'android'  # default client; avoids TV/SABR issues
)

function Assert-Tool {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required tool '$Name' not found on PATH. Install it and try again."
  }
}

function Test-IsDirectoryIntent {
  param([string]$Path)
  if ($Path -match '[\\/]\s*$') { return $true }
  if (Test-Path $Path -PathType Container) { return $true }
  if (-not ([IO.Path]::HasExtension($Path))) { return $true }
  return $false
}

function New-Directory {
  param([string]$Dir)
  if ($Dir -and -not (Test-Path $Dir -PathType Container)) {
    New-Item -ItemType Directory -Path $Dir | Out-Null
  }
}

function Build-CommonArgs {
  param([string]$ExtractorClient,[switch]$ListOnly)
  $a = @(
    "--no-playlist"
    "--ignore-errors"
    "--progress"
    "--extractor-args", "youtube:player_client=$ExtractorClient"
  )
  if ($VerboseLogs) { $a += "--verbose" }
  if (-not $NoThumbnail) { $a += "--embed-thumbnail" }
  if ($Overwrite) { $a += @("--no-continue","--no-part","--force-overwrites") }
  if ($ListOnly) { $a += "-F" } # list formats
  return $a
}

try {
  Assert-Tool yt-dlp
  Assert-Tool ffmpeg

  # Some share links include ?si=… tracking. Strip it—it’s harmless if left, but cleaner without.
  $Url = $Url -replace '\?si=[^&]+$',''

  $isDir = Test-IsDirectoryIntent $Output

  # Build the per-mode args (without client yet)
  if ($AudioOnly) {
    $ppArgs = "ffmpeg:-ar $SampleRate"
    $af = $AudioFormat

    if ($isDir) {
      New-Directory $Output
      $template = Join-Path $Output "%(title).200B-%(id)s.%(ext)s"
      $modeArgs = @(
        $Url
        "-o", $template
        "-f", "bestaudio/best"
        "-x", "--audio-format", $af, "--audio-quality", "0"
        "--postprocessor-args", $ppArgs
      )
    } else {
      $ext = [IO.Path]::GetExtension($Output).TrimStart('.').ToLowerInvariant()
      if (-not $ext) { throw "When using -AudioOnly with a file path, include an extension like .mp3, .m4a, .wav, .flac, or .opus." }
      if ($ext -ne $af) {
        Write-Host "Note: Changing audio format from '$af' to match file extension '.$ext'."
        $af = $ext
      }
      $dir = [IO.Path]::GetDirectoryName($Output)
      if ($dir) { New-Directory $dir }
      $parent = if ([string]::IsNullOrWhiteSpace($dir)) { "." } else { $dir }
      $baseNoExt = [IO.Path]::Combine($parent, [IO.Path]::GetFileNameWithoutExtension($Output))
      $template = "$baseNoExt.%(ext)s"

      $modeArgs = @(
        $Url
        "-o", $template
        "-f", "bestaudio/best"
        "-x", "--audio-format", $af, "--audio-quality", "0"
        "--postprocessor-args", $ppArgs
      )
    }
  } else {
    if ($isDir) {
      New-Directory $Output
      $template = Join-Path $Output "%(title).200B-%(id)s.%(ext)s"
      $modeArgs = @(
        $Url
        "-o", $template
        "-f", "bv*+ba/b"
        "--merge-output-format", "mp4"
        "--remux-video", "mp4"
      )
    } else {
      $dir = [IO.Path]::GetDirectoryName($Output)
      if ($dir) { New-Directory $dir }

      $ext = ([IO.Path]::GetExtension($Output).TrimStart('.').ToLowerInvariant())
      if (-not $ext) { $ext = "mp4" }
      $validFormats = @('mp4','mkv','webm')
      $mergeFmt = if ($validFormats -contains $ext) { $ext } else { "mp4" }

      $parent = if ([string]::IsNullOrWhiteSpace($dir)) { "." } else { $dir }
      $baseNoExt = [IO.Path]::Combine($parent, [IO.Path]::GetFileNameWithoutExtension($Output))
      $template = "$baseNoExt.%(ext)s"

      $modeArgs = @(
        $Url
        "-o", $template
        "-f", "bv*+ba/b"
        "--merge-output-format", $mergeFmt
      )
      if ($mergeFmt -eq 'mp4') { $modeArgs += @("--remux-video","mp4") }
    }
  }

  if ($ListFormats) {
    $common = Build-CommonArgs -ExtractorClient $Client -ListOnly
    if ($VerboseLogs) { Write-Host "yt-dlp" ($common + $modeArgs -join ' ') }
    & yt-dlp @common @modeArgs
    exit $LASTEXITCODE
  }

  # Try with preferred client, then fall back if SABR/nsig issues appear
  $clientCandidates = @($Client, 'android','web','ios','mweb') | Select-Object -Unique
  $lastCode = 1
  foreach ($c in $clientCandidates) {
    $common = Build-CommonArgs -ExtractorClient $c
    if ($VerboseLogs) { Write-Host "yt-dlp" ($common + $modeArgs -join ' ') }

    & yt-dlp @common @modeArgs
    $lastCode = $LASTEXITCODE

    if ($lastCode -eq 0) {
      Write-Host "`nDone (client=$c)."
      exit 0
    }

    # Heuristics: if SABR/images/nsig messages, try next client automatically
    # (yt-dlp writes warnings to stdout/stderr already; just rotate client)
    Write-Warning "yt-dlp failed with client='$c' (code $lastCode). Trying next client..."
  }

  throw "yt-dlp failed with all client options tried: $($clientCandidates -join ', ')"
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
