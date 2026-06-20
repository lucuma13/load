# Windows workstation setup script
# Usage: Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing | Invoke-Expression
# Flags: --full  --fast  --dry-run

$ErrorActionPreference = "Stop"

$WorkDir = "$HOME\Downloads\load-win"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Mark-Done { param($step); New-Item -ItemType File -Force -Path "$WorkDir\$step" | Out-Null }
function Is-Done   { param($step); Test-Path "$WorkDir\$step" }

# Get-WorkspaceName <ws_file> — return the workspace display name from the XML file,
# stored under the UserName key.
function Get-WorkspaceName {
    param($wsFile)
    $content = [System.IO.File]::ReadAllText($wsFile)
    if ($content -match '<key>UserName</key>\s*<ustring>(.*?)</ustring>') { return $Matches[1] }
    return ""
}

# Set-PrefNode <prefs> <node> <value> — replace an XML leaf node's text in place.
# Returns $false WITHOUT touching the file when the node is absent, so callers
# can flag nodes a future Premiere version may have renamed (no edit = no corruption).
function Set-PrefNode {
    param($prefs, $node, $value)
    $bytes = [System.IO.File]::ReadAllBytes($prefs)
    if     ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
    else                                                                            { $enc = [System.Text.Encoding]::UTF8 }
    $content  = $enc.GetString($bytes)
    $open     = "<$node>"
    $close    = "</$node>"
    $idx      = $content.IndexOf($open)
    if ($idx -lt 0) { return $false }
    $closeIdx = $content.IndexOf($close, $idx + $open.Length)
    $new = $content.Substring(0, $idx + $open.Length) + $value + $content.Substring($closeIdx)
    [System.IO.File]::WriteAllBytes($prefs, $enc.GetBytes($new))
    return $true
}

# Apply-PremierePrefs <prefs> <kys_file> <ws_name> — point Premiere's prefs at
# the keyboard set + workspace, apply the Classic label preset, enable auto-save
# every 5 minutes, and turn on the timeline's Link Selection + Display Settings.
#
# A missing-node warning can mean one of two things:
#   (a) Fresh Premiere install — Premiere only writes certain nodes to disk after
#       a user first manually changes them (confirmed for the 8 timeline display
#       toggles, which default to true). Warning is harmless; the setting is
#       already at the correct value.
#   (b) Adobe renamed the node in this Premiere version — the setting was NOT
#       applied and the script needs updating.
# Either way the file is left untouched for that node.
function Apply-PremierePrefs {
    param($prefs, $kysFile, $wsName)
    $labelNames  = @('Violet','Iris','Caribbean','Lavender','Cerulean','Forest','Rose','Mango','Purple','Blue','Teal','Magenta','Tan','Green','Brown','Yellow')
    $labelColors = @('14717094','13408882','10016297','14910691','14597935','5814353','10776567','3909357','9896087','16727100','8421376','15151847','9814478','2191389','1262987','6611682')
    $missing = @()

    # Keyboard set
    if (-not (Set-PrefNode $prefs "FE.Prefs.Shortcuts.Filename" $kysFile)) { $missing += "FE.Prefs.Shortcuts.Filename" }

    # Active workspace
    if ($wsName) {
        if (-not (Set-PrefNode $prefs "FE.Application.LastWorkspaceName" $wsName)) { $missing += "FE.Application.LastWorkspaceName" }
    }

    # Classic label preset (names + colours + preset marker)
    for ($i = 0; $i -lt $labelNames.Count; $i++) {
        if (-not (Set-PrefNode $prefs "BE.Prefs.LabelNames.$i"  $labelNames[$i]))  { $missing += "BE.Prefs.LabelNames.$i" }
        if (-not (Set-PrefNode $prefs "BE.Prefs.LabelColors.$i" $labelColors[$i])) { $missing += "BE.Prefs.LabelColors.$i" }
    }
    if (-not (Set-PrefNode $prefs "PPro.LabelColorPresets.RecentPreset" '{"builtIn":true,"name":"Classic"}')) { $missing += "PPro.LabelColorPresets.RecentPreset" }

    # Auto-save: on, every 5 minutes
    if (-not (Set-PrefNode $prefs "BE.Prefs.AutoSave.DoSave"   "true")) { $missing += "BE.Prefs.AutoSave.DoSave" }
    if (-not (Set-PrefNode $prefs "BE.Prefs.AutoSave.Interval" "5"))    { $missing += "BE.Prefs.AutoSave.Interval" }
    Set-PrefNode $prefs "BE.Prefs.AutoSave.Interval" "5"    | Out-Null

    # Timeline toggles: Link Selection + Display Settings (wrench menu)
    foreach ($node in @(
        'TL.PREFLinkedSelectionState',
        'be.Prefs.Timeline.Show.Video.Thumbnails',
        'be.Prefs.Timeline.Show.Video.Names',
        'be.Prefs.Timeline.Show.Audio.Waveforms',
        'be.Prefs.Timeline.Show.Audio.Names',
        'be.Prefs.Timeline.Show.Proxy.Badges',
        'TL.PREFShowFXBadges',
        'TL.PREFShowThroughEditsState',
        'MZ.SQShowDuplicateMarkers'
    )) {
        if (-not (Set-PrefNode $prefs $node "true")) { $missing += $node }
    }

    if ($missing.Count -gt 0) {
        Write-Host "  ⚠️  Premiere prefs: $($missing.Count) node(s) not found and skipped (file untouched for those nodes):"
        $missing | ForEach-Object { Write-Host "        - $_" }
        Write-Host "      This is expected on a fresh install (nodes default to the correct value"
        Write-Host "      and are only written by Premiere after a manual change). Otherwise,"
        Write-Host "      Adobe may have renamed these nodes — check and update the script."
    }
}

