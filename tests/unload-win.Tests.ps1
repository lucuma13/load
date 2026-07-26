# Tests for src/unload-win.ps1
#
# The script is sourced with $env:LOAD_LIB so only its functions load (nothing runs,
# nothing is deleted).
#
# Run:  Invoke-Pester tests\unload-win.Tests.ps1

BeforeAll {
    $env:LOAD_LIB = "1"
    . "$PSScriptRoot\..\src\unload-win.ps1"
    $env:LOAD_LIB = $null
}

# PSScriptAnalyzer's PSUseCompatibleSyntax rule flags any 7+-only syntax (??
# null-coalescing, ternaries, ?. etc.) for the target version, so this fails the
# build before such syntax can ship to the 5.1 default shell on Windows.
Describe "unload-win.ps1 PowerShell 5.1 compatibility" {
    BeforeAll {
        if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
            Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
        }
        Import-Module PSScriptAnalyzer

        $settings = @{
            Rules = @{
                PSUseCompatibleSyntax = @{
                    Enable         = $true
                    TargetVersions = @('5.1')
                }
            }
        }
        $script:violations = Invoke-ScriptAnalyzer -Path "$PSScriptRoot/../src/unload-win.ps1" -Settings $settings -IncludeRule PSUseCompatibleSyntax
    }

    It "uses no syntax unavailable in Windows PowerShell 5.1" {
        $violations | Should -BeNullOrEmpty -Because (
            ($violations | ForEach-Object { "line $($_.Line): $($_.Message)" }) -join "`n")
    }
}

# The script is downloaded and run by pre-installed Windows PowerShell 5.1 on a fresh
# Windows machine, which garbles a UTF-8 BOM and non-ASCII bytes into '?'. Keep the
# distributed script pure ASCII.
Describe "unload-win.ps1 encoding (Windows PowerShell 5.1 safe)" {
    BeforeAll {
        $script:scriptBytes = [System.IO.File]::ReadAllBytes("$PSScriptRoot/../src/unload-win.ps1")
    }

    It "has no byte-order mark" {
        $hasBom = $scriptBytes.Length -ge 3 -and
        $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF
        $hasBom | Should -BeFalse
    }

    It "is pure ASCII (no bytes that garble in legacy PowerShell)" {
        $offenders = for ($i = 0; $i -lt $scriptBytes.Length; $i++) {
            if ($scriptBytes[$i] -gt 0x7F) { $i }
        }
        @($offenders).Count | Should -Be 0 -Because "non-ASCII byte(s) at offset(s): $($offenders -join ', ')"
    }
}

# The script ends with a sentinel line so the launch command can confirm the download
# arrived whole - a truncated copy (dropped connection) loses the tail and is rejected
# before it runs. That matters more here than in the installer: half of a delete script
# is worse than none of it.
Describe "unload-win.ps1 completeness sentinel" {
    BeforeAll {
        $script:sentinel = '# === END unload-win.ps1 ==='
        $script:scriptText = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
    }

    It "is the last line of the distributed script" {
        $scriptText.TrimEnd() | Should -BeLike "*$sentinel"
    }

    It "a truncated copy fails the sentinel check" {
        $truncated = $scriptText.Substring(0, [int]($scriptText.Length / 2))
        # The sentinel string also appears in the .EXAMPLE header near the top, so a
        # truncated copy still *contains* it - which is exactly why the launch check must
        # test ends-with (the tail arrived), not merely presence.
        $truncated | Should -BeLike "*$sentinel*" -Because "the header copy is within the first half"
        $truncated.TrimEnd() | Should -Not -BeLike "*$sentinel"
    }
}

