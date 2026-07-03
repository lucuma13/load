<#
.SYNOPSIS
Windows workstation setup script

.NOTES
Copyright (c) 2026 Luis Gomez Gutierrez

.EXAMPLE
# Stream and run in memory (avoids MOTW / blocking GPO). Flags: --fast/--full/--dry-run.
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1").Content))

.EXAMPLE
# Alternative for Constrained Language Mode (download and run, gracefully downgrade under $CLM). Flags: --fast/--full/--dry-run.
$f="$env:TEMP\load-win.ps1"; Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lucuma13/load/main/src/load-win.ps1" -UseBasicParsing -OutFile $f -ErrorAction Stop; if(-not ((Get-Content $f -Raw).TrimEnd().EndsWith('# === END load-win.ps1 ==='))){throw "download incomplete - try again"}; powershell -ExecutionPolicy Bypass -File $f
#>

$ErrorActionPreference = "Continue"

Set-StrictMode -Version Latest

# Constrained Language Mode (enforced by WDAC/AppLocker) blocks Add-Type, P/Invoke,
# crypto and most .NET method calls. Steps that need those degrade to a clean
# "skipped (CLM)".
$CLM = $ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'

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

# Find-UvExe - locate the uv executable, or return $null. We invoke uv by full path so
# the uv-tool installs don't depend on the session PATH having refreshed after winget
# installed it - which is unreliable under CLM, where %vars% in the registry PATH can't
# be expanded. Checks PATH first, then winget's usual install/shim locations.
function Find-UvExe {
    $exe = Get-Command uv.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $exe) {
        $exe = Get-ChildItem `
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe", `
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\astral-sh.uv*\uv.exe", `
            "$env:ProgramFiles\WinGet\Links\uv.exe", `
            "$env:USERPROFILE\.local\bin\uv.exe" `
            -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }
    return $exe
}

# Get-WorkspaceName <ws_file> - return the workspace display name from the XML file,
# stored under the UserName key.
function Get-WorkspaceName {
    param($wsFile)
    $content = Get-Content -LiteralPath $wsFile -Raw
    if ($content -match '<key>UserName</key>\s*<ustring>(.*?)</ustring>') { return $Matches[1] }
    return ""
}

# Set-PrefNode <prefs> <node> <value> - replace an XML leaf node's text in place.
# Returns $false WITHOUT touching the file when the node is absent, so callers
# can flag nodes a future Premiere version may have renamed (no edit = no corruption).
function Set-PrefNode {
    param($prefs, $node, $value)
    $bytes = [System.IO.File]::ReadAllBytes($prefs)
    $enc = [System.Text.Encoding]::UTF8
    $content = $enc.GetString($bytes)
    $open = "<$node>"
    $close = "</$node>"
    $idx = $content.IndexOf($open)
    if ($idx -lt 0) { return $false }
    $closeIdx = $content.IndexOf($close, $idx + $open.Length)
    $new = $content.Substring(0, $idx + $open.Length) + $value + $content.Substring($closeIdx)
    [System.IO.File]::WriteAllBytes($prefs, $enc.GetBytes($new))
    return $true
}

