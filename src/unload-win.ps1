<#
.SYNOPSIS
Windows workstation cleanup script

.DESCRIPTION
It removes custom setup - load-win's work directory, our Premiere Pro
workspaces, AutoHotkey, claude-code, Mister Horse Product Manager sign-in, and
the shell history.

--dry-run is the only flag, to see the exact list before deleting.

.NOTES
Copyright (c) 2026 Luis Gomez Gutierrez

.EXAMPLE
# Stream and run in memory (avoids MOTW / blocking GPO).
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri
"https://raw.githubusercontent.com/lucuma13/load/main/src/unload-win.ps1").Content))

.EXAMPLE
# Preview only - print everything that would be removed, remove nothing.
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri
"https://raw.githubusercontent.com/lucuma13/load/main/src/unload-win.ps1").Content))
--dry-run

.EXAMPLE
# Alternative for Constrained Language Mode (download and run).
$f="$env:TEMP\unload-win.ps1"; Invoke-WebRequest -Uri
"https://raw.githubusercontent.com/lucuma13/load/main/src/unload-win.ps1"
-UseBasicParsing -OutFile $f -ErrorAction Stop; if(-not ((Get-Content $f
-Raw).TrimEnd().EndsWith('# === END unload-win.ps1 ==='))){throw "download
incomplete - try again"}; powershell -ExecutionPolicy Bypass -File $f
#>

$ErrorActionPreference = "Continue"

Set-StrictMode -Version Latest

# -----------------------------------------------------------------------------
# Function library
#
# Everything above the LOAD_LIB guard is side-effect-free definitions, so the
# test suite can dot-source this file (with $env:LOAD_LIB set) to exercise
# individual functions without deleting anything.
# -----------------------------------------------------------------------------

# Test-KnownArgument <args> - false when any argument isn't a recognised option.
#
# The bare command removes everything this script knows about, so an
# unrecognised argument must stop the run rather than be ignored: a typo'd
# "--dryrun" would otherwise fall through and be treated as a bare command.
function Test-KnownArgument {
    param([string[]]$Arguments = @())
    foreach ($arg in $Arguments) {
        if ($arg -notin @("--dry-run", "--help", "-h")) { return $false }
    }
    return $true
}

function Show-Usage {
    Write-Host "Usage: unload-win.ps1 [--dry-run]"
    Write-Host ""
    Write-Host "  Removes, from this account only:"
    Write-Host "    - the work directory ~\Downloads\load-win (LUTs, AHK macros, downloads)"
    Write-Host "    - the Premiere Pro workspaces load drops (other workspaces are left alone)"
    Write-Host "    - AutoHotkey: quit and uninstalled"
    Write-Host "    - Mister Horse Product Manager: signed out"
    Write-Host "    - Claude Code: signed out, uninstalled, and its local state wiped"
    Write-Host "    - the PowerShell (PSReadLine) command history"
    Write-Host ""
    Write-Host "  Other apps installed by load are left in place. There is no confirmation"
    Write-Host "  prompt, so use --dry-run to print what would be removed and remove nothing."
}

# Find-AhkExe - locate an installed AutoHotkey interpreter, or return $null.
function Find-AhkExe {
    $exe = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $exe) {
        $exe = Get-ChildItem `
            "$env:ProgramFiles\AutoHotkey", `
            "${env:ProgramFiles(x86)}\AutoHotkey" `
            -Recurse -Filter "AutoHotkey*.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    return $exe
}

# Get-RegValue <path> <name> - the value, or $null when the key or the value is
# absent.
function Get-RegValue($path, $name) {
    Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty $name -ErrorAction SilentlyContinue
}

# Get-DocumentsFolder - the real Documents folder, which is where Premiere keeps
# its profiles.
function Get-DocumentsFolder {
    param($key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")
    $path = Get-RegValue $key 'Personal'
    if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    return "$HOME\Documents"
}

# The repo's src/data listing, where the workspaces `load-win` drops come from.
$WS_API = "https://api.github.com/repos/lucuma13/load/contents/src/data?ref=main"

# Get-WorkspaceFileName [uri] - the workspace filenames from the live listing.
# Empty when the listing can't be read, which the caller reports rather than
# treating as "nothing to remove".
#
# The whole thing is inside the try, the Where-Object included: an error response
# (rate limit, a moved repo) is valid JSON without a "name" property, and under
# Set-StrictMode -Version Latest reading that property throws.
function Get-WorkspaceFileName {
    param($uri = $WS_API)
    try {
        return @(Invoke-RestMethod -Uri $uri -Headers @{ "User-Agent" = "load-setup" } |
                Where-Object { $_.name -like 'UserWorkspace_*.xml' } |
                ForEach-Object { $_.name })
    }
    catch { return @() }
}

# Get-PremiereLayoutDir - the Layouts folders of every Premiere Pro profile on
# this machine.
function Get-PremiereLayoutDir {
    param($premiereDir = (Join-Path (Get-DocumentsFolder) "Adobe\Premiere Pro"))
    $dirs = @()
    foreach ($version in Get-ChildItem -LiteralPath $premiereDir -Directory -ErrorAction SilentlyContinue) {
        foreach ($profileDir in Get-ChildItem -LiteralPath $version.FullName -Directory -Filter "Profile-*" -ErrorAction SilentlyContinue) {
            $layouts = Join-Path $profileDir.FullName "Layouts"
            if (Test-Path -LiteralPath $layouts) { $dirs += $layouts }
        }
    }
    return $dirs
}

# Get-ClaudeStatePath - every per-user path Claude Code writes.
#
# Windows has no keychain, so the OAuth token lives in .credentials.json INSIDE
# ~\.claude and goes with it.
#
# %APPDATA%\Claude is deliberately NOT here (belongs to the Claude desktop app),
# only the CLI's own state is in scope.
function Get-ClaudeStatePath {
    $paths = @(
        "$HOME\.claude"
        "$HOME\.claude.json"
        "$HOME\.claude.json.backup"
    )
    # The CLI's node cache. Confirmed as ~/Library/Caches/claude-cli-nodejs on
    # macOS; this is the LOCALAPPDATA equivalent. Guarded by Test-Path at the
    # call site like every other path here, so if the name ever differs it is a
    # silent no-op rather than an error.
    #
    # Appended only when LOCALAPPDATA is actually set: interpolating an empty
    # variable would yield the relative "\claude-cli-nodejs", which
    # Test-UnderHome then refuses with a warning - a confusing complaint about a
    # path we invented ourselves.
    if ($env:LOCALAPPDATA) { $paths += "$env:LOCALAPPDATA\claude-cli-nodejs" }
    return $paths
}

# Get-MisterHorseStatePath - the per-user state Mister Horse keeps, which on
# Windows is also where the signed-in account lives.
#
# The session is held in the app's own encrypted .dat files under
# %LOCALAPPDATA%\MisterHorse - not in the registry and not in Credential Manager
# - so removing that tree IS the local sign-out.
#
# Guarded on LOCALAPPDATA being set: interpolating an empty variable would yield
# the relative "\MisterHorse", which Test-UnderHome then refuses with a warning
# - a confusing complaint about a path we invented ourselves.
function Get-MisterHorseStatePath {
    if (-not $env:LOCALAPPDATA) { return @() }
    return @("$env:LOCALAPPDATA\MisterHorse")
}

# Get-HistoryPath - every shell-history file to remove.
#
# PSReadLine is what actually persists command history on Windows, and its save
# path is per-host: each host writes its own "<HostName>_history.txt", and a
# profile can move the lot anywhere. So ask the live PSReadLine for its path
# first, then sweep the whole PSReadLine directory for the other hosts' files -
# a console this script was never launched from still has its history on disk.
#
# Deduped, because the live session's path is normally one of the files the
# sweep already found. A real run wouldn't care (Remove-TargetPath is silent the
# second time), but --dry-run would print the same path twice and read like a
# bug.
function Get-HistoryPath {
    $paths = @()
    $opt = Get-PSReadLineOption -ErrorAction SilentlyContinue
    if ($opt -and $opt.HistorySavePath) { $paths += $opt.HistorySavePath }
    # Only when APPDATA is actually set: interpolating an empty variable would yield
    # a relative "\Microsoft\Windows\..." that Test-UnderHome then refuses with a
    # warning - a confusing complaint about a path we invented ourselves.
    if ($env:APPDATA) {
        $dir = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine"
        $paths += "$dir\ConsoleHost_history.txt"
        $paths += @(Get-ChildItem -LiteralPath $dir -Filter "*_history.txt" -File -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName)
    }
    return @($paths | Select-Object -Unique)
}

# Test-UnderHome <path> - true only for a path strictly inside $HOME (or
# LOCALAPPDATA/APPDATA, which sit outside $HOME under a redirected profile) and
# free of "..".
#
# Every removal this script makes is per-user, so this is the single guard
# between a variable that came back empty (or unexpanded, or relative) and a
# recursive delete with a catastrophic argument. Remove-TargetPath refuses
# anything that fails it rather than trusting its caller, because there is no
# undo for what follows.
function Test-UnderHome {
    param([string]$Path)
    if (-not $Path) { return $false }
    if ($Path -like "*..*") { return $false }
    foreach ($root in @($HOME, $env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $root) { continue }
        $prefix = $root.TrimEnd('\') + '\'
        if ($Path.Length -gt $prefix.Length -and $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

# Remove-SelfTemp - delete our own copy when we were launched from a temp file
# (the CLM entrypoint downloads the script to %TEMP% first). PowerShell loads
# the whole script into memory before running it, so deleting the file mid-run
# is safe. Only ever removes a copy under %TEMP%; a checkout is left untouched.
#
# Kept above the library guard, so the tests can reach it..
function Remove-SelfTemp {
    param([string]$path = $PSCommandPath, [string]$temp = $env:TEMP)
    if ($temp -and $path -and $path.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# Sourced as a library (tests set $env:LOAD_LIB): stop here, run nothing below.
if ($env:LOAD_LIB) { return }

# -----------------------------------------------------------------------------
# Flags - the only option is --dry-run.
# -----------------------------------------------------------------------------

if (-not (Test-KnownArgument -Arguments $args)) {
    Write-Host "  [warn] Unrecognised argument. Nothing was removed."
    Show-Usage
    exit 1
}

if (($args -contains "--help") -or ($args -contains "-h")) { Show-Usage; exit 0 }

$DRY_RUN = $args -contains "--dry-run"

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

# Mirrors $WorkDir in load-win.ps1.
$WorkDir = "$HOME\Downloads\load-win"

$WINGET_OK = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

# The winget package id load's Windows side would have used for the CLI.
$CLAUDE_PKG = "Anthropic.ClaudeCode"

# AutoHotkey's id in load-win.ps1's $FULL_PKGS. It is the one app load installs
# that exists purely to serve load - it runs the Mac-keyboard macros and nothing
# else - which is why unload removes it while leaving VLC, FFmpeg and the rest
# of the installed apps in place.
$AHK_PKG = "AutoHotkey.AutoHotkey"

function Section { param($msg); Write-Host ("  " + $msg) }
function Removing { param($msg); Write-Host ("  " + "[removing]".PadRight(12) + $msg) }
function Kept { param($msg); Write-Host ("  " + "[ok]".PadRight(12) + $msg) }
function NothingToDo { Write-Host ("  " + "[ok]".PadRight(12) + "Nothing to remove") }
function Note { param($msg); Write-Host ("  " + "[note]".PadRight(12) + $msg) }

# Get-DisplayPath <path> - shorten a path under $HOME to ~\... for display.
# Presentation only; never feed the result back to a cmdlet.
function Get-DisplayPath {
    param([string]$Path)
    $prefix = $HOME.TrimEnd('\') + '\'
    if ($Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "~\" + $Path.Substring($prefix.Length)
    }
    return $Path
}

# Remove-TargetPath <path> - remove a file or directory tree, honouring
# --dry-run. Prints exactly one line whether it deletes or only previews, so a
# dry run's output is precisely what a real run would do. Returns $false and
# stays silent when there is nothing there, so callers can distinguish "cleaned"
# from "already clean" and report an empty section as such.
function Remove-TargetPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not (Test-UnderHome $Path)) {
        Write-Host "  [warn] Refusing to remove '$Path' - outside the user profile"
        return $false
    }
    if ($DRY_RUN) {
        Removing "Would remove $(Get-DisplayPath $Path)"
        return $true
    }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) {
        Write-Host "  [warn] Could not remove $(Get-DisplayPath $Path) - a program may be holding it open"
        return $false
    }
    Removing "Removed $(Get-DisplayPath $Path)"
    return $true
}

# Test-WingetPackage <id> - true when winget reports the package installed.
function Test-WingetPackage($id) {
    if (-not $WINGET_OK) { return $false }
    $listed = winget list --id $id --exact --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0) -and ($listed -match [regex]::Escape($id))
}

# Uninstall-WingetPackage <id> <label> - uninstall a winget package, elevating
# only if it turns out to be necessary. Returns $true when the package was there
# to remove (so the caller can tell "cleaned" from "already clean"), $false when
# it was never installed.
#
# The result is re-checked against winget because the elevated console swallows
# its own exit code.
function Uninstall-WingetPackage($id, $label) {
    if (-not (Test-WingetPackage $id)) { return $false }
    if ($DRY_RUN) {
        Removing "Would uninstall $label (winget package '$id')"
        return $true
    }

    winget uninstall --id $id --exact --silent --accept-source-agreements 2>&1 | Out-Null
    if (-not (Test-WingetPackage $id)) {
        Removing "Uninstalled $label"
        return $true
    }

    try {
        Start-Process cmd.exe -Verb RunAs -Wait -ArgumentList (
            "/s /c `"winget uninstall --id $id --exact --silent --accept-source-agreements`"")
    }
    catch {
        Write-Host "  [warn] Elevated uninstall did not run (admin prompt cancelled?): $_"
    }
    if (-not (Test-WingetPackage $id)) { Removing "Uninstalled $label (needed admin)" }
    else { Write-Host "  [warn] Could not uninstall $label - remove it from Settings > Apps by hand" }
    return $true
}

