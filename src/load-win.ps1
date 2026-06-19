# Windows workstation setup script
# Usage: Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing | Invoke-Expression
# Flags: --full  --fast  --dry-run

$ErrorActionPreference = "Stop"

$ProgressDir = "$HOME\.win_setup"
New-Item -ItemType Directory -Force -Path $ProgressDir | Out-Null

function Mark-Done { param($step); New-Item -ItemType File -Force -Path "$ProgressDir\$step" | Out-Null }
function Is-Done   { param($step); Test-Path "$ProgressDir\$step" }

# -----------------------------------------------------------------------------
# Flags
# -----------------------------------------------------------------------------

$FULL    = $args -contains "--full"
$FAST    = $args -contains "--fast"
$DRY_RUN = $args -contains "--dry-run"

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

$PREMIERE_OK = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
$WINGET_OK   = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
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

# Premiere shortcuts & workspace
if ($PREMIERE_OK) {
    Would-Run  "Premiere shortcuts"
    Would-Run  "Premiere workspace"
    if ($FAST) { Would-Skip "Premiere plugins (--fast)" }
    else       { Would-Run  "Premiere plugins — Animation Composer, Flicker Free" }
} else {
    Would-Skip "Premiere shortcuts — not installed"
    Would-Skip "Premiere workspace — not installed"
    Would-Skip "Premiere plugins — not installed"
}

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

    if ($pkgs_done.Count -gt 0) { Would-Run ("update managed packages: "  + ($pkgs_done -join ", ")) }
    if ($pkgs_todo.Count -gt 0) { Would-Run ("install managed packages: " + ($pkgs_todo -join ", ")) }
}

# AHK shortcuts
if ($AHK_OK)   { Already-Done "AHK shortcuts" }
elseif ($FAST) { Would-Skip   "AHK shortcuts (--fast)" }
else           { Would-Run    "AHK shortcuts" }

# LUTs
if ($FAST) { Would-Skip "LUTs (--fast)" }
else       { Would-Run  "LUTs" }

Write-Host ""
if ($DRY_RUN) { exit 0 }

# The lightweight config below runs before any slow download/install so that an
# interrupted run still leaves the quick changes applied. AHK is the exception —
# it needs AutoHotkey (a managed package), so it follows the package install.

# -----------------------------------------------------------------------------
# Premiere Pro shortcuts & workspace
# -----------------------------------------------------------------------------

if ($PREMIERE_OK) {
    # Drop the shortcuts
    foreach ($dir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro" -Directory) {
        if (Test-Path "$($dir.FullName)\Profile-*\Win") {
            curl.exe -s --output-dir "$($dir.FullName)" -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/Luis_Mengo_25.1_WINDOWS.kys"
        }
    }

    # Drop the workspace into every Profile's Layouts folder (any version, any Profile)
    foreach ($profileDir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro\*\Profile-*" -Directory -ErrorAction SilentlyContinue) {
        $layouts = Join-Path $profileDir.FullName "Layouts"
        New-Item -ItemType Directory -Force -Path $layouts | Out-Null
        curl.exe -s --output-dir "$layouts" -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/UserWorkspace_LGG.xml"
    }
}

# -----------------------------------------------------------------------------
# Keyboard preferences
# -----------------------------------------------------------------------------

if (-not $KB_OK) {
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value 31
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 0
}

# -----------------------------------------------------------------------------
# Managed packages
# -----------------------------------------------------------------------------

if (-not $FAST) {
    foreach ($pkg in $CORE_PKGS) {
        winget install $pkg --accept-package-agreements --accept-source-agreements
    }
    # Refresh PATH so newly installed tools (uv, etc.) are available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($pkg in $CORE_UV) {
        uv tool install $pkg --upgrade
    }
    # Add uv's tool bin dir to PATH permanently and refresh for this session
    uv tool update-shell
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

if ($FULL -and -not $FAST) {
    foreach ($pkg in $FULL_PKGS) {
        winget install $pkg --accept-package-agreements --accept-source-agreements
    }
    # Refresh PATH so newly installed tools (AutoHotkey, etc.) are available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# -----------------------------------------------------------------------------
# AHK macros (needs AutoHotkey, installed above with --full; skipped with --fast)
# -----------------------------------------------------------------------------

if (-not $AHK_OK -and -not $FAST) {
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

# -----------------------------------------------------------------------------
# Premiere plugins
# -----------------------------------------------------------------------------
# Mister Horse's Product Manager is the app that installs & updates Animation
# Composer (and the rest of the Mister Horse plugins) into Premiere/After
# Effects. We download the Product Manager installer and run it; Animation
# Composer itself is then installed from within the app on first launch.

if ($PREMIERE_OK -and -not $FAST) {
    $pmPath = "$HOME\Downloads\MisterHorseProductManager.msi"
    curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
    Start-Process msiexec.exe -ArgumentList "/i `"$pmPath`" /qn" -Verb RunAs -Wait

    # Flicker Free — Digital Anarchy's deflicker plugin. The download is a zip
    # wrapping the installer .exe; we extract it and run the installer.
    $ffZip = "$HOME\Downloads\flickerfree_229_AE.zip"
    $ffDir = "$HOME\Downloads\flickerfree_229_AE"
    curl.exe -fsSL -o $ffZip "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.zip"
    Expand-Archive -Path $ffZip -DestinationPath $ffDir -Force
    $ffExe = Get-ChildItem $ffDir -Filter *.exe | Select-Object -First 1
    if ($ffExe) { Start-Process $ffExe.FullName -Verb RunAs -Wait }
}

# -----------------------------------------------------------------------------
# LUTs
# -----------------------------------------------------------------------------
# Download every LUT in src/data/LUTs into ~\Downloads\LUTs (skipped --fast).
# The file list comes from the GitHub contents API, so new LUTs are picked up
# automatically without editing this script.

if (-not $FAST) {
    $lutDir = "$HOME\Downloads\LUTs"
    $lutApi = "https://api.github.com/repos/lucuma13/load/contents/src/data/LUTs?ref=main"
    New-Item -ItemType Directory -Force -Path $lutDir | Out-Null
    try {
        $luts = Invoke-RestMethod -Uri $lutApi -Headers @{ "User-Agent" = "load-setup" }
        foreach ($lut in $luts) {
            if ($lut.download_url) {
                curl.exe -s --output-dir "$lutDir" -O $lut.download_url
            }
        }
    } catch {
        Write-Host "  ⚠️  Could not fetch LUTs: $_"
    }
}

# -----------------------------------------------------------------------------
# Upgrade everything winget manages to the latest version
# -----------------------------------------------------------------------------

if (-not $FAST -and $WINGET_OK) {
    winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements
}

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "  You're ready to roll!"
Write-Host ""
