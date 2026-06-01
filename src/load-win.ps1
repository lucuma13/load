# Windows workstation setup script
# Usage: Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing | Invoke-Expression
# Flags: --full  --fast  --dry-run

$ErrorActionPreference = "Stop"

$ProgressDir = "$HOME\.win_setup"
New-Item -ItemType Directory -Force -Path $ProgressDir | Out-Null

function Mark-Done { param($step); New-Item -ItemType File -Force -Path "$ProgressDir\$step" | Out-Null }
function Is-Done   { param($step); Test-Path "$ProgressDir\$step" }

# ── Flags ─────────────────────────────────────────────────────────────────────

$FULL    = $args -contains "--full"
$FAST    = $args -contains "--fast"
$DRY_RUN = $args -contains "--dry-run"

# ── Preflight ─────────────────────────────────────────────────────────────────

$PREMIERE_OK = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
$WINGET_OK   = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$PKGS_DONE_OK = Is-Done "winget_packages"
$AHK_OK      = Is-Done "ahk"

$KB_Speed = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
$KB_Delay = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
$KB_OK    = ($KB_Speed -eq "31") -and ($KB_Delay -eq "0")

function winget_installed($id) {
    if (-not $WINGET_OK) { return $false }
    $result = winget list --id $id --accept-source-agreements 2>$null
    return $LASTEXITCODE -eq 0 -and ($result -match [regex]::Escape($id))
}

function uv_installed($pkg) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { return $false }
    return (uv tool list 2>$null) -match "^$pkg"
}

function Would-Run  { param($msg); Write-Host "  [run]   $msg" }
function Would-Skip { param($msg); Write-Host "  [skip]  $msg" }
function Already-Done { param($msg); Write-Host "  [done]  $msg" }

Write-Host ""

# Premiere shortcuts
if ($PREMIERE_OK) { Would-Run  "Premiere shortcuts" }
else              { Would-Skip "Premiere shortcuts — not installed" }

# Keyboard preferences
if ($KB_OK) { Already-Done "Keyboard preferences" }
else        { Would-Run    "Keyboard preferences" }

# winget packages
$CORE_PKGS = @(
    "astral-sh.uv",
    "MediaArea.MediaInfo",
    "MediaArea.MediaInfo.GUI",
    "OliverBetz.ExifTool",
    "Gyan.FFmpeg",
    "VideoLAN.VLC",
    "ZhornSoftware.Caffeine"
)
$FULL_PKGS = @(
    "AutoHotkey.AutoHotkey",
    "AtomicParsley.AtomicParsley",
    "Bento4.Bento4",
    "ImageMagick.ImageMagick",
    "Google.Chrome",
    "Audacity.Audacity"
)
$CORE_UV = @("triplecheck")

if ($FAST) {
    $all = $CORE_PKGS + $CORE_UV
    if ($FULL) { $all += $FULL_PKGS }
    Would-Skip ("managed packages (--fast) — " + ($all -join ", "))
} else {
    $PKG_LIST = $CORE_PKGS
    if ($FULL) { $PKG_LIST += $FULL_PKGS }

    $pkgs_done = @(); $pkgs_todo = @()
    foreach ($pkg in $PKG_LIST) {
        if (winget_installed $pkg) { $pkgs_done += $pkg } else { $pkgs_todo += $pkg }
    }
    foreach ($pkg in $CORE_UV) {
        if (uv_installed $pkg) { $pkgs_done += $pkg } else { $pkgs_todo += $pkg }
    }

    if ($pkgs_done.Count -gt 0) { Already-Done ("managed packages: " + ($pkgs_done -join ", ")) }
    if ($pkgs_todo.Count -gt 0) { Would-Run    ("managed packages: " + ($pkgs_todo -join ", ")) }
}

# AHK shortcuts
if ($AHK_OK) { Already-Done "AHK shortcuts" }
else         { Would-Run    "AHK shortcuts" }

Write-Host ""
if ($DRY_RUN) { exit 0 }

# ── Premiere Pro shortcuts ────────────────────────────────────────────────────

if ($PREMIERE_OK) {
    foreach ($dir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro" -Directory) {
        if (Test-Path "$($dir.FullName)\Profile-*\Win") {
            curl.exe -s --output-dir "$($dir.FullName)" -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/Luis_Mengo_25.1_WINDOWS.kys"
        }
    }
}

# ── Keyboard preferences ─────────────────────────────────────────────────────

if (-not $KB_OK) {
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value 31
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 0
}

# ── Managed packages ──────────────────────────────────────────────────────────

if (-not $PKGS_DONE_OK -and -not $FAST) {
    foreach ($pkg in $CORE_PKGS) {
        winget install $pkg --accept-package-agreements --accept-source-agreements
    }
    # Refresh PATH so newly installed tools (uv, etc.) are available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($pkg in $CORE_UV) {
        uv tool install $pkg
    }
    # Add uv's tool bin dir to PATH permanently and refresh for this session
    uv tool update-shell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    Mark-Done "winget_packages"
}

if ($FULL -and -not (Is-Done "winget_packages_full") -and -not $FAST) {
    foreach ($pkg in $FULL_PKGS) {
        winget install $pkg --accept-package-agreements --accept-source-agreements
    }
    Mark-Done "winget_packages_full"
}

# ── AHK shortcuts ─────────────────────────────────────────────────────────────

if (-not $AHK_OK) {
    $ahkExe = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $ahkExe) {
        $ahkExe = @(
            "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
            "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $ahkExe) {
        Write-Host "  ⚠️  AutoHotkey not found — skipping AHK shortcuts"
    } else {
        $ahkPath = "$HOME\Downloads\MacKeyboard_LM.ahk"
        curl.exe -s -o $ahkPath "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/MacKeyboard_LM.ahk"
        Start-Process $ahkExe -ArgumentList $ahkPath -Verb RunAs
        Mark-Done "ahk"
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  You're ready to roll!"
Write-Host ""