# -----------------------------------------------------------------------------
# Cleanup phases
# -----------------------------------------------------------------------------

# Stop-AhkProcess - quit every running AutoHotkey interpreter.
#
# No attempt to single out load's own macro by command line. The macro is only a
# file in the work directory, so it goes when that directory does, and
# AutoHotkey itself is uninstalled moments later.
#
# This whole phase runs before the work directory is removed, so nothing is
# executing out of it by the time it goes.
function Stop-AhkProcess {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $false }
    if ($DRY_RUN) {
        Removing "Would quit $($procs.Count) running AutoHotkey process(es)"
        return $true
    }
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Removing "Quit $($procs.Count) running AutoHotkey process(es)"
    return $true
}

function Clear-WorkDir {
    Section "Work directory ($(Get-DisplayPath $WorkDir))"
    if (-not (Remove-TargetPath $WorkDir)) { NothingToDo }
}

# Clear-PremiereWorkspace - remove our workspace files into Premiere profile's
# Layouts folders.
function Clear-PremiereWorkspace {
    Section "Premiere Pro workspaces"
    $dirs = @(Get-PremiereLayoutDir)
    # No Premiere profile means nothing to remove - and no reason to go to the
    # network for the list.
    if ($dirs.Count -eq 0) { NothingToDo; return }

    $names = @(Get-WorkspaceFileName)
    if ($names.Count -eq 0) {
        Write-Host "  [warn] Could not read the workspace list from GitHub - Premiere workspaces left in place"
        return
    }

    $did = $false
    foreach ($dir in $dirs) {
        foreach ($name in $names) {
            if (Remove-TargetPath (Join-Path $dir $name)) { $did = $true }
        }
    }
    if (-not $did) { NothingToDo }
}

