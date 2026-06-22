<#
.SYNOPSIS
Windows workstation setup script

.NOTES
Copyright (c) 2026 Luis Gomez Gutierrez

.EXAMPLE
# With interactive menu (optional flags: --fast/--full/--dry-run):
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile "$env:TEMP\load-win.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\load-win.ps1"
#>

$ErrorActionPreference = "Continue"

$WorkDir = "$HOME\Downloads\load-win"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# AHK macros live in the work dir - the user double-clicks the script after rebooting to activate it.
$AhkScript = Join-Path $WorkDir "MacKeyboard_LGG.ahk"

# Find-AhkExe - locate an installed AutoHotkey interpreter, or return $null. Used
# both to preview (is AutoHotkey present?) and to run the macros.
function Find-AhkExe {
    $exe = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $exe) {
        $exe = Get-ChildItem `
                   "$env:ProgramFiles\AutoHotkey", `
                   "${env:ProgramFiles(x86)}\AutoHotkey" `
                   -Recurse -Filter "AutoHotkey*.exe" -ErrorAction SilentlyContinue |
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

# Set-PremiereProPrefs <prefs> <kys_file> <ws_name> - point Premiere Pro's keyboard shortcuts preset
# and active workspace at our files, use  Classic label colour preset, enable auto-save every 5 minutes,
# and toggle on the Timeline's Linked Selection button and some Timeline Display Settings.
#
# A missing-node warning can mean one of two things:
#   (a) Fresh Premiere install - Premiere only writes certain nodes to disk after
#       a user first manually changes them. Warning is harmless; the setting is
#       already at the correct value.
#   (b) Adobe renamed the node in this Premiere version - the setting was NOT
#       applied and the script needs updating.
# Either way the file is left untouched for that node.
function Set-PremiereProPrefs {
    param($prefs, $kysFile, $wsName, $version)
    $labelNames  = @('Violet','Iris','Caribbean','Lavender','Cerulean','Forest','Rose','Mango','Purple','Blue','Teal','Magenta','Tan','Green','Brown','Yellow')
    $labelColors = @('14717094','13408882','10016297','14910691','14597935','5814353','10776567','3909357','9896087','16727100','8421376','15151847','9814478','2191389','1262987','6611682')
    $missing = @()

    # Keyboard shortcuts preset
    if (-not (Set-PrefNode $prefs "FE.Prefs.Shortcuts.Filename" $kysFile)) { $missing += "FE.Prefs.Shortcuts.Filename" }

    # Active workspace
    if ($wsName) {
        if (-not (Set-PrefNode $prefs "FE.Application.LastWorkspaceName" $wsName)) { $missing += "FE.Application.LastWorkspaceName" }
    }

    # Classic label colour preset
    for ($i = 0; $i -lt $labelNames.Count; $i++) {
        if (-not (Set-PrefNode $prefs "BE.Prefs.LabelNames.$i"  $labelNames[$i]))  { $missing += "BE.Prefs.LabelNames.$i" }
        if (-not (Set-PrefNode $prefs "BE.Prefs.LabelColors.$i" $labelColors[$i])) { $missing += "BE.Prefs.LabelColors.$i" }
    }
    if (-not (Set-PrefNode $prefs "PPro.LabelColorPresets.RecentPreset" '{"builtIn":true,"name":"Classic"}')) { $missing += "PPro.LabelColorPresets.RecentPreset" }

    # Auto-save every 5 minutes
    if (-not (Set-PrefNode $prefs "BE.Prefs.AutoSave.DoSave"   "true")) { $missing += "BE.Prefs.AutoSave.DoSave" }
    if (-not (Set-PrefNode $prefs "BE.Prefs.AutoSave.Interval" "5"))    { $missing += "BE.Prefs.AutoSave.Interval" }

    # Timeline toggles: Linked Selection + Timeline Display Settings (wrench menu)
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

# Friendly display names for the winget ids (uv tools are already friendly).
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
function Get-PkgAlias($id) { if ($PKG_ALIAS.ContainsKey($id)) { $PKG_ALIAS[$id] } else { $id } }

# Sourced as a library (tests set $env:LOAD_LIB): stop here, run nothing below.
if ($env:LOAD_LIB) { return }

# Remove-SelfTemp - delete our own copy when we were launched from a temp file. The
# documented entrypoint downloads the script to %TEMP%, and the fast->full hand-off
# rewrites the same path; PowerShell loads the whole script into memory before
# running, so deleting the file mid-run is safe. Only ever removes a copy under
# %TEMP% - a checkout or any other location is left untouched.
function Remove-SelfTemp {
    # Guard on $env:TEMP being non-empty: StartsWith("") is true for every path, so a
    # blank TEMP must NOT be allowed to match (and delete) an arbitrary script path.
    $temp = $env:TEMP
    if ($temp -and $PSCommandPath -and $PSCommandPath.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
    }
}

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
        Remove-SelfTemp
        exit 1
    }
    $AUTO = $true
    $FAST = $true
}

# Phase gates. Invoke-FastPass applies lightweight config; Invoke-SlowPass does the
# downloads/installs. The bare command runs Fast inline then hands off to a Full
# pass (marked with LOAD_FROM_FAST) that runs Slow only - so Fast is skipped there
# to avoid repeating the same actions.
$RUN_FAST = -not $env:LOAD_FROM_FAST
$RUN_SLOW = -not $FAST

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

$PREMIERE_OK      = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
# Premiere may rewrites its prefs while running - activating a set while it's running can get clobbered.
$PREMIERE_RUNNING = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
$WINGET_OK        = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

# Premiere shortcut set + workspace we distribute
$KYS_FILE = "LGG_25.1_WINDOWS.kys"
$LAYOUT_FILE  = "UserWorkspace_LGG.xml"

# Keyboard repeat
$KB_Speed = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
$KB_Delay = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
$KB_OK    = ($KB_Speed -eq "31") -and ($KB_Delay -eq "0")

# Default-app targets - the apps we make the OS default for and the file types each
# should own. WingetId ties each to its package so the friendly name comes from
# $PKG_ALIAS (shared with the "install or update" checklist line). ProgId contains
# "{ext}" for installers that register a per-extension ProgId (VLC -> VLC.mp4,
# VLC.mkv, ...); otherwise it's a single ProgId used for every type (the 64-bit
# Acrobat Reader). This one list drives the checklist and Set-DefaultApps.
$DEFAULT_APPS = @(
    @{
        WingetId = "VideoLAN.VLC"
        Exe      = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"
        ProgId   = "VLC.{ext}"
        Exts     = @('mp4','m4v','mov','mkv','avi','wmv','flv','webm','mpg','mpeg','m2ts','mts','ts','vob','mxf')
    }
    @{
        WingetId = "Adobe.Acrobat.Reader.64-bit"
        Exe      = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
        ProgId   = "Acrobat.Document.DC"
        Exts     = @('pdf')
    }
)

function Test-WingetInstalled($id) {
    if (-not $WINGET_OK) { return $false }
    $result = winget list --id $id --accept-source-agreements 2>$null
    return $LASTEXITCODE -eq 0 -and ($result -match [regex]::Escape($id))
}

# Invoke-WingetApply <id> - install the package, or upgrade it in place when already present.
# winget's native output is shown only for installs/upgrades and errors.
function Invoke-WingetApply($id) {
    if (Test-WingetInstalled $id) {
        # Redirecting a native command's stderr under $ErrorActionPreference='Stop'
        # wraps each line in a NativeCommandError that aborts the script, so soften
        # the preference while we capture winget's output.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        $ErrorActionPreference = $eap
        # Swallow the "nothing to do" chatter; surface real upgrade/error output.
        if ($out -notmatch 'No available upgrade|No installed package') { Write-Host $out.TrimEnd() }
    } else {
        winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    }
}

function Test-UvInstalled($pkg) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { return $false }
    return [bool]((uv tool list 2>$null) -match "^$pkg")
}

# Test-AppInstalled <pattern> - true if any Windows uninstall entry's DisplayName
# matches <pattern> (per-machine 64- and 32-bit, plus per-user).
function Test-AppInstalled($pattern) {
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

# Non-winget packages already on the machine? Each registers a Windows uninstall entry.
function Test-FlickerFreeInstalled { Test-AppInstalled 'Flicker Free' }
function Test-MisterHorseInstalled { Test-AppInstalled 'Mister Horse' }

# Test-PremiereApplied - true once our shortcut set is active in any Premiere profile
# (the prefs' Shortcuts.Filename points at our .kys). Reads the prefs with the same
# BOM-aware decoding as Set-PrefNode.
function Test-PremiereApplied {
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

# Test-LutsPresent - true once at least one LUT has been downloaded into the work dir.
function Test-LutsPresent { [bool](Get-ChildItem "$WorkDir\LUTs" -File -ErrorAction SilentlyContinue | Select-Object -First 1) }

function Done     { param($msg); Write-Host ("  " + "[done]".PadRight(12)      + $msg) }
function Skipped  { param($msg); Write-Host ("  " + "[skipped]".PadRight(12)   + $msg) }
function WouldRun { param($msg); Write-Host ("  " + "[would run]".PadRight(12) + $msg) }

# Show-Checklist - print the live state of every action: [done], [skipped] or [would
# run]. The same call works at the start of a run (a preview - nothing done yet) or
# at the end (a summary - state reflects what ran), because every line is derived
# from the real current state plus the run mode. No flags, no "post" switch.
function Show-Checklist {
    $kbSpeed = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
    $kbDelay = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
    $kbOk    = ($kbSpeed -eq "31") -and ($kbDelay -eq "0")
    # Input-language / keyboard-layout switch hotkeys disabled ("3" = Not Assigned).
    $toggle    = Get-ItemProperty "HKCU:\Keyboard Layout\Toggle" -ErrorAction SilentlyContinue
    $togglesOk = $toggle -and $toggle.Hotkey -eq "3" -and $toggle.'Language Hotkey' -eq "3" -and $toggle.'Layout Hotkey' -eq "3"
    $sysOk     = $kbOk -and $togglesOk
    $premiereRunning = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
    $ahkActive    = Test-Path $AhkScript
    $ahkInstalled = [bool](Find-AhkExe)

    Write-Host ""

    # Premiere Pro - shortcuts, workspace, preferences and LUTs are the editing setup, so they
    # all require Premiere installed. (When Premiere is open the files are dropped but not activated.)
    if (-not $PREMIERE_OK)    { Skipped  "Premiere Pro (shortcuts, workspace, preferences, LUTs) - Premiere Pro not installed" }
    elseif ($premiereRunning) { Skipped  "Premiere Pro (shortcuts, workspace, preferences, LUTs) - Premiere Pro is open" }
    elseif ((Test-PremiereApplied) -and (Test-LutsPresent)) { Done "Premiere Pro (shortcuts, workspace, preferences, LUTs)" }
    else                      { WouldRun "Premiere Pro (shortcuts, workspace, preferences, LUTs)" }

    # Activate AHK macros - applied whenever AutoHotkey is present. In --fast we might only
    # have a pre-installed AutoHotkey to work with (installing it is a Full-pass step).
    if ($ahkActive)        { Done     "Activate AHK macros" }
    elseif ($ahkInstalled) { WouldRun "Activate AHK macros" }
    elseif ($FAST)         { Skipped  "Activate AHK macros - AutoHotkey not installed" }
    else                   { WouldRun "Activate AHK macros" }

    # System preferences - keyboard repeat speed/delay and the disabled layout-switch hotkeys
    if ($sysOk) { Done "System preferences" } else { WouldRun "System preferences" }

    # Default apps - one line covering every $DEFAULT_APPS target. "Done" once every
    # installed app owns its types; nothing to do if none of them are installed.
    $names        = ($DEFAULT_APPS | ForEach-Object { Get-PkgAlias $_.WingetId }) -join ", "
    $installedApps = @($DEFAULT_APPS | Where-Object { Test-Path $_.Exe })
    $anyInstalled = $installedApps.Count -gt 0
    $allDefault   = -not ($installedApps | Where-Object { -not (Test-DefaultOwned $_) })
    if (-not $anyInstalled -and $FAST)      { Skipped  "Make default: $names - one or more not installed" }
    elseif ($anyInstalled -and $allDefault) { Done     "Make default: $names" }
    else                                    { WouldRun "Make default: $names" }

    # Install or update apps - winget packages, non-winget programs (Premiere Pro plugins) and uv tools
    # (each entry paired with its "already installed?" check). Installation is slow, so it runs last.
    $apps = @()
    foreach ($pkg in $CORE_PKGS)              { $apps += @{ name = (Get-PkgAlias $pkg); ok = (Test-WingetInstalled $pkg) } }
    if ($FULL) { foreach ($pkg in $FULL_PKGS) { $apps += @{ name = (Get-PkgAlias $pkg); ok = (Test-WingetInstalled $pkg) } } }
    if ($PREMIERE_OK) {
        $apps += @{ name = "Mister Horse"; ok = (Test-MisterHorseInstalled) }
        $apps += @{ name = "Flicker Free";                 ok = (Test-FlickerFreeInstalled) }
    }
    foreach ($pkg in $CORE_UV)                { $apps += @{ name = $pkg; ok = (Test-UvInstalled $pkg) } }

    if ($FAST) {
        Skipped ("Install or update: " + (($apps | ForEach-Object { $_.name }) -join ", "))
    } else {
        $done = @($apps | Where-Object { $_.ok }      | ForEach-Object { $_.name })
        $todo = @($apps | Where-Object { -not $_.ok }  | ForEach-Object { $_.name })
        if ($done.Count -gt 0) { Done     ("Install or update: " + ($done -join ", ")) }
        if ($todo.Count -gt 0) { WouldRun ("Install or update: " + ($todo -join ", ")) }
    }

    Write-Host ""
}

# -----------------------------------------------------------------------------
# Phase functions
# -----------------------------------------------------------------------------
# Invoke-FastPass - lightweight preference changes only (no downloads/installs).
# Invoke-SlowPass - everything that downloads or installs. Setting default apps is config
# that needs the app present, so Set-DefaultApps runs in both phases (idempotent: it
# re-checks the current default and no-ops once the app already owns its types). The
# bare command runs Invoke-FastPass inline then hands off to a Full pass that runs
# Invoke-SlowPass; --fast runs Invoke-FastPass only and --full runs both.

# Resolve the ProgId $app should own for $ext (fills in "{ext}" when present).
function Get-DefaultProgId($app, $ext) { $app.ProgId -replace '\{ext\}', $ext }

# True when $app is already the OS default for its file types (probe the first ext).
function Test-DefaultOwned($app) {
    $ext = $app.Exts[0]
    $cur = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.$ext\UserChoice" -ErrorAction SilentlyContinue).ProgId
    $cur -eq (Get-DefaultProgId $app $ext)
}

function Set-DefaultApps {
    # Point Explorer's per-extension UserChoice at each $DEFAULT_APPS target's ProgIds.
    # Each app is gated on being installed and re-checks the current default, so it's a
    # no-op once owned and safe to call from both phases.
    foreach ($app in $DEFAULT_APPS) {
        if (-not (Test-Path $app.Exe)) { continue }
        if (Test-DefaultOwned $app)        { continue }
        foreach ($ext in $app.Exts) {
            try { Set-FileAssociation ".$ext" (Get-DefaultProgId $app $ext) } catch {}
        }
    }
}

function Install-AhkMacros {
    # Download the AHK macro script into the work dir and launch it now so the
    # shortcuts work immediately. The file's presence there is the "done" marker.
    if (Test-Path $AhkScript) { return }
    $ahkExe = Find-AhkExe
    if (-not $ahkExe) {
        Write-Host "  [warn] AutoHotkey not found - skipping AHK shortcuts"
        return
    }
    curl.exe -s -o $AhkScript "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/MacKeyboard_LGG.ahk"
    # Quote the path and launch non-elevated - so macros will work only on non-elevated apps.
    Start-Process $ahkExe -ArgumentList "`"$AhkScript`""
}