# There are no target flags: the bare command is the whole interface. That makes
# argument validation the safety property worth testing - a typo'd "--dryrun" that
# fell through to "no options given" would delete for real at exactly the moment the
# caller was asking for a preview.
Describe "Test-KnownArgument" {
    It "accepts <Name>" -ForEach @(
        @{ Name = 'the bare command'; Arguments = @() }
        @{ Name = '--dry-run'; Arguments = @('--dry-run') }
        @{ Name = '--help'; Arguments = @('--help') }
        @{ Name = '-h'; Arguments = @('-h') }
    ) {
        Test-KnownArgument -Arguments $Arguments | Should -BeTrue
    }

    It "rejects <Name>" -ForEach @(
        @{ Name = 'a misspelt --dry-run'; Arguments = @('--dryrun') }
        @{ Name = 'an underscored --dry_run'; Arguments = @('--dry_run') }
        @{ Name = 'a target flag that no longer exists'; Arguments = @('--workdir') }
        @{ Name = '--all'; Arguments = @('--all') }
        @{ Name = 'an unknown flag beside a valid one'; Arguments = @('--dry-run', '--nope') }
        @{ Name = 'a bare word'; Arguments = @('workdir') }
    ) {
        Test-KnownArgument -Arguments $Arguments | Should -BeFalse
    }
}