# Set-PremierePro <prefs> <kys_file> <ws_name> - point Premiere Pro's keyboard shortcuts preset
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
function Set-PremierePro {
    param($prefs, $kysFile, $wsName, $version)
    $labelNames = @('Violet', 'Iris', 'Caribbean', 'Lavender', 'Cerulean', 'Forest', 'Rose', 'Mango', 'Purple', 'Blue', 'Teal', 'Magenta', 'Tan', 'Green', 'Brown', 'Yellow')
    $labelColors = @('14717094', '13408882', '10016297', '14910691', '14597935', '5814353', '10776567', '3909357', '9896087', '16727100', '8421376', '15151847', '9814478', '2191389', '1262987', '6611682')
    $missing = @()

    # Keyboard shortcuts preset
    if (-not (Set-PrefNode -Prefs $prefs -Node "FE.Prefs.Shortcuts.Filename" -Value $kysFile)) { $missing += "FE.Prefs.Shortcuts.Filename" }

    # Active workspace
    if ($wsName) {
        if (-not (Set-PrefNode -Prefs $prefs -Node "FE.Application.LastWorkspaceName" -Value $wsName)) { $missing += "FE.Application.LastWorkspaceName" }
    }

    # Classic label colour preset
    for ($i = 0; $i -lt $labelNames.Count; $i++) {
        if (-not (Set-PrefNode -Prefs $prefs -Node "BE.Prefs.LabelNames.$i"  -Value $labelNames[$i])) { $missing += "BE.Prefs.LabelNames.$i" }
        if (-not (Set-PrefNode -Prefs $prefs -Node "BE.Prefs.LabelColors.$i" -Value $labelColors[$i])) { $missing += "BE.Prefs.LabelColors.$i" }
    }
    if (-not (Set-PrefNode -Prefs $prefs -Node "PPro.LabelColorPresets.RecentPreset" -Value '{"builtIn":true,"name":"Classic"}')) { $missing += "PPro.LabelColorPresets.RecentPreset" }

    # Auto-save every 5 minutes
    if (-not (Set-PrefNode -Prefs $prefs -Node "BE.Prefs.AutoSave.DoSave"   -Value "true")) { $missing += "BE.Prefs.AutoSave.DoSave" }
    if (-not (Set-PrefNode -Prefs $prefs -Node "BE.Prefs.AutoSave.Interval" -Value "5")) { $missing += "BE.Prefs.AutoSave.Interval" }

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
        if (-not (Set-PrefNode -Prefs $prefs -Node $node -Value "true")) { $missing += $node }
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
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sub = "software\microsoft\windows\currentversion\explorer\fileexts\$Extension\userchoice"
    $ft = [long][math]::Floor([datetime]::UtcNow.ToFileTime() / 10000000) * 10000000
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
    }
    catch {}
    $uc = $parent.CreateSubKey("UserChoice")
    $uc.SetValue("ProgId", $ProgId)
    $uc.SetValue("Hash", $hash)
    $uc.Close()
    $parent.Close()
}

# winget package lists. Kept above the guard so the test suite can source them and
# confirm every id still resolves on winget (catches renames/delisting/typos).
# uv is singled out: it installs per-user (its tools live in the user's home), so it's
# kept out of the elevated machine-wide batch and installed in the non-elevated process.
$UV_PKG = "astral-sh.uv"
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

# Default-app targets - the apps we make the OS default for and the file types each
# should own. WingetId ties each to its package so the friendly name comes from
# $PKG_ALIAS (shared with the "install or update" checklist line). ProgId contains
# "{ext}" for installers that register a per-extension ProgId (VLC -> VLC.mp4,
# VLC.mkv, ...); otherwise it's a single ProgId used for every type (the 64-bit
# Acrobat Reader). This one list drives the checklist and Set-DefaultApp.
$DEFAULT_APPS = @(
    @{
        WingetId = "VideoLAN.VLC"
        Exe      = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"
        ProgId   = "VLC.{ext}"
        Exts     = @('mp4', 'm4v', 'mov', 'mkv', 'avi', 'wmv', 'flv', 'webm', 'mpg', 'mpeg', 'm2ts', 'mts', 'ts', 'vob', 'mxf')
    }
    @{
        WingetId = "Adobe.Acrobat.Reader.64-bit"
        Exe      = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
        ProgId   = "Acrobat.Document.DC"
        Exts     = @('pdf')
    }
)

