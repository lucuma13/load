<#
.SYNOPSIS
Windows workstation setup script

.NOTES
Copyright (c) 2026 Luis Gomez Gutierrez

.EXAMPLE
# With interactive menu (optional flags: --fast/--full/--dry-run):
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile "$env:TEMP\load-win.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\load-win.ps1"
#>


$ErrorActionPreference = "Stop"

$WorkDir = "$HOME\Downloads\load-win"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# AHK macros live in the Startup folder so they relaunch at every login; their
# presence there doubles as the "already applied" marker (no separate flag file).
$AhkScript = Join-Path ([Environment]::GetFolderPath("Startup")) "MacKeyboard_LGG.ahk"

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
    param($prefs, $kysFile, $wsName, $version)
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
        'TL.PREFShowThroughEditsState',
        'MZ.SQShowDuplicateMarkers'
        # The preferences below are commented out for now because they are not written to the preference file until the default behaviour has changed:
        # 'be.Prefs.Timeline.Show.Video.Thumbnails',
        # 'be.Prefs.Timeline.Show.Video.Names',
        # 'be.Prefs.Timeline.Show.Audio.Waveforms',
        # 'be.Prefs.Timeline.Show.Audio.Names',
        # 'be.Prefs.Timeline.Show.Proxy.Badges',
        # 'TL.PREFShowFXBadges',
    )) {
        if (-not (Set-PrefNode $prefs $node "true")) { $missing += $node }
    }

    if ($missing.Count -gt 0) {
        Write-Host "  [warn] Premiere prefs on version ${version}: $($missing.Count) node(s) not found and skipped (file untouched for those nodes):"
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

# Friendly display names for the winget ids (used by the checklist). uv tools are
# already human-readable, so they pass through unchanged.
$PKG_ALIAS = @{
    "astral-sh.uv"                = "uv"
    "MediaArea.MediaInfo"         = "MediaInfo CLI"
    "MediaArea.MediaInfo.GUI"     = "MediaInfo GUI"
    "OliverBetz.ExifTool"         = "ExifTool"
    "VideoLAN.VLC"                = "VLC"
    "ZhornSoftware.Caffeine"      = "Caffeine"
    "Gyan.FFmpeg"                 = "FFmpeg"
    "AutoHotkey.AutoHotkey"       = "AutoHotKey"
    "Google.Chrome"               = "Google Chrome"
    "Adobe.Acrobat.Reader.64-bit" = "Adobe Acrobat Reader"
    "Audacity.Audacity"           = "Audacity"
}
function pkg_alias($id) { if ($PKG_ALIAS.ContainsKey($id)) { $PKG_ALIAS[$id] } else { $id } }

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

# Premiere shortcut set + workspace we distribute (used by run_fast and the
# "is it applied?" checklist detector).
$KYS_FILE = "LGG_25.1_WINDOWS.kys"
$WS_FILE  = "UserWorkspace_LGG.xml"

# Keyboard repeat (fastest speed, no delay) - read here because run_fast decides
# whether to apply it; checklist re-reads the rest of the state on its own.
$KB_Speed = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
$KB_Delay = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
$KB_OK    = ($KB_Speed -eq "31") -and ($KB_Delay -eq "0")

# Default-app targets: VLC for video, Adobe Acrobat (64-bit) for PDF. The Acrobat
# ProgId is the one the 64-bit Reader registers for .pdf.
$VLC_EXE     = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"
$ACRO_EXE    = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
$ACRO_PROGID = "Acrobat.Document.DC"

function winget_installed($id) {
    if (-not $WINGET_OK) { return $false }
    $result = winget list --id $id --accept-source-agreements 2>$null
    return $LASTEXITCODE -eq 0 -and ($result -match [regex]::Escape($id))
}

# winget_apply <id> - install the package, or just check for an upgrade when it's
# already present. The upgrade path's output (the repetitive "No available upgrade
# found" chatter) is routed to null; a fresh install still shows its progress.
function winget_apply($id) {
    if (winget_installed $id) {
        Write-Host "  [done]  $id - checking for updates"
        # Redirecting a native command's stderr under $ErrorActionPreference='Stop'
        # wraps each line in a NativeCommandError that aborts the script, so soften
        # the preference while we discard winget's upgrade chatter.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements *> $null
        $ErrorActionPreference = $eap
    } else {
        winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    }
}

function uv_installed($pkg) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { return $false }
    return [bool]((uv tool list 2>$null) -match "^$pkg")
}