function Invoke-FastPass {
    # Premiere Pro shortcuts, workspace & LUTs
    if ($PREMIERE_OK) {
        foreach ($profileDir in Get-ChildItem "$HOME\Documents\Adobe\Premiere Pro\*\Profile-*" -Directory -ErrorAction SilentlyContinue) {
            $prefs   = Join-Path $profileDir.FullName "Adobe Premiere Pro Prefs"
            $winDir  = Join-Path $profileDir.FullName "Win"
            $layouts = Join-Path $profileDir.FullName "Layouts"

            # Premiere creates Win/ and Layouts/ inside each profile, so we write into
            # them rather than creating them ourselves.
            # Drop the shortcuts into the Profile's Win folder (where Premiere reads custom sets)
            curl.exe -s --output-dir $winDir  -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$KYS_FILE"
            # Drop the workspace into Layouts. Premiere auto-registers it on launch.
            curl.exe -s --output-dir $layouts -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$LAYOUT_FILE"
            $wsName = Get-WorkspaceName (Join-Path $layouts $LAYOUT_FILE)

            if ($PREMIERE_RUNNING) {
                Write-Host "  [warn] Premiere Pro is running - files dropped but not activated"
            } elseif (Test-Path $prefs) {
                # $profileDir.Parent.Name is the version folder (e.g. "25.0"), so each
                # profile's warning is tagged with the Premiere version it came from.
                Set-PremiereProPrefs $prefs $KYS_FILE $wsName $profileDir.Parent.Name
            }
        }

        # LUTs - download every LUT in src/data/LUTs into $WorkDir\LUTs
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

    # AHK macros - apply now if AutoHotkey is already installed (covers --fast on a
    # machine that has it). On a Full run AutoHotkey is installed in Invoke-SlowPass, which
    # applies them there instead - so only act here when it's already present.
    if (Find-AhkExe) { Install-AhkMacros }

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

    # Disable the input-language / keyboard-layout switch hotkeys (Alt+Shift,
    # Ctrl+Shift) at the OS level - "3" = Not Assigned. Done here instead of in the
    # AHK macros because intercepting LAlt & LShift there swallowed Shift and broke
    # Alt+Shift shortcuts (e.g. Win+Alt+Shift+Backspace, Alt+Shift+2).
    # Values are REG_SZ; create the key if a fresh profile lacks it. Applies at next sign-in.
    $toggle = "HKCU:\Keyboard Layout\Toggle"
    if (-not (Test-Path $toggle)) { New-Item -Path $toggle -Force | Out-Null }
    Set-ItemProperty -Path $toggle -Name "Hotkey"          -Value "3" -Type String
    Set-ItemProperty -Path $toggle -Name "Language Hotkey" -Value "3" -Type String
    Set-ItemProperty -Path $toggle -Name "Layout Hotkey"   -Value "3" -Type String

    # Explorer preferences - show all filename extensions (HideFileExt = 0), the
    # Windows counterpart of macOS's AppleShowAllExtensions.
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

    # Tell Explorer to re-read its settings so the change applies without a restart.
    if (-not ([System.Management.Automation.PSTypeName]'Win32Shell').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Shell {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
"@
    }
    [Win32Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)  # SHCNE_ASSOCCHANGED

    # Default apps - config that needs the app present (see Set-DefaultApps)
    Set-DefaultApps
}

function Invoke-SlowPass {
    # Managed packages
    foreach ($pkg in $CORE_PKGS) { Invoke-WingetApply $pkg }
    # Refresh PATH so newly installed tools (uv, etc.) are available in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    # --quiet silences uv's resolve/install progress on success but still prints
    # warnings and errors, so a failed install is surfaced without any capture dance.
    foreach ($pkg in $CORE_UV) { uv tool install $pkg --upgrade --quiet }
    # Add uv's tool bin dir to PATH permanently and refresh for this session.
    uv tool update-shell --quiet
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Full-only managed packages
    if ($FULL) {
        foreach ($pkg in $FULL_PKGS) { Invoke-WingetApply $pkg }
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

    # Non-winget packages (like Premiere Pro plugins); the plugins themselves are then added
    # from within it on first launch.
    if ($PREMIERE_OK) {
        # Skip the download + (elevated) MSI when the Product Manager is already installed.
        if (-not (Test-MisterHorseInstalled)) {
            $pmPath = "$WorkDir\MisterHorseProductManager.msi"
            curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
            $pm = Start-Process msiexec.exe -ArgumentList "/i `"$pmPath`" /qn" -Verb RunAs -Wait -PassThru
            # Clean up the installer once it finished successfully (exit 0).
            if ($pm.ExitCode -eq 0) { Remove-Item $pmPath -Force -ErrorAction SilentlyContinue }
        }

        # Flicker Free 2.0. The download is a zip wrapping the installer .exe; we extract it and
        # run the installer.
        if (-not (Test-FlickerFreeInstalled)) {
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
}

# -----------------------------------------------------------------------------
# Dispatch - Invoke-FastPass inline; the bare command then hands off to a Full pass,
# and Invoke-SlowPass does the downloads/installs.
# -----------------------------------------------------------------------------

# Wrapped so Remove-SelfTemp always runs (finally runs even on `exit`), deleting our
# %TEMP% copy of the script on every path - dry-run, fast, full, and both sides of
# the hand-off (the child cleans its own copy on completion; the parent's finally is
# then a no-op).
try {
    # --dry-run just prints the checklist (a preview, since nothing has run), then stops.
    if ($DRY_RUN) { Show-Checklist; exit 0 }

    if ($RUN_FAST) { Invoke-FastPass }

    if ($AUTO) {
        # Fast pass finished. Only now save the script to a temp file - so nothing is
        # left on disk if the user stops here - run the Full pass from it, then the
        # finally below deletes it. The Full pass prints the post-install summary at
        # the end (its live state covers what this Fast pass just did too), so we
        # don't print one here.
        Read-Host "  Fast loading is complete. Press enter to continue on FULL mode" | Out-Null
        $self = "$env:TEMP\load-win.ps1"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing |
            Set-Content $self -Encoding UTF8
        $env:LOAD_FROM_FAST = "1"
        powershell -ExecutionPolicy Bypass -File $self --full
        exit $LASTEXITCODE
    }

    if ($RUN_SLOW) { Invoke-SlowPass }

    # End state summary.
    Show-Checklist
    Write-Host "  You're ready to roll!"
    Write-Host ""
} finally {
    Remove-SelfTemp
}