# Clear-Ahk - quit AutoHotkey and uninstall it.
function Clear-Ahk {
    Section "AutoHotkey"
    $did = $false
    if (Stop-AhkProcess) { $did = $true }
    if (Uninstall-WingetPackage $AHK_PKG "AutoHotkey") { $did = $true }
    if (-not $did) { NothingToDo }

    # Still on disk after the uninstall means it was installed some other way (the
    # .exe/.zip build from autohotkey.com rather than winget), which this script
    # doesn't touch. Say so rather than let a "cleaned" summary imply otherwise.
    if (-not $DRY_RUN) {
        $exe = Find-AhkExe
        if ($exe) { Note "AutoHotkey is still installed at $exe - not a winget install; remove it by hand" }
    }
}

# Get-MisterHorseProcess - every running Mister Horse process (the Product
# Manager and the crash handler that sits beside it).
#
# Matched on the image PATH, not the process name: "ProductManager.exe" is a
# generic enough name to belong to some other vendor's app. A regex rather than
# a WQL filter so both spellings of the vendor's own folder are covered -
# "Mister Horse Product Manager" under Program Files, "MisterHorse" for anything
# installed beside its state dir.
function Get-MisterHorseProcess {
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath -match '(?i)mister ?horse' })
}

# Stop-MisterHorseProcess - quit the Product Manager so the sign-out below
# sticks.
#
# It holds the session in memory and writes its state back as it closes, so
# files deleted underneath a running Product Manager come straight back.
function Stop-MisterHorseProcess {
    # Re-wrapped in @() at the call site, exactly as Stop-AhkProcess wraps its
    # own Get-CimInstance: PowerShell unrolls a returned array, so with nothing
    # running $procs is $null - and under Set-StrictMode -Version Latest,
    # reading .Count off $null is an error rather than a zero.
    $procs = @(Get-MisterHorseProcess)
    if ($procs.Count -eq 0) { return $false }
    if ($DRY_RUN) {
        Removing "Would quit $($procs.Count) running Mister Horse process(es)"
        return $true
    }
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    Removing "Quit $($procs.Count) running Mister Horse process(es)"
    return $true
}

