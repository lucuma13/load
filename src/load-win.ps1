<#
.SYNOPSIS
Windows workstation setup script

.NOTES
Copyright (c) 2026 Luis Gomez Gutierrez

.EXAMPLE
# With interactive menu:

.EXAMPLE
# With bypass execution policy and flags (append --fast/--full/--dry-run):
#>


$ErrorActionPreference = "Stop"

$WorkDir = "$HOME\Downloads\load-win"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Mark-Done { param($step); New-Item -ItemType File -Force -Path "$WorkDir\$step" | Out-Null }
function Is-Done   { param($step); Test-Path "$WorkDir\$step" }

# Find-AhkExe - locate an installed AutoHotkey interpreter, or return $null. Used
# both to preview (is AutoHotkey present?) and to run the macros. The winget
# install layout varies by version, so try PATH, the common install paths, then a
# recursive search preferring the 64-bit interpreter over the launcher.
function Find-AhkExe {
    $exe = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $exe) {
        $exe = @(
            "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
            "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
            "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe",
            "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
            "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
            "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $exe) {
        $exe = Get-ChildItem "$env:ProgramFiles\AutoHotkey" -Recurse -Filter "AutoHotkey*.exe" -ErrorAction SilentlyContinue |
               Sort-Object { $_.Name -notmatch '64' } |
               Select-Object -First 1 -ExpandProperty FullName
    }
    return $exe
}

# Get-WorkspaceName <ws_file> - return the workspace display name from the XML file,
# stored under the UserName key.
function Get-WorkspaceName {
    param($wsFile)
    $content = [System.IO.File]::ReadAllText($wsFile)
    if ($content -match '<key>UserName</key>\s*<ustring>(.*?)</ustring>') { return $Matches[1] }
    return ""
}

# Set-PrefNode <prefs> <node> <value> - replace an XML leaf node's text in place.
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

# Apply-PremierePrefs <prefs> <kys_file> <ws_name> - point Premiere's prefs at
# the keyboard set + workspace, apply the Classic label preset, enable auto-save
# every 5 minutes, and turn on the timeline's Link Selection + Display Settings.
#
# A missing-node warning can mean one of two things:
#   (a) Fresh Premiere install - Premiere only writes certain nodes to disk after
#       a user first manually changes them (confirmed for the 8 timeline display
#       toggles, which default to true). Warning is harmless; the setting is
#       already at the correct value.
#   (b) Adobe renamed the node in this Premiere version - the setting was NOT
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
        Write-Host "  [warn] Premiere prefs: $($missing.Count) node(s) not found and skipped (file untouched for those nodes):"
        $missing | ForEach-Object { Write-Host "        - $_" }
        Write-Host "      This is expected on a fresh install (nodes default to the correct value"
        Write-Host "      and are only written by Premiere after a manual change). Otherwise,"
        Write-Host "      Adobe may have renamed these nodes - check and update the script."
    }
}

# Set-FileAssociation <ext> <progid> - write a UserChoice entry so Explorer
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
        # UserChoice has a restrictive DACL - unlock it so we can delete the key
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

# winget package lists. Kept above the guard so the test suite can source them and
# confirm every id still resolves on winget (catches renames/delisting/typos).
$CORE_PKGS = @(
    "astral-sh.uv",
    "MediaArea.MediaInfo",
    "MediaArea.MediaInfo.GUI",
    "OliverBetz.ExifTool",
    "VideoLAN.VLC",
    "ZhornSoftware.Caffeine",
    "Gyan.FFmpeg"
)
$FULL_PKGS = @(  # Add if needed: "AxiomaticSystems.Bento4", "wez.atomicparsley"
    "AutoHotkey.AutoHotkey",
    "Google.Chrome",
    "Adobe.Acrobat.Reader.64-bit",
    "Audacity.Audacity"
)
$CORE_UV = @(
    "triplecheck",
    "mhl-suite"
)

# Sourced as a library (tests set $env:LOAD_LIB): stop here, run nothing below.
if ($env:LOAD_LIB) { return }

# -----------------------------------------------------------------------------
# Flags
# -----------------------------------------------------------------------------

$FULL    = $args -contains "--full"
$FAST    = $args -contains "--fast"
$DRY_RUN = $args -contains "--dry-run"

# No flag given - run the Fast pass inline now (quick config, nothing saved to
# disk), then pause and hand off to the Full pass (see the Dispatch section, which
# only then downloads the script to a temp file). Bail if there's no interactive
# console (e.g. CI) so we don't run a heavy install on an unattended box.
$AUTO = $false
if (-not ($FULL -or $FAST -or $DRY_RUN)) {
    if ([System.Console]::IsInputRedirected) {
        Write-Error "No setup flag given and no interactive console. Pass --fast or --full."
        exit 1
    }
    $AUTO = $true
    $FAST = $true
}