# Set-FileAssociation <ext> <progid> — write a UserChoice entry so Explorer
# treats <progid> as the default handler for <ext>. Windows protects this key
# with a tamper hash tied to the user SID + current time; we compute it with
# MD5 and unlock the key's ACL so the write succeeds.
function Set-FileAssociation {
    param($Extension, $ProgId)
    $sid  = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sub  = "software\microsoft\windows\currentversion\explorer\fileexts\$Extension\userchoice"
    $ft   = [long][math]::Floor([datetime]::UtcNow.ToFileTime() / 10000000) * 10000000
    $data = [System.Text.Encoding]::Unicode.GetBytes(
                $sub + $sid.ToLower() + $ProgId.ToLower() + $ft.ToString('x') +
                "user choice set via windows user experience {d18b6dd5-6124-4341-9318-804003bafa0b}")
    $hash = [Convert]::ToBase64String([Security.Cryptography.MD5]::Create().ComputeHash($data))

    $parent = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(
                  "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension", $true)
    try {
        # UserChoice has a restrictive DACL — unlock it so we can delete the key
        $uc = $parent.OpenSubKey("UserChoice",
                  [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                  [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        if ($uc) {
            $acl = $uc.GetAccessControl()
            $acl.SetAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
            $uc.SetAccessControl($acl)
            $uc.Close()
        }
        $parent.DeleteSubKey("UserChoice", $false)
    } catch {}
    $uc = $parent.CreateSubKey("UserChoice")
    $uc.SetValue("ProgId", $ProgId)
    $uc.SetValue("Hash",   $hash)
    $uc.Close()
    $parent.Close()
}

# Sourced as a library (tests set $env:LOAD_LIB): stop here, run nothing below.
if ($env:LOAD_LIB) { return }

# -----------------------------------------------------------------------------
# Flags
# -----------------------------------------------------------------------------

$FULL    = $args -contains "--full"
$FAST    = $args -contains "--fast"
$DRY_RUN = $args -contains "--dry-run"

# No flag given — prompt for the setup type (Fast/Full). Bail if there's no
# interactive console (e.g. CI) so we don't hang or guess into a heavy install.
if (-not ($FULL -or $FAST -or $DRY_RUN)) {
    do {
        try {
            $reply = Read-Host "  Setup type - [1] Fast (config only)  [2] Full (everything)"
        } catch {
            Write-Error "No setup flag given and no interactive console. Pass --fast or --full."
            exit 1
        }
        if     ($reply -in '1','fast','Fast') { $FAST = $true }
        elseif ($reply -in '2','full','Full') { $FULL = $true }
        else   { Write-Host "  Please enter 1 or 2." }
    } while (-not ($FAST -or $FULL))
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

$PREMIERE_OK      = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
# Premiere rewrites its prefs on exit — activating a set while it's running would get clobbered.
$PREMIERE_RUNNING = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
$WINGET_OK        = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$AHK_OK      = Is-Done "ahk"

$KB_Speed = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
$KB_Delay = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
$KB_OK    = ($KB_Speed -eq "31") -and ($KB_Delay -eq "0")

$VLC_EXE        = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"
$VLC_IS_DEFAULT = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice" -ErrorAction SilentlyContinue).ProgId -eq 'VLC.mp4'

function winget_installed($id) {
    if (-not $WINGET_OK) { return $false }
    $result = winget list --id $id --accept-source-agreements 2>$null
    return $LASTEXITCODE -eq 0 -and ($result -match [regex]::Escape($id))
}

function uv_installed($pkg) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { return $false }
    return [bool]((uv tool list 2>$null) -match "^$pkg")
}

function Would-Run  { param($msg); Write-Host "  [run]   $msg" }
function Would-Skip { param($msg); Write-Host "  [skip]  $msg" }
function Already-Done { param($msg); Write-Host "  [done]  $msg" }

Write-Host ""

# Premiere Pro
if ($PREMIERE_OK) {
    Would-Run  "Premiere Pro shortcuts & workspace"
    if ($PREMIERE_RUNNING) { Would-Skip "Premiere Pro preferences — Premiere Pro is open" }
    else                   { Would-Run  "Premiere Pro preferences" }
    if ($FAST) { Would-Skip "Premiere Pro plugins (--fast)" }
    else       { Would-Run  "Premiere Pro plugins — Animation Composer, Flicker Free" }
} else {
    Would-Skip "Premiere Pro shortcuts & workspace — not installed"
    Would-Skip "Premiere Pro preferences — not installed"
    Would-Skip "Premiere Pro plugins — not installed"
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
    "Audacity.Audacity",
    "Adobe.Acrobat.Reader.64-bit"
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

# VLC as default video player
if ($VLC_IS_DEFAULT)                           { Already-Done "VLC as default video player" }
elseif ($FAST -and -not (Test-Path $VLC_EXE)) { Would-Skip   "VLC as default video player — VLC not installed" }
else                                           { Would-Run    "VLC as default video player" }

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
    $KYS_FILE = "Luis_Mengo_25.1_WINDOWS.kys"
    $WS_FILE  = "UserWorkspace_LGG.xml"

    foreach ($profileDir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro\*\Profile-*" -Directory -ErrorAction SilentlyContinue) {
        $prefs   = Join-Path $profileDir.FullName "Adobe Premiere Pro Prefs"
        $winDir  = Join-Path $profileDir.FullName "Win"
        $layouts = Join-Path $profileDir.FullName "Layouts"

        New-Item -ItemType Directory -Force -Path $winDir  | Out-Null
        New-Item -ItemType Directory -Force -Path $layouts | Out-Null

        # Drop the shortcuts into the Profile's Win folder (where Premiere reads custom sets)
        curl.exe -s --output-dir $winDir  -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$KYS_FILE"
        # Drop the workspace into Layouts. Premiere auto-registers it on launch.
        curl.exe -s --output-dir $layouts -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$WS_FILE"
        $wsName = Get-WorkspaceName (Join-Path $layouts $WS_FILE)

        if ($PREMIERE_RUNNING) {
            Write-Host "  ⚠️  Premiere Pro is running — files dropped but not activated"
        } elseif (Test-Path $prefs) {
            Apply-PremierePrefs $prefs $KYS_FILE $wsName
        }
    }
}

# -----------------------------------------------------------------------------
# Keyboard preferences
# -----------------------------------------------------------------------------

if (-not $KB_OK) {
    # Persist across reboots
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value 31
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 0

    # Apply to the active session immediately (no logoff needed)
    if (-not ([System.Management.Automation.PSTypeName]'KeyboardConfig').Type) {
        Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class KeyboardConfig {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, uint pvParam, uint fWinIni);
}
"@
    }
    [KeyboardConfig]::SystemParametersInfo(0x0017, 0, 0, 0)  | Out-Null  # SPI_SETKEYBOARDDELAY
    [KeyboardConfig]::SystemParametersInfo(0x000B, 31, 0, 0) | Out-Null  # SPI_SETKEYBOARDSPEED
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

# Tell already-running apps to re-read the environment so the new PATH is picked
# up without a logoff (this session is already refreshed above).
if (-not $FAST) {
    if (-not ([System.Management.Automation.PSTypeName]'Win32Env').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Env {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    [IntPtr]$res = [IntPtr]::Zero
    [Win32Env]::SendMessageTimeout($HWND_BROADCAST, 0x001A, [IntPtr]::Zero, "Environment", 2, 5000, [ref]$res) | Out-Null  # WM_SETTINGCHANGE
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
        $ahkPath = "$WorkDir\MacKeyboard_LM.ahk"
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
    $pmPath = "$WorkDir\MisterHorseProductManager.msi"
    curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
    Start-Process msiexec.exe -ArgumentList "/i `"$pmPath`" /qn" -Verb RunAs -Wait

    # Flicker Free — Digital Anarchy's deflicker plugin. The download is a zip
    # wrapping the installer .exe; we extract it and run the installer.
    $ffZip = "$WorkDir\flickerfree_229_AE.zip"
    $ffDir = "$WorkDir\flickerfree_229_AE"
    curl.exe -fsSL -o $ffZip "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.zip"
    Expand-Archive -Path $ffZip -DestinationPath $ffDir -Force
    $ffExe = Get-ChildItem $ffDir -Filter *.exe | Select-Object -First 1
    if ($ffExe) { Start-Process $ffExe.FullName -Verb RunAs -Wait }
}

# -----------------------------------------------------------------------------
# LUTs
# -----------------------------------------------------------------------------
# Download every LUT in src/data/LUTs into $WorkDir\LUTs (skipped --fast).
# The file list comes from the GitHub contents API, so new LUTs are picked up
# automatically without editing this script.

if (-not $FAST) {
    $lutDir = "$WorkDir\LUTs"
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