# Clear-MisterHorse - sign this account out of Mister Horse, leaving the plugins
# installed. See Get-MisterHorseStatePath for why removing that state is the
# sign-out.
function Clear-MisterHorse {
    Section "Mister Horse (Animation Composer)"
    $did = $false
    if (Stop-MisterHorseProcess) { $did = $true }
    foreach ($path in Get-MisterHorseStatePath) {
        if (Remove-TargetPath $path) { $did = $true }
    }
    if (-not $did) { NothingToDo }

    # A panel open inside a running Premiere or After Effects has the same
    # session in memory and writes its own copy back when the host quits, so a
    # sign-out performed underneath it does not stick. Killing the host would
    # cost the user unsaved work, so say so instead. Skipped on a dry run, where
    # nothing has been removed for a panel to undo.
    if (-not $DRY_RUN) {
        $hostApps = @(Get-Process -Name "Adobe Premiere Pro*", "AfterFX*" -ErrorAction SilentlyContinue)
        if ($hostApps.Count -gt 0) {
            Note "Premiere Pro / After Effects is open - close it and re-run, or its Mister Horse panel will write the session back."
        }
    }
}

function Clear-Claude {
    Section "Claude Code"
    $did = $false

    # Uninstall before wiping state, so a half-removed install can't confuse
    # winget's own uninstall.
    if (Uninstall-WingetPackage $CLAUDE_PKG "Claude Code") { $did = $true }

    foreach ($path in Get-ClaudeStatePath) {
        if (Remove-TargetPath $path) { $did = $true }
    }

    if (-not $did) { NothingToDo }

    # A `claude` still on PATH after all that was installed some other way - the
    # native installer (~\.local\bin) or a global npm package - which this
    # script deliberately doesn't touch. Say so rather than let a "cleaned"
    # summary imply the machine is clear. Skipped on a dry run, where nothing
    # has been removed yet and the binary is still there by definition.
    if (-not $DRY_RUN) {
        $claude = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
        if ($claude) { Note "'claude' is still on PATH at $claude - not a winget install; remove it by hand" }
    }
}