# AutoHotkey is the one app load installs that unload also removes: it exists purely
# to run load's Mac-keyboard macros, unlike VLC/FFmpeg, which are the machine's now.
Describe "AutoHotkey target" {
    It "uninstalls the same winget id load installs" {
        $loadWin = Get-Content "$PSScriptRoot/../src/load-win.ps1" -Raw
        $unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
        $id = 'AutoHotkey.AutoHotkey'
        $loadWin | Should -BeLike "*$id*" -Because "load-win.ps1 should still install it"
        $unloadWin | Should -BeLike "*`$AHK_PKG = `"$id`"*" -Because "a rename in load must be mirrored here"
    }

    # Stopping the interpreters is what lets the uninstall replace files - a live
    # AutoHotkey process would otherwise defer it to a reboot, which on a machine
    # being handed back is the same as not running at all.
    It "quits AutoHotkey before uninstalling it" {
        $unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
        $body = [regex]::Match($unloadWin, '(?s)function Clear-Ahk \{.*?\n\}').Value
        $body | Should -Not -BeNullOrEmpty -Because "Clear-Ahk should be findable"
        $body | Should -BeLike "*Stop-AhkProcess*"
        $body.IndexOf('Stop-AhkProcess') | Should -BeLessThan $body.IndexOf('Uninstall-WingetPackage')
    }

    # No command-line matching: load's macro is just a file in the work directory, so
    # it goes when that directory does, and uninstalling AutoHotkey stops every macro
    # on the machine anyway. Singling one process out would protect nothing.
    It "stops every interpreter rather than matching load's macro by name" {
        $unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
        $body = [regex]::Match($unloadWin, '(?s)function Stop-AhkProcess \{.*?\n\}').Value
        $body | Should -Not -BeNullOrEmpty
        $body | Should -Not -BeLike "*MacKeyboard_LGG*"
        $body | Should -Not -BeLike "*CommandLine*"
    }

    # The work-directory phase does no AutoHotkey handling of its own, and doesn't need
    # to - the AutoHotkey phase runs first and has already quit everything.
    It "clears the work directory without any AutoHotkey handling of its own" {
        $unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
        $body = [regex]::Match($unloadWin, '(?s)function Clear-WorkDir \{.*?\n\}').Value
        $body | Should -Not -BeNullOrEmpty
        $body | Should -Not -BeLike "*Ahk*"
    }

    # The ordering is the whole mechanism: quit the interpreters, then delete the
    # directory they were running out of. Reversed, the macro script would be pulled
    # out from under a live process and the uninstall would meet open file handles.
    It "runs the AutoHotkey phase before the work-directory phase" {
        $unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
        $dispatch = [regex]::Match($unloadWin, '(?s)^try \{.*?\n\}', 'Multiline').Value
        $dispatch | Should -Not -BeNullOrEmpty -Because "the dispatch block should be findable"
        $dispatch.IndexOf('Clear-Ahk') | Should -BeLessThan $dispatch.IndexOf('Clear-WorkDir')
    }
}

# Test-UnderHome is the single guard between a variable that came back empty (or
# unexpanded, or relative) and a recursive delete with a catastrophic argument.
Describe "Test-UnderHome" {
    It "accepts a path strictly inside the profile" {
        Test-UnderHome "$HOME\Downloads\load-win" | Should -BeTrue
        Test-UnderHome "$HOME\.claude" | Should -BeTrue
    }

    # An empty or unexpanded value is the failure mode that matters most: a blank
    # path must never satisfy the guard.
    It "rejects <Name>" -ForEach @(
        @{ Name = 'an empty path'; Path = '' }
        @{ Name = 'a null path'; Path = $null }
        @{ Name = 'the profile root itself'; Path = $HOME }
        @{ Name = 'the profile root with a trailing separator'; Path = "$HOME\" }
        @{ Name = 'a relative path'; Path = 'relative\path' }
        @{ Name = 'parent-directory traversal'; Path = "$HOME\..\..\Windows" }
    ) {
        Test-UnderHome $Path | Should -BeFalse
    }

    It "rejects a path outside the profile" {
        Test-UnderHome "C:\Windows\System32" | Should -BeFalse
        Test-UnderHome "/etc/passwd" | Should -BeFalse
    }
}

# Mister Horse is a sign-out, not an uninstall: the plugins are the machine's now, the
# way VLC and FFmpeg are, but the account signed into them is the departing user's. On
# Windows that session lives in the app's own encrypted files rather than in a keychain,
# so removing them IS the sign-out - which makes the contents of that path list, and the
# order the phase does things in, the properties worth pinning.
Describe "Mister Horse sign-out" {
    BeforeAll {
        $script:unloadWin = Get-Content "$PSScriptRoot/../src/unload-win.ps1" -Raw
    }

    # %LOCALAPPDATA%\MisterHorse holds the Product Manager's session alongside the
    # panel's cached copy of it, so one removal signs out both.
    It "covers the per-user state dir" {
        if (-not $env:LOCALAPPDATA) {
            Set-ItResult -Skipped -Because "LOCALAPPDATA is not set on this host"
            return
        }
        Get-MisterHorseStatePath | Should -Contain "$env:LOCALAPPDATA\MisterHorse"
    }

    # An unset LOCALAPPDATA must yield nothing at all. Interpolating it blindly would
    # produce the relative "\MisterHorse", which Remove-TargetPath then refuses with a
    # warning about a path the script invented itself.
    It "yields nothing when LOCALAPPDATA is unset" {
        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = ""
            @(Get-MisterHorseStatePath).Count | Should -Be 0
        }
        finally { $env:LOCALAPPDATA = $saved }
    }

    It "yields only paths the delete guard will accept" {
        foreach ($path in Get-MisterHorseStatePath) {
            Test-UnderHome $path | Should -BeTrue -Because "'$path' would be refused by Remove-TargetPath"
        }
    }

    # The sign-out must not turn into an uninstall: the plugins live in Program Files
    # and the shared Adobe plug-in folders, and both are out of scope here (they are
    # also machine-wide, so the per-user guard would refuse them anyway).
    It "removes no installed plugin" {
        foreach ($path in Get-MisterHorseStatePath) {
            $path | Should -Not -BeLike "*Program Files*"
            $path | Should -Not -BeLike "*\Adobe\*"
        }
        $body = [regex]::Match($unloadWin, '(?s)function Clear-MisterHorse \{.*?\n\}').Value
        $body | Should -Not -BeNullOrEmpty -Because "Clear-MisterHorse should be findable"
        $body | Should -Not -BeLike "*Uninstall-WingetPackage*"
    }

    # The ordering is the mechanism, as with AutoHotkey: a running Product Manager holds
    # the session in memory and writes its state back as it closes, so files deleted
    # underneath it come straight back and the account is still signed in.
    It "quits the Product Manager before removing its state" {
        $body = [regex]::Match($unloadWin, '(?s)function Clear-MisterHorse \{.*?\n\}').Value
        $body | Should -BeLike "*Stop-MisterHorseProcess*"
        $body.IndexOf('Stop-MisterHorseProcess') | Should -BeLessThan $body.IndexOf('Remove-TargetPath')
    }

    # "ProductManager.exe" is a generic enough name to belong to another vendor
    # entirely, so the process match is on the image path.
    It "matches the app by image path, not by process name" {
        $body = [regex]::Match($unloadWin, '(?s)function Get-MisterHorseProcess \{.*?\n\}').Value
        $body | Should -Not -BeNullOrEmpty
        $body | Should -BeLike "*ExecutablePath*"
    }

    It "runs as its own phase in the dispatch block" {
        $dispatch = [regex]::Match($unloadWin, '(?s)^try \{.*?\n\}', 'Multiline').Value
        $dispatch | Should -Not -BeNullOrEmpty -Because "the dispatch block should be findable"
        $dispatch | Should -BeLike "*Clear-MisterHorse*"
    }
}

Describe "Claude Code target paths" {
    # ~\.claude is the whole point of the Claude target on a machine you're leaving:
    # it holds transcripts, per-project history, memory and the credentials file.
    It "covers the CLI's state" {
        $paths = Get-ClaudeStatePath
        $paths | Should -Contain "$HOME\.claude"
        $paths | Should -Contain "$HOME\.claude.json"
        $paths | Should -Contain "$HOME\.claude.json.backup"
    }

    # The Claude desktop app is a separate product that may well belong to someone
    # else on a shared machine. Only the CLI's own state is in scope, so %APPDATA%\Claude
    # must never creep into the list.
    It "leaves the Claude desktop app alone" {
        Get-ClaudeStatePath | Where-Object { $_ -eq "$env:APPDATA\Claude" } | Should -BeNullOrEmpty
    }

    It "yields only paths the delete guard will accept" {
        foreach ($path in Get-ClaudeStatePath) {
            Test-UnderHome $path | Should -BeTrue -Because "'$path' would be refused by Remove-TargetPath"
        }
    }
}

Describe "Shell history target paths" {
    # PSReadLine is what actually persists command history on Windows. The path is
    # built from %APPDATA%, which only exists on the target platform - on a macOS/Linux
    # host running this suite the entry is correctly omitted, so there is nothing to
    # assert there.
    It "covers the PSReadLine history file" {
        if (-not $env:APPDATA) {
            Set-ItResult -Skipped -Because "APPDATA is not set on this host"
            return
        }
        Get-HistoryPath | Should -Contain "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    }

    # The live session's save path is normally one of the files the directory sweep
    # already finds. A real run wouldn't care - Remove-TargetPath is silent the second
    # time - but --dry-run would print the same path twice and read like a bug.
    It "contains no duplicates" {
        $paths = @(Get-HistoryPath)
        @($paths | Select-Object -Unique).Count | Should -Be $paths.Count
    }
}

# Remove-SelfTemp only ever deletes a copy of the script under $env:TEMP. The blank-TEMP
# guard matters because StartsWith("") is true for every path - a blank TEMP must NOT be
# allowed to match and delete an arbitrary script location.
Describe "Remove-SelfTemp temp-dir guard" {
    It "<Name>" -ForEach @(
        @{ Name = 'deletes a copy under TEMP'; UnderTemp = $true; BlankTemp = $false; ShouldDelete = $true }
        @{ Name = 'leaves a copy outside TEMP untouched'; UnderTemp = $false; BlankTemp = $false; ShouldDelete = $false }
        @{ Name = 'deletes nothing when TEMP is blank'; UnderTemp = $false; BlankTemp = $true; ShouldDelete = $false }
    ) {
        $temp = Join-Path $TestDrive "temp"
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $self = if ($UnderTemp) { Join-Path $temp "unload-win.ps1" } else { Join-Path $TestDrive "elsewhere.ps1" }
        Set-Content $self "x"

        Remove-SelfTemp -path $self -temp $(if ($BlankTemp) { "" } else { $temp })

        Test-Path $self | Should -Be (-not $ShouldDelete)
    }
}

# Hits the network to confirm the pinned winget id is still the one that ships Claude
# Code. Exclude on an offline run with:  Invoke-Pester -ExcludeTag Live
Describe "Claude Code winget id resolves" -Tag 'Live' {
    It "Anthropic.ClaudeCode is found on winget" {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because "winget is not installed"
            return
        }
        winget show --id "Anthropic.ClaudeCode" --exact --source winget --accept-source-agreements --disable-interactivity *> $null
        $LASTEXITCODE | Should -Be 0 -Because "'Anthropic.ClaudeCode' did not resolve (renamed, delisted, or mistyped?)"
    }
}