# Phase gates. run_fast applies lightweight config; run_slow does the
# downloads/installs. The bare command runs Fast inline then hands off to a Full
# pass (marked with LOAD_FROM_FAST) that runs Slow only - so Fast is skipped there
# to avoid repeating the same actions.
$RUN_FAST = -not $env:LOAD_FROM_FAST
$RUN_SLOW = -not $FAST

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

$PREMIERE_OK      = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
# Premiere rewrites its prefs on exit - activating a set while it's running would get clobbered.
$PREMIERE_RUNNING = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
$WINGET_OK        = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$AHK_OK        = Is-Done "ahk"
$AHK_INSTALLED = [bool](Find-AhkExe)   # AutoHotkey already on the machine?

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
    if (-not $RUN_FAST) {
        Already-Done "Premiere Pro shortcuts & workspace"
        Already-Done "Premiere Pro preferences"
    } else {
        Would-Run  "Premiere Pro shortcuts & workspace"
        if ($PREMIERE_RUNNING) { Would-Skip "Premiere Pro preferences - Premiere Pro is open" }
        else                   { Would-Run  "Premiere Pro preferences" }
    }
    if ($FAST) { Would-Skip "Premiere Pro plugins (--fast)" }
    else       { Would-Run  "Premiere Pro plugins - Animation Composer, Flicker Free" }
} else {
    Would-Skip "Premiere Pro shortcuts & workspace - not installed"
    Would-Skip "Premiere Pro preferences - not installed"
    Would-Skip "Premiere Pro plugins - not installed"
}

# Keyboard preferences (lightweight config - skipped in the Full hand-off)
if (-not $RUN_FAST) { Already-Done "Keyboard preferences" }
elseif ($KB_OK)       { Already-Done "Keyboard preferences" }
else                  { Would-Run    "Keyboard preferences" }

# winget packages (lists defined above the library guard)
if ($FAST) {
    $all = $CORE_PKGS + $CORE_UV
    if ($FULL) { $all += $FULL_PKGS }
    Would-Skip ("managed packages (--fast) - " + ($all -join ", "))
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
elseif ($FAST -and -not (Test-Path $VLC_EXE)) { Would-Skip   "VLC as default video player - VLC not installed" }
else                                           { Would-Run    "VLC as default video player" }

# AHK shortcuts - applied whenever AutoHotkey is present. In --fast we only have a
# pre-installed AutoHotkey to work with (installing it is a Full-pass step).
if ($AHK_OK)            { Already-Done "AHK shortcuts" }
elseif ($AHK_INSTALLED) { Would-Run    "AHK shortcuts" }
elseif ($FAST)          { Would-Skip   "AHK shortcuts (--fast) - AutoHotkey not installed" }
else                    { Would-Run    "AHK shortcuts" }

# LUTs
if ($FAST) { Would-Skip "LUTs (--fast)" }
else       { Would-Run  "LUTs" }

Write-Host ""
if ($DRY_RUN) { exit 0 }

# -----------------------------------------------------------------------------
# Phase functions
# -----------------------------------------------------------------------------
# run_fast - lightweight preference changes only (no downloads/installs).
# run_slow - everything that downloads or installs. VLC-as-default is config that
# needs VLC present, so Set-VlcDefault runs in both phases (idempotent: it
# re-checks the current default and no-ops once VLC already owns the types). The
# bare command runs run_fast inline then hands off to a Full pass that runs
# run_slow; --fast runs run_fast only and --full runs both.

function Set-VlcDefault {
    # Point Explorer's per-extension UserChoice at VLC's registered ProgIds
    # (VLC.<ext>, created by the VLC installer). No-op if VLC isn't installed or
    # already owns .mp4; re-queries so it's safe to call from both phases.
    if (-not (Test-Path $VLC_EXE)) { return }
    $cur = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice" -ErrorAction SilentlyContinue).ProgId
    if ($cur -eq 'VLC.mp4') { return }
    foreach ($ext in @('mp4','m4v','mov','mkv','avi','wmv','flv','webm','mpg','mpeg','m2ts','mts','ts','vob','mxf')) {
        try { Set-FileAssociation ".$ext" "VLC.$ext" } catch {}
    }
}

function Install-AhkMacros {
    # Download the AHK macro script and launch it (elevated) under the installed
    # AutoHotkey. No-op once done, or when AutoHotkey isn't present.
    if (Is-Done "ahk") { return }
    $ahkExe = Find-AhkExe
    if (-not $ahkExe) {
        Write-Host "  [warn] AutoHotkey not found - skipping AHK shortcuts"
        return
    }
    $ahkPath = "$WorkDir\MacKeyboard_LGG.ahk"
    curl.exe -s -o $ahkPath "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/MacKeyboard_LGG.ahk"
    Start-Process $ahkExe -ArgumentList $ahkPath -Verb RunAs
    Mark-Done "ahk"
}

function run_fast {
    # Premiere Pro shortcuts & workspace
    if ($PREMIERE_OK) {
        $KYS_FILE = "LGG_25.1_WINDOWS.kys"
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
                Write-Host "  [warn] Premiere Pro is running - files dropped but not activated"
            } elseif (Test-Path $prefs) {
                Apply-PremierePrefs $prefs $KYS_FILE $wsName
            }
        }
    }

    # Keyboard preferences
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

    # VLC as default video player - config that needs VLC present (see Set-VlcDefault)
    Set-VlcDefault

    # AHK macros - apply now if AutoHotkey is already installed (covers --fast on a
    # machine that has it). On a Full run AutoHotkey is installed in run_slow, which
    # applies them there instead - so only act here when it's already present.
    if (Find-AhkExe) { Install-AhkMacros }
}