function Clear-ShellHistory {
    Section "Shell history"
    $did = $false
    foreach ($path in Get-HistoryPath) {
        if (Remove-TargetPath $path) { $did = $true }
    }
    if (-not $did) { NothingToDo }

    # The console you launched this from holds its own commands in memory and
    # PSReadLine appends them to a fresh history file as you keep typing -
    # including the command that ran this script. Clear-History empties this
    # session's buffer; a console that outlives this script is the caller's to
    # close, so say so rather than leave a file to quietly reappear.
    if (-not $DRY_RUN) { Clear-History -ErrorAction SilentlyContinue }
    Note "Close this console when you're done - PSReadLine re-writes its history file as you type."
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

try {
    Write-Host ""
    if ($DRY_RUN) {
        Write-Host "  Dry run - nothing will be removed."
        Write-Host ""
    }

    # AutoHotkey first, and deliberately: it quits every interpreter, so by the time
    # the work directory goes nothing is running out of it.
    Clear-Ahk
    Clear-WorkDir
    Clear-PremiereWorkspace
    Clear-MisterHorse
    Clear-Claude
    Clear-ShellHistory

    Write-Host ""
    if ($DRY_RUN) { Write-Host "  Dry run complete - re-run without --dry-run to remove the above." }
    else { Kept "Cleanup complete. Other apps installed by load were left in place." }
    Write-Host ""
}
finally {
    Remove-SelfTemp
}

# Completeness sentinel - MUST be the last line. The download entrypoint
# verifies the file ends with this before executing, so a truncated download is
# rejected.
# === END unload-win.ps1 ===