# Remove-SelfTemp - delete our own copy when we were launched from a temp file. The
# documented entrypoint downloads the script to %TEMP% before running it; PowerShell
# loads the whole script into memory first, so deleting the file mid-run is safe. Only
# ever removes a copy under %TEMP% - a checkout or any other location is left untouched.
function Remove-SelfTemp {
    # $path/$temp default to the live script path and TEMP, but are injectable so the
    # guard can be unit-tested. Guard on $temp being non-empty: StartsWith("") is true
    # for every path, so a blank TEMP must NOT match (and delete) an arbitrary script path.
    param([string]$path = $PSCommandPath, [string]$temp = $env:TEMP)
    if ($temp -and $path -and $path.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# Sourced as a library (tests set $env:LOAD_LIB): stop here, run nothing below.
if ($env:LOAD_LIB) { return }

# -----------------------------------------------------------------------------
# Flags
# -----------------------------------------------------------------------------

$FULL = $args -contains "--full"
$FAST = $args -contains "--fast"
$DRY_RUN = $args -contains "--dry-run"

# No flag given - run the Fast pass inline now (quick config), then pause and run the
# Full pass in this same process. Bail if there's no interactive console (e.g. CI) so
# we don't run a heavy install on an unattended box.
$AUTO = $false
if (-not ($FULL -or $FAST -or $DRY_RUN)) {
    if ([System.Console]::IsInputRedirected) {
        Write-Error "No setup flag given and no interactive console. Pass --fast or --full."
        Remove-SelfTemp
        exit 1
    }
    $AUTO = $true
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

$PREMIERE_OK = Test-Path "$HOME\Documents\Adobe\Premiere Pro"
# Premiere may rewrites its prefs while running - activating a set while it's running can get clobbered.
$PREMIERE_RUNNING = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
$WINGET_OK = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

# Premiere shortcut set + workspace we distribute
$KYS_FILE = "LGG_25.1_WINDOWS.kys"
$LAYOUT_FILE_1 = "UserWorkspace_LGG_1.xml"
$LAYOUT_FILE_2 = "UserWorkspace_LGG_2.xml"

# Keyboard repeat
$KB_Speed = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
$KB_Delay = (Get-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
$KB_OK = ($KB_Speed -eq "31") -and ($KB_Delay -eq "0")

function Test-WingetInstalled($id) {
    if (-not $WINGET_OK) { return $false }
    $result = winget list --id $id --accept-source-agreements 2>$null
    return $LASTEXITCODE -eq 0 -and ($result -match [regex]::Escape($id))
}

# Invoke-WingetApply <id> [scope] - install the package, or upgrade it in place when
# already present. <scope> ("user"/"machine") is passed only on a fresh install; an
# upgrade keeps the existing install's scope. winget's native output is shown only for
# installs/upgrades and errors. Used for the non-elevated, per-user installs (uv); the
# elevated machine-wide batch builds its own winget command lines (see Invoke-ElevatedInstall).
function Invoke-WingetApply($id, $scope) {
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
    }
    else {
        $scopeArg = if ($scope) { @("--scope", $scope) } else { @() }
        winget install --id $id --exact --silent @scopeArg --accept-package-agreements --accept-source-agreements
    }
}

function Test-UvInstalled($pkg) {
    $uv = Find-UvExe
    if (-not $uv) { return $false }
    return [bool]((& $uv tool list 2>$null) -match "^$pkg")
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
        $content = Get-Content -LiteralPath $prefs -Raw
        if ($content -match "<FE\.Prefs\.Shortcuts\.Filename>$([regex]::Escape($KYS_FILE))</FE\.Prefs\.Shortcuts\.Filename>") { return $true }
    }
    return $false
}

# Test-LutPresent - true once at least one LUT has been downloaded into the work dir.
function Test-LutPresent { [bool](Get-ChildItem "$WorkDir\LUTs" -File -ErrorAction SilentlyContinue | Select-Object -First 1) }

function Done { param($msg); Write-Host ("  " + "[done]".PadRight(12) + $msg) }
function Skipped { param($msg); Write-Host ("  " + "[skipped]".PadRight(12) + $msg) }
function WouldRun { param($msg); Write-Host ("  " + "[would run]".PadRight(12) + $msg) }

# Show-Checklist - print the live state of every action: [done], [skipped] or [would
# run]. The same call works at the start of a run (a preview - nothing done yet) or
# at the end (a summary - state reflects what ran), because every line is derived
# from the real current state plus the run mode. No flags, no "post" switch.
function Show-Checklist {
    $kbSpeed = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -ErrorAction SilentlyContinue).KeyboardSpeed
    $kbDelay = (Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -ErrorAction SilentlyContinue).KeyboardDelay
    $kbOk = ($kbSpeed -eq "31") -and ($kbDelay -eq "0")
    # Input-language / keyboard-layout switch hotkeys disabled ("3" = Not Assigned).
    $toggle = Get-ItemProperty "HKCU:\Keyboard Layout\Toggle" -ErrorAction SilentlyContinue
    $togglesOk = $toggle -and $toggle.Hotkey -eq "3" -and $toggle.'Language Hotkey' -eq "3" -and $toggle.'Layout Hotkey' -eq "3"
    $sysOk = $kbOk -and $togglesOk
    $premiereRunning = $PREMIERE_OK -and ($null -ne (Get-Process -Name "Adobe Premiere Pro*" -ErrorAction SilentlyContinue))
    $ahkActive = Test-Path $AhkScript
    $ahkInstalled = [bool](Find-AhkExe)

    Write-Host ""

    # Constrained Language Mode disables the .NET-backed steps below; flag it once up top
    # so the per-line "skipped" reasons make sense.
    if ($CLM) { Write-Host "  [info] Constrained Language Mode active - default apps and Premiere prefs can't be scripted; keyboard/Explorer settings persist but apply at next sign-in." }

    # Premiere Pro - shortcuts, workspace, preferences and LUTs are the editing setup, so they
    # all require Premiere installed. (When Premiere is open the files are dropped but not activated.)
    if (-not $PREMIERE_OK) { Skipped  "Premiere Pro (shortcuts, workspace, preferences, LUTs) - Premiere Pro not installed" }
    elseif ($premiereRunning) { Skipped  "Premiere Pro (shortcuts, workspace, preferences, LUTs) - Premiere Pro is open" }
    elseif ($CLM) { Skipped  "Premiere Pro (shortcuts, workspace, preferences, LUTs) - Not allowed under Constrained Language Mode" }
    elseif ((Test-PremiereApplied) -and (Test-LutPresent)) { Done "Premiere Pro (shortcuts, workspace, preferences, LUTs)" }
    else { WouldRun "Premiere Pro (shortcuts, workspace, preferences, LUTs)" }

    # Activate AHK macros - applied whenever AutoHotkey is present. In --fast we might only
    # have a pre-installed AutoHotkey to work with (installing it is a Full-pass step).
    if ($ahkActive) { Done     "Activate AHK macros" }
    elseif ($ahkInstalled) { WouldRun "Activate AHK macros" }
    elseif ($FAST) { Skipped  "Activate AHK macros - AutoHotkey not installed" }
    else { WouldRun "Activate AHK macros" }

    # System preferences - keyboard repeat speed/delay and the disabled layout-switch hotkeys
    if ($sysOk) { Done "System preferences" } else { WouldRun "System preferences" }

    # Default apps - one line covering every $DEFAULT_APPS target. "Done" once every
    # installed app owns its types; nothing to do if none of them are installed.
    $names = ($DEFAULT_APPS | ForEach-Object { Get-PkgAlias $_.WingetId }) -join ", "
    $installedApps = @($DEFAULT_APPS | Where-Object { Test-Path $_.Exe })
    $anyInstalled = $installedApps.Count -gt 0
    $allDefault = -not ($installedApps | Where-Object { -not (Test-DefaultOwned $_) })
    if ($CLM) { Skipped  "Make default: $names - Not allowed under Constrained Language Mode" }
    elseif (-not $anyInstalled -and $FAST) { Skipped  "Make default: $names - one or more not installed" }
    elseif ($anyInstalled -and $allDefault) { Done     "Make default: $names" }
    else { WouldRun "Make default: $names" }

    # Install or update apps - winget packages, non-winget programs (Premiere Pro plugins) and uv tools
    # (each entry paired with its "already installed?" check). Installation is slow, so it runs last.
    $apps = @()
    foreach ($pkg in $CORE_PKGS) { $apps += @{ name = (Get-PkgAlias $pkg); ok = (Test-WingetInstalled $pkg) } }
    if ($FULL) { foreach ($pkg in $FULL_PKGS) { $apps += @{ name = (Get-PkgAlias $pkg); ok = (Test-WingetInstalled $pkg) } } }
    if ($PREMIERE_OK) {
        $apps += @{ name = "Mister Horse"; ok = (Test-MisterHorseInstalled) }
        $apps += @{ name = "Flicker Free"; ok = (Test-FlickerFreeInstalled) }
    }
    foreach ($pkg in $CORE_UV) { $apps += @{ name = $pkg; ok = (Test-UvInstalled $pkg) } }

    if ($FAST) {
        Skipped ("Install or update: " + (($apps | ForEach-Object { $_.name }) -join ", "))
    }
    else {
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
# that needs the app present, so Set-DefaultApp runs in both phases (idempotent: it
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

function Set-DefaultApp {
    # Point Explorer's per-extension UserChoice at each $DEFAULT_APPS target's ProgIds.
    # Each app is gated on being installed and re-checks the current default, so it's a
    # no-op once owned and safe to call from both phases.
    # The UserChoice tamper-hash needs MD5 + a registry-ACL edit, neither of which is
    # available under CLM - skip the whole step there (the checklist reports it).
    if ($CLM) { return }
    foreach ($app in $DEFAULT_APPS) {
        if (-not (Test-Path $app.Exe)) { continue }
        if (Test-DefaultOwned $app) { continue }
        foreach ($ext in $app.Exts) {
            try { Set-FileAssociation ".$ext" (Get-DefaultProgId $app $ext) } catch {}
        }
    }
}

function Install-AhkScript {
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
            $prefs = Join-Path $profileDir.FullName "Adobe Premiere Pro Prefs"
            $winDir = Join-Path $profileDir.FullName "Win"
            $layouts = Join-Path $profileDir.FullName "Layouts"

            # Premiere creates Win/ and Layouts/ inside each profile, so we write into
            # them rather than creating them ourselves.
            # Drop the shortcuts into the Profile's Win folder (where Premiere reads custom sets)
            curl.exe -s --output-dir $winDir  -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$KYS_FILE"
            # Drop the workspaces into Layouts. Premiere auto-registers them on launch.
            curl.exe -s --output-dir $layouts -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$LAYOUT_FILE_1"
            curl.exe -s --output-dir $layouts -O "https://raw.githubusercontent.com/lucuma13/load/refs/heads/main/src/data/$LAYOUT_FILE_2"
            $wsName = Get-WorkspaceName (Join-Path $layouts $LAYOUT_FILE_1)

            if ($PREMIERE_RUNNING) {
                Write-Host "  [warn] Premiere Pro is running - files dropped but not activated"
            }
            elseif ($CLM) {
                # The prefs write is a byte-level .NET edit (the only no-BOM writer on
                # PowerShell 5.1); it can't run under CLM. The shortcut/workspace files
                # are still dropped above - Premiere registers the workspace on launch.
                Write-Host "  [warn] Constrained Language Mode - shortcut/workspace files dropped but prefs not modified"
            }
            elseif (Test-Path $prefs) {
                # $profileDir.Parent.Name is the version folder (e.g. "25.0"), so each
                # profile's warning is tagged with the Premiere version it came from.
                Set-PremierePro -Prefs $prefs -KysFile $KYS_FILE -WsName $wsName -Version $profileDir.Parent.Name
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
        }
        catch {
            Write-Host "  [warn] Could not fetch LUTs: $_"
        }
    }

    # AHK macros - apply now if AutoHotkey is already installed (covers --fast on a
    # machine that has it). On a Full run AutoHotkey is installed in Invoke-SlowPass, which
    # applies them there instead - so only act here when it's already present.
    if (Find-AhkExe) { Install-AhkScript }

    # Keyboard preferences
    if (-not $KB_OK) {
        # Persist across reboots
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value 31
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value 0

        # Apply to the active session immediately (no logoff needed). Needs Add-Type +
        # P/Invoke, both blocked under CLM - the registry writes above still persist, so
        # under CLM the change just takes effect at next sign-in instead of instantly.
        if (-not $CLM) {
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

    # Show the status bar at the bottom of Explorer windows (ShowStatusBar = 1).
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowStatusBar" -Value 1

    # Tell Explorer to re-read its settings so the change applies without a restart.
    # Add-Type/P-Invoke is blocked under CLM; the HideFileExt write above persists, so
    # under CLM the change just applies on the next Explorer restart instead of now.
    if (-not $CLM) {
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
    }

    # Default apps - config that needs the app present (see Set-DefaultApp)
    Set-DefaultApp
}

# Update-SessionPath - pull the freshly-installed tools' PATH entries into this
# session. Normally rebuilds $env:Path from the Machine + User stores via .NET (which
# expands %vars%). Under CLM that .NET call is blocked, so fall back to reading the
# registry with cmdlets and *appending* to the live $env:Path (REG_EXPAND_SZ entries
# come back unexpanded, so we keep the current PATH rather than replacing it).
function Update-SessionPath {
    if (-not $CLM) {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
        return
    }
    $machine = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path -ErrorAction SilentlyContinue).Path
    $user = (Get-ItemProperty "HKCU:\Environment" -Name Path -ErrorAction SilentlyContinue).Path
    $env:Path = (@($env:Path, $machine, $user) | Where-Object { $_ }) -join ";"
}

# Invoke-ElevatedInstall - run every install that needs admin rights in ONE elevated
# process, so a standard user is asked for the admin password just once. The
# install/upgrade decisions and the plugin downloads happen here (non-elevated); only
# the installers run elevated. winget runs with --scope machine so packages install
# system-wide and are available to the standard user; uv is excluded (it must stay
# per-user - see Invoke-SlowPass). Does nothing, and prompts for nothing, when there's
# nothing left to install.
#
# The batch is handed to an elevated cmd.exe via its command line: AppLocker's
# script-file rules and AV script heuristics don't apply, and cmd works under CLM too.
function Invoke-ElevatedInstall {
    $cmds = @()

    # winget: everything except uv, installed machine-wide. An upgrade keeps the
    # existing install's scope, so --scope is only set on a fresh install. winget waits
    # for its own installer, so no "start /wait" wrapper is needed here.
    if ($WINGET_OK) {
        $ids = @($CORE_PKGS | Where-Object { $_ -ne $UV_PKG })
        if ($FULL) { $ids += $FULL_PKGS }
        foreach ($id in $ids) {
            if (Test-WingetInstalled $id) {
                $cmds += "winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements"
            }
            else {
                $cmds += "winget install --id $id --exact --silent --scope machine --accept-package-agreements --accept-source-agreements"
            }
        }
    }

    # Premiere plugins - download now (no admin needed), install in the elevated batch.
    # msiexec and the Flicker Free GUI installer return immediately, so wrap them in
    # "start /wait" (the leading "" is the required window-title placeholder) so the
    # batch waits for each to finish.
    $cleanup = @()
    if ($PREMIERE_OK) {
        if (-not (Test-MisterHorseInstalled)) {
            $pmPath = "$WorkDir\MisterHorseProductManager.msi"
            curl.exe -fsSL -o $pmPath "https://misterhorse.com/downloads/product-manager/win"
            $cmds += "start `"`" /wait msiexec /i `"$pmPath`" /qn"
            $cleanup += $pmPath
        }
        # Flicker Free 2.0 - the download is a zip wrapping the installer .exe.
        if (-not (Test-FlickerFreeInstalled)) {
            $ffZip = "$WorkDir\flickerfree_229_AE.zip"
            $ffDir = "$WorkDir\flickerfree_229_AE"
            curl.exe -fsSL -o $ffZip "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.zip"
            Expand-Archive -Path $ffZip -DestinationPath $ffDir -Force
            $ffExe = Get-ChildItem $ffDir -Filter *.exe | Select-Object -First 1
            if ($ffExe) {
                $cmds += "start `"`" /wait `"$($ffExe.FullName)`""
                $cleanup += $ffZip
                $cleanup += $ffDir
            }
        }
    }

    if ($cmds.Count -eq 0) { return }  # nothing needs admin - no prompt

    # Join with " & " (run each regardless of the previous one's exit code) and hand it
    # to one elevated cmd.exe. "/s /c" strips just the outermost quotes, leaving the
    # inner quotes around installer paths intact. -Wait so the config that follows sees
    # the installs finished; the elevated console shows install progress.
    $chain = "/s /c `"" + ($cmds -join " & ") + "`""
    try {
        Start-Process cmd.exe -ArgumentList $chain -Verb RunAs -Wait
    }
    catch {
        Write-Host "  [warn] Elevated install step did not run (admin prompt cancelled?): $_"
    }
    foreach ($p in $cleanup) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-SlowPass {
    # All installs that need admin rights (machine-wide winget packages + the Premiere
    # plugins) run in ONE elevated batch. Everything below stays in this non-elevated
    # process so it lands in the real user's profile.
    Invoke-ElevatedInstall

    # uv - installed per-user (no elevation, --scope user) so `uv tool install` lands in
    # THIS user's home, not the admin's. Invoked by full path (see Find-UvExe) so it's
    # found even when the session PATH didn't pick up winget's change (common under CLM).
    if ($WINGET_OK) { Invoke-WingetApply $UV_PKG "user" }
    Update-SessionPath
    $uv = Find-UvExe
    if ($uv) {
        # --quiet silences uv's resolve/install progress on success but still prints
        # warnings and errors, so a failed install is surfaced without any capture dance.
        foreach ($pkg in $CORE_UV) { & $uv tool install $pkg --upgrade --quiet }
        # Add uv's tool bin dir to PATH permanently and refresh for this session.
        & $uv tool update-shell --quiet
        Update-SessionPath
    }
    else {
        Write-Host "  [warn] uv not found after install - reopen the terminal and re-run with --full to finish the uv tools ($($CORE_UV -join ', '))"
    }

    # Tell already-running apps to re-read the environment so the new PATH is picked
    # up without a logoff (this session is already refreshed above). Needs Add-Type +
    # P/Invoke, both blocked under CLM - skip the broadcast there (other apps pick up
    # the persisted PATH when they next start; this session was already refreshed).
    if (-not $CLM) {
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

    # Default apps - now that VLC/Acrobat are installed (covers a fresh machine)
    Set-DefaultApp

    # AHK macros - AutoHotkey was installed above on a Full run (or already present).
    # Launched non-elevated from this process so the macros work on non-elevated apps.
    Install-AhkScript
}

# -----------------------------------------------------------------------------
# Dispatch - Invoke-FastPass applies the quick config; Invoke-SlowPass does the
# downloads/installs. Both run in this same process.
# -----------------------------------------------------------------------------

# Wrapped so Remove-SelfTemp always runs (finally runs even on `exit`), deleting our
# %TEMP% copy of the script on every exit path - dry-run, fast and full.
try {
    # --dry-run just prints the checklist (a preview, since nothing has run), then stops.
    if ($DRY_RUN) { Show-Checklist; exit 0 }

    # Fast pass runs for every mode (--fast, --full, and the bare command).
    Invoke-FastPass

    # The bare command pauses between the quick config and the heavy installs. Enter (or
    # y) continues to the Full pass; n stops here with just the fast setup applied.
    if ($AUTO) {
        $ans = Read-Host "  Fast loading is complete. Continue to FULL mode (downloads + installs)? [Y/n]"
        if ($ans -match '^\s*n') {
            Write-Host "  Stopped after fast setup - re-run with --full to install."
        }
        else {
            $FULL = $true
        }
    }
    if ($FULL) { Invoke-SlowPass }

    # End state summary.
    Show-Checklist
    Write-Host "  You're ready to roll!"
    Write-Host ""
}
finally {
    Remove-SelfTemp
}

# Completeness sentinel - MUST be the last line. The launch command verifies the
# downloaded file ends with this before executing, so a truncated download (e.g. a
# dropped connection) is rejected instead of run as an empty/partial script.
# === END load-win.ps1 ===
