# Windows workstation setup script
# Usage: Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing | Invoke-Expression

$ErrorActionPreference = "Stop"

$ProgressDir = "$HOME\.win_setup"
New-Item -ItemType Directory -Force -Path $ProgressDir | Out-Null

function Mark-Done { param($step); New-Item -ItemType File -Force -Path "$ProgressDir\$step" | Out-Null }
function Is-Done  { param($step); Test-Path "$ProgressDir\$step" }

function Header {
  param($title)
  Write-Host ""
  Write-Host "──────────────────────────────────────────────────────────"
  Write-Host "  $title"
  Write-Host "──────────────────────────────────────────────────────────"
}

Write-Host ""
Write-Host "╔══════════════════════════════════════╗"
Write-Host "║   Windows Workstation Setup Script   ║"
Write-Host "╚══════════════════════════════════════╝"
Write-Host "Already-completed steps will be skipped."

# ── 1 · Premiere Pro shortcuts ────────────────────────────────────────────────

if (Is-Done "premiere") {
  Write-Host "✅  Premiere shortcuts already installed — skipping."
} else {
  Header "1 · Premiere Pro shortcuts"
  $premiereBase = "$HOME\Documents\Adobe\Premiere Pro"
  if (Test-Path $premiereBase) {
    foreach ($dir in Get-ChildItem $premiereBase -Directory) {
      if (Test-Path "$($dir.FullName)\Profile-*\Win") {
        curl.exe --output-dir "$($dir.FullName)" -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/Luis_Mengo_25.1_WINDOWS.kys"
      }
    }
  } else {
    Write-Host "⚠️  Premiere Pro directory not found — skipping shortcuts."
  }
  Mark-Done "premiere"
}

# ── 2 · winget packages ───────────────────────────────────────────────────────

if (Is-Done "winget_packages") {
  Write-Host "✅  winget packages already installed — skipping."
} else {
  Header "2 · Install packages via winget"
  $packages = @(
    "AutoHotkey.AutoHotkey",
    "astral-sh.uv",
    "MediaArea.MediaInfo",
    "MediaArea.MediaInfo.GUI",
    "OliverBetz.ExifTool",
    "Gyan.FFmpeg",
    "AtomicParsley.AtomicParsley",
    "Bento4.Bento4",
    "ImageMagick.ImageMagick",
    "Google.Chrome",
    "VideoLAN.VLC",
    "ZhornSoftware.Caffeine",
    "Audacity.Audacity"
  )
  foreach ($pkg in $packages) {
    Write-Host "`n▶ Installing $pkg..."
    winget install $pkg --accept-package-agreements --accept-source-agreements
  }
  Mark-Done "winget_packages"
}

# ── 3 · AHK shortcuts ─────────────────────────────────────────────────────────

if (Is-Done "ahk") {
  Write-Host "✅  AHK shortcuts already installed — skipping."
} else {
  Header "3 · AutoHotkey shortcuts"
  $ahkPath = "$HOME\Downloads\MacKeyboard_LM.ahk"
  curl.exe -o $ahkPath "https://raw.githubusercontent.com/lucuma13/load/main/src/data/MacKeyboard_LM.ahk"
  Start-Process "AutoHotkey.exe" -ArgumentList $ahkPath -Verb RunAs
  Mark-Done "ahk"
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════╗"
Write-Host "║           Setup complete! ✅          ║"
Write-Host "╚══════════════════════════════════════╝"
Write-Host ""
Write-Host "🗑️  Remove progress files when you're happy:"
Write-Host "    Remove-Item -Recurse $HOME\.win_setup"
Write-Host ""