function run_slow {
    # Managed packages
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

    # Full-only managed packages
    if ($FULL) {
        foreach ($pkg in $FULL_PKGS) {
            winget install $pkg --accept-package-agreements --accept-source-agreements
        }
        # Refresh PATH so newly installed tools (AutoHotkey, etc.) are available in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Tell already-running apps to re-read the environment so the new PATH is picked
    # up without a logoff (this session is already refreshed above).
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

    # VLC as default video player - now that VLC is installed (covers a fresh machine)
    Set-VlcDefault

    # AHK macros - AutoHotkey was installed above on a Full run (or already present)
    Install-AhkMacros

    # Premiere plugins - Mister Horse's Product Manager installs & updates Animation
    # Composer (and the other Mister Horse plugins) into Premiere/After Effects. We
    # download the Product Manager installer and run it; Animation Composer itself is
    # then installed from within the app on first launch.
    if ($PREMIERE_OK) {
        $pmPath = "$WorkDir\MisterHorseProductManager.msi"
        curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
        $pm = Start-Process msiexec.exe -ArgumentList "/i `"$pmPath`" /qn" -Verb RunAs -Wait -PassThru
        # Clean up the installer once it finished successfully (exit 0).
        if ($pm.ExitCode -eq 0) { Remove-Item $pmPath -Force -ErrorAction SilentlyContinue }

        # Flicker Free - Digital Anarchy's deflicker plugin. The download is a zip
        # wrapping the installer .exe; we extract it and run the installer.
        $ffZip = "$WorkDir\flickerfree_229_AE.zip"
        $ffDir = "$WorkDir\flickerfree_229_AE"
        curl.exe -fsSL -o $ffZip "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.zip"
        Expand-Archive -Path $ffZip -DestinationPath $ffDir -Force
        $ffExe = Get-ChildItem $ffDir -Filter *.exe | Select-Object -First 1
        if ($ffExe) {
            $ff = Start-Process $ffExe.FullName -Verb RunAs -Wait -PassThru
            # Clean up the zip and extracted installer once it finished successfully.
            if ($ff.ExitCode -eq 0) {
                Remove-Item $ffZip -Force -ErrorAction SilentlyContinue
                Remove-Item $ffDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # LUTs - download every LUT in src/data/LUTs into $WorkDir\LUTs. The file list
    # comes from the GitHub contents API, so new LUTs are picked up automatically
    # without editing this script.
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
        Write-Host "  [warn] Could not fetch LUTs: $_"
    }
}

# -----------------------------------------------------------------------------
# Dispatch - run_fast inline; the bare command then hands off to a Full pass,
# and run_slow does the downloads/installs.
# -----------------------------------------------------------------------------

if ($RUN_FAST) { run_fast }

if ($AUTO) {
    # Fast pass finished. Only now save the script to a temp file - so nothing is
    # left on disk if the user stops here - and run the Full pass from it.
    Read-Host "  Fast loading is complete. Press enter to continue on FULL mode" | Out-Null
    $self = "$env:TEMP\load-win.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing |
        Set-Content $self -Encoding UTF8
    $env:LOAD_FROM_FAST = "1"
    powershell -ExecutionPolicy Bypass -File $self --full
    exit $LASTEXITCODE
}

if ($RUN_SLOW) { run_slow }

Write-Host ""
Write-Host "  You're ready to roll!"
Write-Host ""