# app_installed <pattern> - true if any Windows uninstall entry's DisplayName
# matches <pattern> (per-machine 64- and 32-bit, plus per-user).
function app_installed($pattern) {
    foreach ($key in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )) {
        if (Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match $pattern }) { return $true }
    }
    return $false
}

# Premiere plugins already on the machine? Each registers a Windows uninstall entry.
function flickerfree_installed { app_installed 'Flicker Free' }
function misterhorse_installed { app_installed 'Mister Horse' }

# premiere_applied - true once our shortcut set is active in any Premiere profile
# (the prefs' Shortcuts.Filename points at our .kys). Reads the prefs with the same
# BOM-aware decoding as Set-PrefNode.
function premiere_applied {
    if (-not $PREMIERE_OK) { return $false }
    foreach ($profileDir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro\*\Profile-*" -Directory -ErrorAction SilentlyContinue) {
        $prefs = Join-Path $profileDir.FullName "Adobe Premiere Pro Prefs"
        if (-not (Test-Path $prefs)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($prefs)
        if     ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
        else                                                                          { $enc = [System.Text.Encoding]::UTF8 }
        if ($enc.GetString($bytes) -match "<FE\.Prefs\.Shortcuts\.Filename>$([regex]::Escape($KYS_FILE))</FE\.Prefs\.Shortcuts\.Filename>") { return $true }
    }
    return $false
}

# luts_present - true once at least one LUT has been downloaded into the work dir.
function luts_present { [bool](Get-ChildItem "$WorkDir\LUTs" -File -ErrorAction SilentlyContinue | Select-Object -First 1) }

function Done     { param($msg); Write-Host ("  " + "[done]".PadRight(12)      + $msg) }
function Skipped  { param($msg); Write-Host ("  " + "[skipped]".PadRight(12)   + $msg) }
function WouldRun { param($msg); Write-Host ("  " + "[would run]".PadRight(12) + $msg) }

# checklist - print the live state of every action: [done], [skipped] or [would
# run]. The same call works at the start of a run (a preview - nothing done yet) or
# at the end (a summary - state reflects what ran), because every line is derived
# from the real current state plus the run mode. No flags, no "post" switch.
function checklist {
    $kbSpeed = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
    $kbDelay = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
    $kbOk    = ($kbSpeed -eq "31") -and ($kbDelay -eq "0")
    $premiereRunning = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
    $vlcInstalled  = Test-Path $VLC_EXE
    $acroInstalled = Test-Path $ACRO_EXE
    $vlcDefault    = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice" -ErrorAction SilentlyContinue).ProgId -eq 'VLC.mp4'
    $acroDefault   = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice" -ErrorAction SilentlyContinue).ProgId -eq $ACRO_PROGID
    $ahkActive    = Test-Path $AhkScript
    $ahkInstalled = [bool](Find-AhkExe)

    Write-Host ""

    # Premiere Pro - shortcuts, workspace and preferences always go together, so they
    # show as one line. (When Premiere is open the files are dropped but not activated.)
    if (-not $PREMIERE_OK)    { Skipped  "Premiere Pro (shortcuts, workspace and preferences) - not installed" }
    elseif ($premiereRunning) { Skipped  "Premiere Pro (shortcuts, workspace and preferences) - Premiere Pro is open" }
    elseif (premiere_applied) { Done     "Premiere Pro (shortcuts, workspace and preferences)" }
    else                      { WouldRun "Premiere Pro (shortcuts, workspace and preferences)" }

    # Keyboard preferences
    if ($kbOk) { Done "Keyboard preferences" } else { WouldRun "Keyboard preferences" }

    # Install or update apps - winget packages, then the Premiere plugins, then the uv
    # tools (each entry paired with its "already installed?" check, in that order).
    $apps = @()
    foreach ($pkg in $CORE_PKGS)              { $apps += @{ name = (pkg_alias $pkg); ok = (winget_installed $pkg) } }
    if ($FULL) { foreach ($pkg in $FULL_PKGS) { $apps += @{ name = (pkg_alias $pkg); ok = (winget_installed $pkg) } } }
    if ($PREMIERE_OK) {
        $apps += @{ name = "Mister Horse Product Manager"; ok = (misterhorse_installed) }
        $apps += @{ name = "Flicker Free";                 ok = (flickerfree_installed) }
    }
    foreach ($pkg in $CORE_UV)                { $apps += @{ name = $pkg; ok = (uv_installed $pkg) } }

    if ($FAST) {
        Skipped ("Install or update apps (--fast) - " + (($apps | ForEach-Object { $_.name }) -join ", "))
    } else {
        $done = @($apps | Where-Object { $_.ok }      | ForEach-Object { $_.name })
        $todo = @($apps | Where-Object { -not $_.ok }  | ForEach-Object { $_.name })
        if ($done.Count -gt 0) { Done     ("Install or update apps: " + ($done -join ", ")) }
        if ($todo.Count -gt 0) { WouldRun ("Install or update apps: " + ($todo -join ", ")) }
    }

    # Default apps - VLC for video, Adobe Acrobat Reader for PDF. "Done" once every
    # installed one of the two owns its types; nothing to do if neither is installed.
    $anyInstalled = $vlcInstalled -or $acroInstalled
    $allDefault   = ((-not $vlcInstalled) -or $vlcDefault) -and ((-not $acroInstalled) -or $acroDefault)
    if (-not $anyInstalled -and $FAST)      { Skipped  "Change default apps (--fast) - VLC, Adobe Acrobat Reader not installed" }
    elseif ($anyInstalled -and $allDefault) { Done     "Change default apps: VLC, Adobe Acrobat Reader" }
    else                                    { WouldRun "Change default apps: VLC, Adobe Acrobat Reader" }

    # Activate AHK macros - applied whenever AutoHotkey is present. In --fast we only
    # have a pre-installed AutoHotkey to work with (installing it is a Full-pass step).
    if ($ahkActive)        { Done     "Activate AHK macros" }
    elseif ($ahkInstalled) { WouldRun "Activate AHK macros" }
    elseif ($FAST)         { Skipped  "Activate AHK macros (--fast) - AutoHotkey not installed" }
    else                   { WouldRun "Activate AHK macros" }

    # Download LUTs
    if ($FAST)            { Skipped  "Download LUTs (--fast)" }
    elseif (luts_present) { Done     "Download LUTs" }
    else                  { WouldRun "Download LUTs" }

    Write-Host ""
}

# -----------------------------------------------------------------------------
# Phase functions
# -----------------------------------------------------------------------------
# run_fast - lightweight preference changes only (no downloads/installs).
# run_slow - everything that downloads or installs. Setting default apps is config
# that needs the app present, so Set-DefaultApps runs in both phases (idempotent: it
# re-checks the current default and no-ops once the app already owns its types). The
# bare command runs run_fast inline then hands off to a Full pass that runs
# run_slow; --fast runs run_fast only and --full runs both.

function Set-DefaultApps {
    # Point Explorer's per-extension UserChoice at each app's registered ProgIds.
    # Each app is gated on being installed and re-queries the current default, so
    # it's a no-op once owned and safe to call from both phases.

    # VLC for the common video container types (ProgIds VLC.<ext> from the installer).
    if (Test-Path $VLC_EXE) {
        $cur = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice" -ErrorAction SilentlyContinue).ProgId
        if ($cur -ne 'VLC.mp4') {
            foreach ($ext in @('mp4','m4v','mov','mkv','avi','wmv','flv','webm','mpg','mpeg','m2ts','mts','ts','vob','mxf')) {
                try { Set-FileAssociation ".$ext" "VLC.$ext" } catch {}
            }
        }
    }

    # Adobe Acrobat Reader for PDF.
    if (Test-Path $ACRO_EXE) {
        $cur = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice" -ErrorAction SilentlyContinue).ProgId
        if ($cur -ne $ACRO_PROGID) {
            try { Set-FileAssociation ".pdf" $ACRO_PROGID } catch {}
        }
    }
}

function Install-AhkMacros {
    # Install the AHK macro script into the user's Startup folder (so it loads on
    # every login - not left lying in the work dir) and launch it now so the
    # shortcuts work immediately. The file's presence there is the "done" marker.
    if (Test-Path $AhkScript) { return }
    $ahkExe = Find-AhkExe
    if (-not $ahkExe) {
        Write-Host "  [warn] AutoHotkey not found - skipping AHK shortcuts"
        return
    }
    curl.exe -s -o $AhkScript "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/MacKeyboard_LGG.ahk"
    # Quote the path (a profile dir may contain spaces) and launch non-elevated, the
    # way it'll start at every login - an elevated RunAs launch also pops a UAC
    # prompt mid-run that, if dismissed, leaves the macros inactive.
    Start-Process $ahkExe -ArgumentList "`"$AhkScript`""
}

function run_fast {
    # Premiere Pro shortcuts & workspace
    if ($PREMIERE_OK) {
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
                # $profileDir.Parent.Name is the version folder (e.g. "25.0"), so each
                # profile's warning is tagged with the Premiere version it came from.
                Apply-PremierePrefs $prefs $KYS_FILE $wsName $profileDir.Parent.Name
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

    # Default apps - config that needs the app present (see Set-DefaultApps)
    Set-DefaultApps

    # AHK macros - apply now if AutoHotkey is already installed (covers --fast on a
    # machine that has it). On a Full run AutoHotkey is installed in run_slow, which
    # applies them there instead - so only act here when it's already present.
    if (Find-AhkExe) { Install-AhkMacros }
}

function run_slow {
    # Managed packages
    foreach ($pkg in $CORE_PKGS) { winget_apply $pkg }
    # Refresh PATH so newly installed tools (uv, etc.) are available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($pkg in $CORE_UV) {
        uv tool install $pkg --upgrade
    }
    # Add uv's tool bin dir to PATH permanently and refresh for this session. uv
    # prints "already in PATH" to stderr when the bin dir is already set up;
    # redirecting a native command's stderr under $ErrorActionPreference='Stop'
    # wraps that line in a NativeCommandError and aborts the script, so soften the
    # preference for this one call.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    uv tool update-shell *> $null
    $ErrorActionPreference = $eap
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Full-only managed packages
    if ($FULL) {
        foreach ($pkg in $FULL_PKGS) { winget_apply $pkg }
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

    # Default apps - now that VLC/Acrobat are installed (covers a fresh machine)
    Set-DefaultApps

    # AHK macros - AutoHotkey was installed above on a Full run (or already present)
    Install-AhkMacros

    # Premiere plugins - Mister Horse Product Manager is the app that installs &
    # updates the Mister Horse plugins (Animation Composer etc.) into Premiere/After
    # Effects; the plugins themselves are then added from within it on first launch.
    # We install the Product Manager here; Flicker Free is a standalone installer.
    if ($PREMIERE_OK) {
        # Skip the download + (elevated) MSI when the Product Manager is already installed.
        if (misterhorse_installed) {
            Write-Host "  [done]  Mister Horse Product Manager already installed"
        } else {
            $pmPath = "$WorkDir\MisterHorseProductManager.msi"
            curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
            $pm = Start-Process msiexec.exe -ArgumentList "/i `"$pmPath`" /qn" -Verb RunAs -Wait -PassThru
            # Clean up the installer once it finished successfully (exit 0).
            if ($pm.ExitCode -eq 0) { Remove-Item $pmPath -Force -ErrorAction SilentlyContinue }
        }

        # Flicker Free - Digital Anarchy's deflicker plugin. The download is a zip
        # wrapping the installer .exe; we extract it and run the installer. Skip the
        # whole download+install when it's already present.
        if (flickerfree_installed) {
            Write-Host "  [done]  Flicker Free already installed"
        } else {
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

# --dry-run just prints the checklist (a preview, since nothing has run), then stops.
if ($DRY_RUN) { checklist; exit 0 }

if ($RUN_FAST) { run_fast }

if ($AUTO) {
    # Fast pass finished. Only now save the script to a temp file - so nothing is
    # left on disk if the user stops here - and run the Full pass from it. The Full
    # pass prints the post-install summary at the end (its live state covers what
    # this Fast pass just did too), so we don't print one here.
    Read-Host "  Fast loading is complete. Press enter to continue on FULL mode" | Out-Null
    $self = "$env:TEMP\load-win.ps1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing |
        Set-Content $self -Encoding UTF8
    $env:LOAD_FROM_FAST = "1"
    powershell -ExecutionPolicy Bypass -File $self --full
    exit $LASTEXITCODE
}

if ($RUN_SLOW) { run_slow }

# Final checklist - same call as the preview, but now it reports the end state.
checklist
Write-Host "  You're ready to roll!"
Write-Host ""
