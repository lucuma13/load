# Tests for src/load-win.ps1, both whole-script and Premiere-prefs:
#   - PowerShell 5.1 syntax compatibility (no 7+-only syntax ships)
#   - file encoding (pure ASCII, no BOM) so legacy PowerShell doesn't garble it
#   - liveness of the external resources the installer pulls (plugins, winget, PyPI)
#   - Set-PremierePro / Get-WorkspaceName / Set-PrefNode prefs handling
#
# The script is sourced with $env:LOAD_LIB so only its functions load (no installer).
#
# Run:  Invoke-Pester tests\load-win.Tests.ps1

BeforeAll {
    $env:LOAD_LIB = "1"
    . "$PSScriptRoot\..\src\load-win.ps1"
    $env:LOAD_LIB = $null
}

# Discover every captured version; adding a premiere_pro_* fixture dir is enough.
$PremiereVersions = Get-ChildItem "$PSScriptRoot/fixtures" -Directory -Filter 'premiere_pro_*' |
    Sort-Object Name | ForEach-Object {
        @{ Version = ($_.Name -replace '^premiere_pro_v?', ''); Dir = $_.Name }
    }

# Read the timeline nodes straight from the `foreach ($node in @(...))` loop in the
# script (via the AST, so commented-out nodes are ignored).
$TimelineNodes = & {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        "$PSScriptRoot/../src/load-win.ps1", [ref]$null, [ref]$null)
    $loop = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.ForEachStatementAst] -and
            $n.Variable.VariablePath.UserPath -eq 'node' }, $true) | Select-Object -First 1
    $loop.Condition.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
        ForEach-Object { @{ Node = $_.Value } }
}

# PSScriptAnalyzer's PSUseCompatibleSyntax rule flags any 7+-only syntax (??
# null-coalescing, ternaries, ?. etc.) for the target version, so this fails the
# build before such syntax can ship to the 5.1 default shell on Windows.
Describe "load-win.ps1 PowerShell 5.1 compatibility" {
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
        $script:violations = Invoke-ScriptAnalyzer -Path "$PSScriptRoot/../src/load-win.ps1" -Settings $settings -IncludeRule PSUseCompatibleSyntax
    }

    It "uses no syntax unavailable in Windows PowerShell 5.1" {
        $violations | Should -BeNullOrEmpty -Because (
            ($violations | ForEach-Object { "line $($_.Line): $($_.Message)" }) -join "`n")
    }
}

# The script is downloaded and run by pre-installed Windows PowerShell 5.1 on a fresh Windows Machine,
# which garbles a UTF-8 BOM and non-ASCII bytes into '?'. Keep the distributed script pure ASCII.
Describe "load-win.ps1 encoding (Windows PowerShell 5.1 safe)" {
    BeforeAll {
        $script:scriptBytes = [System.IO.File]::ReadAllBytes("$PSScriptRoot/../src/load-win.ps1")
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
# before it runs. This guards the sentinel's presence so the check can't silently rot.
Describe "load-win.ps1 completeness sentinel" {
    BeforeAll {
        $script:sentinel = '# === END load-win.ps1 ==='
        $script:scriptText = Get-Content "$PSScriptRoot/../src/load-win.ps1" -Raw
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

# These hit the network to confirm the hard-coded plugin installer URLs are still live. Exclude them
# on an offline run with:  Invoke-Pester -ExcludeTag Live

# Confirms every pinned winget id still resolves on the winget source
Describe "winget package ids resolve" -Tag 'Live' {
    BeforeDiscovery {
        $env:LOAD_LIB = "1"
        . "$PSScriptRoot\..\src\load-win.ps1"
        $env:LOAD_LIB = $null
        $script:wingetIds = @($CORE_PKGS + $FULL_PKGS)
    }

    It "<_> is found on winget" -ForEach $wingetIds {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because "winget is not installed"
            return
        }
        winget show --id $_ --exact --source winget --accept-source-agreements --disable-interactivity *> $null
        $LASTEXITCODE | Should -Be 0 -Because "'$_' did not resolve (renamed, delisted, or mistyped?)"
    }
}

# Confirms links to apps not available on winget are live
Describe "Plugin download links" -Tag 'Live' {
    $links = @(
        @{ Name = 'Mister Horse Product Manager'; Url = 'https://misterhorse.com/downloads/product-manager/win' }
        @{ Name = 'Flicker Free'; Url = 'https://www.digitalanarchy.com/downloads/flickerfree_229_AE.zip' }
    )

    It "<Name> link is live" -ForEach $links {
        try {
            $resp = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 5 -UseBasicParsing -TimeoutSec 30
        }
        catch {
            # Some servers reject HEAD - fall back to a 1-byte ranged GET.
            $resp = Invoke-WebRequest -Uri $Url -Headers @{ Range = 'bytes=0-0' } -MaximumRedirection 5 -UseBasicParsing -TimeoutSec 30
        }
        [int]$resp.StatusCode | Should -BeIn @(200, 206)
    }
}

# The uv tools install from PyPI, so existence is a PyPI lookup (200 = project
# exists, 404 = renamed/delisted/mistyped).
Describe "uv tool ids resolve on PyPI" -Tag 'Live' {
    BeforeDiscovery {
        $env:LOAD_LIB = "1"
        . "$PSScriptRoot\..\src\load-win.ps1"
        $env:LOAD_LIB = $null
        $script:uvTools = @($CORE_UV)
    }

    It "<_> exists on PyPI" -ForEach $uvTools {
        try {
            $resp = Invoke-WebRequest -Uri "https://pypi.org/pypi/$_/json" -Method Head -MaximumRedirection 5 -UseBasicParsing -TimeoutSec 30
        }
        catch {
            $resp = Invoke-WebRequest -Uri "https://pypi.org/pypi/$_/json" -MaximumRedirection 5 -UseBasicParsing -TimeoutSec 30
        }
        [int]$resp.StatusCode | Should -Be 200 -Because "'$_' did not resolve on PyPI (renamed, delisted, or mistyped?)"
    }
}

# Remove-SelfTemp only ever deletes a copy of the script under $env:TEMP. The blank-TEMP
# guard matters because StartsWith("") is true for every path - a blank TEMP must NOT be
# allowed to match and delete an arbitrary script location.
Describe "Remove-SelfTemp temp-dir guard" {
    BeforeAll {
        $env:LOAD_LIB = "1"
        . "$PSScriptRoot\..\src\load-win.ps1"
        $env:LOAD_LIB = $null
    }

    # The script is deleted only when it sits under a non-empty TEMP. The blank-TEMP row
    # guards the StartsWith("") footgun (every path "starts with" the empty string).
    It "<Name>" -ForEach @(
        @{ Name = 'deletes a copy under TEMP'; UnderTemp = $true; BlankTemp = $false; ShouldDelete = $true }
        @{ Name = 'leaves a copy outside TEMP untouched'; UnderTemp = $false; BlankTemp = $false; ShouldDelete = $false }
        @{ Name = 'deletes nothing when TEMP is blank'; UnderTemp = $false; BlankTemp = $true; ShouldDelete = $false }
    ) {
        $temp = Join-Path $TestDrive "temp"
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        $self = if ($UnderTemp) { Join-Path $temp "load-win.ps1" } else { Join-Path $TestDrive "elsewhere.ps1" }
        Set-Content $self "x"

        Remove-SelfTemp -path $self -temp $(if ($BlankTemp) { "" } else { $temp })

        Test-Path $self | Should -Be (-not $ShouldDelete)
    }
}

# Show-Checklist derives each default app's friendly name from its WingetId via the
# package lists and $PKG_ALIAS, so a rename/typo there shows a raw id (or nothing).
# Membership is computed at discovery so each id gets its own named test.
Describe "Default-app / package-list consistency" {
    BeforeDiscovery {
        $env:LOAD_LIB = "1"
        . "$PSScriptRoot\..\src\load-win.ps1"
        $env:LOAD_LIB = $null
        $allPkgs = @($CORE_PKGS + $FULL_PKGS)
        $script:defaultAppIds = @($DEFAULT_APPS | ForEach-Object {
                @{ Id = $_.WingetId; InList = ($allPkgs -contains $_.WingetId) } })
        $script:aliasIds = @($allPkgs | ForEach-Object {
                @{ Id = $_; HasAlias = $PKG_ALIAS.ContainsKey($_) } })
    }

    It "default app <Id> is listed in CORE_PKGS/FULL_PKGS" -ForEach $defaultAppIds {
        $InList | Should -BeTrue -Because "$Id is a default-app target but missing from the install lists"
    }

    It "package <Id> has a friendly alias in PKG_ALIAS" -ForEach $aliasIds {
        $HasAlias | Should -BeTrue -Because "$Id has no entry in PKG_ALIAS, so it shows as a raw id"
    }
}

# The script is meant to survive Constrained Language Mode (WDAC/AppLocker): the .NET-
# backed steps (Add-Type/P-Invoke, the file-association tamper-hash, the Premiere prefs
# byte write) are gated on $CLM and degrade to "skipped" instead of crashing. These
# guard that contract so a future edit can't quietly reintroduce an unguarded .NET call.
Describe "Constrained Language Mode resilience" {
    BeforeAll {
        $script:srcPath = (Resolve-Path "$PSScriptRoot/../src/load-win.ps1").Path
    }

    # Add-Type is the gateway to every P/Invoke in the script and is unconditionally
    # blocked under CLM, so each call must live inside an `if (-not $CLM) { ... }` block.
    # Walks the AST (not the text) so reformatting can't fool it.
    It 'every Add-Type call is gated behind "if (-not $CLM)"' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($srcPath, [ref]$null, [ref]$null)
        $addTypes = $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Add-Type' }, $true)
        $addTypes | Should -Not -BeNullOrEmpty -Because 'the guard is meaningless if it finds no Add-Type calls to check'

        $unguarded = foreach ($c in $addTypes) {
            $guarded = $false
            $p = $c.Parent
            while ($p) {
                if ($p -is [System.Management.Automation.Language.IfStatementAst]) {
                    foreach ($clause in $p.Clauses) {
                        if ($clause.Item1.Extent.Text -match '-not\s+\$CLM') { $guarded = $true }
                    }
                }
                $p = $p.Parent
            }
            if (-not $guarded) { "line $($c.Extent.StartLineNumber)" }
        }
        @($unguarded) | Should -BeNullOrEmpty -Because (
            "Add-Type runs only outside CLM - wrap it in 'if (-not `$CLM)'. Unguarded at: $($unguarded -join ', ')")
    }

    # Sourcing the script as a library must not execute any CLM-blocked .NET at module
    # scope (the $CLM probe itself, the top-level statements). Cross-platform.
    It "loads as a library under Constrained Language Mode" {
        $cmd = "`$ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'; `$env:LOAD_LIB='1'; . '$srcPath'"
        & pwsh -NoProfile -Command $cmd *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'a CLM-blocked call at module scope would terminate the load'
    }

    # End-to-end smoke: a --dry-run (preview + full checklist) must complete under CLM
    # without a language-mode violation. Windows-only - the checklist reads HKCU/HKLM,
    # which don't exist on other platforms.
    It "a --dry-run completes under Constrained Language Mode" -Skip:(-not $IsWindows) {
        $errFile = Join-Path $TestDrive "clm-dryrun.err"
        $cmd = "`$ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'; & '$srcPath' --dry-run"
        & pwsh -NoProfile -Command $cmd 1> $null 2> $errFile
        $stderr = Get-Content $errFile -Raw
        if (-not $stderr) { $stderr = "" }
        $LASTEXITCODE | Should -Be 0 -Because "the dry-run threw under CLM: $stderr"
        $stderr | Should -Not -Match 'ConstrainedLanguage' -Because "a CLM violation surfaced: $stderr"
    }
}

# Fast mode (--fast) must never trigger UAC: it applies only per-user config (HKCU
# writes, file drops into the user's profile, a non-elevated AHK launch). The script's
# single elevation point is `Start-Process ... -Verb RunAs` in Invoke-ElevatedInstall,
# reached only via Invoke-SlowPass (the $FULL pass). These walk the AST (not the text,
# and no sourcing - the installer functions live below the $env:LOAD_LIB boundary) to
# prove a fast run can't reach it, so a refactor can't quietly add an elevated step to
# the fast path or sneak in a second RunAs.
Describe "fast mode requests no elevation (no UAC)" {
    BeforeAll {
        $srcPath = (Resolve-Path "$PSScriptRoot/../src/load-win.ps1").Path
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($srcPath, [ref]$null, [ref]$null)

        # name -> FunctionDefinitionAst, for the call-graph walk
        $script:funcs = @{}
        $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object { $script:funcs[$_.Name] = $_ }

        # A command is an elevation point when it passes `-Verb RunAs`.
        function Test-IsRunAsVerb($cmd) {
            $els = $cmd.CommandElements
            for ($i = 0; $i -lt $els.Count - 1; $i++) {
                if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $els[$i].ParameterName -eq 'Verb' -and
                    $els[$i + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $els[$i + 1].Value -eq 'RunAs') { return $true }
            }
            return $false
        }

        # The enclosing function name for an AST node (walks up to the FunctionDefinitionAst).
        function Get-EnclosingFunc($node) {
            $p = $node.Parent
            while ($p) {
                if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $p.Name }
                $p = $p.Parent
            }
            return $null
        }

        # Every -Verb RunAs call in the script, tagged with the function it sits in.
        $script:runAsCmds = $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            Where-Object { Test-IsRunAsVerb $_ }
        $script:runAsFuncs = @($script:runAsCmds | ForEach-Object { Get-EnclosingFunc $_ } | Sort-Object -Unique)

        # Functions transitively reachable from Invoke-FastPass (including itself),
        # restricted to functions the script defines.
        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $stack = New-Object 'System.Collections.Generic.Stack[string]'
        [void]$seen.Add('Invoke-FastPass'); $stack.Push('Invoke-FastPass')
        while ($stack.Count) {
            $name = $stack.Pop()
            if (-not $script:funcs.ContainsKey($name)) { continue }
            foreach ($c in $script:funcs[$name].Body.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $callee = $c.GetCommandName()
                if ($callee -and $script:funcs.ContainsKey($callee) -and $seen.Add($callee)) { $stack.Push($callee) }
            }
        }
        $script:fastReach = $seen

        # Any function in the fast call graph that itself requests elevation.
        $script:fastRunAsFuncs = @($script:runAsFuncs | Where-Object { $script:fastReach.Contains($_) })
    }

    It "has exactly one elevation point in the whole script" {
        @($runAsCmds).Count | Should -Be 1 -Because (
            "the no-UAC-in-fast-mode contract assumes a single, locatable RunAs; found in: $($runAsFuncs -join ', ')")
    }

    It "the only elevation lives in Invoke-ElevatedInstall" {
        $runAsFuncs | Should -Be 'Invoke-ElevatedInstall' -Because (
            "elevation must stay behind the slow/full pass, not in: $($runAsFuncs -join ', ')")
    }

    It "Invoke-FastPass's call graph never reaches an elevated step" {
        foreach ($elevated in 'Invoke-SlowPass', 'Invoke-ElevatedInstall') {
            $fastReach.Contains($elevated) | Should -BeFalse -Because "a --fast run must not call $elevated"
        }
    }

    It "no command reached by Invoke-FastPass requests elevation" {
        @($fastRunAsFuncs) | Should -BeNullOrEmpty -Because (
            "a fast run must prompt for no admin rights; elevation reachable via: $($fastRunAsFuncs -join ', ')")
    }
}

# The prefs format is Premiere-version-dependent (not platform-dependent), so
# these run against every captured version.
Describe "Set-PremierePro (Premiere <Version>)" -ForEach $PremiereVersions {
    BeforeEach {
        $fixture = "$PSScriptRoot\fixtures\$Dir\Adobe Premiere Pro Prefs_truncated"
        $prefs = Join-Path $TestDrive "prefs"
        Copy-Item $fixture $prefs
    }

    It "shortcut set is activated" {
        Set-PremierePro $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Prefs\.Shortcuts\.Filename>LGG_25\.1_WINDOWS\.kys</FE\.Prefs\.Shortcuts\.Filename>'
    }

    It "workspace is activated, spaces preserved" {
        Set-PremierePro $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Application\.LastWorkspaceName>LGG - Single monitor</FE\.Application\.LastWorkspaceName>'
    }

    It "labels switch to Classic (names + colours + marker)" {
        Set-PremierePro $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.LabelNames\.0>Violet</BE\.Prefs\.LabelNames\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelNames\.15>Yellow</BE\.Prefs\.LabelNames\.15>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.0>14717094</BE\.Prefs\.LabelColors\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.15>6611682</BE\.Prefs\.LabelColors\.15>'
        $content | Should -Match '"name":"Classic"'
        $content | Should -Not -Match 'Vibrant'
    }

    It "auto-save enabled every 5 minutes" {
        Set-PremierePro $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.AutoSave\.DoSave>true</BE\.Prefs\.AutoSave\.DoSave>'
        $content | Should -Match '<BE\.Prefs\.AutoSave\.Interval>5</BE\.Prefs\.AutoSave\.Interval>'
    }

    # One test per active node in the script's $node loop (see $TimelineNodes above).
    It "timeline node <Node> is enabled" -ForEach $TimelineNodes {
        Set-PremierePro $prefs "x.kys" "WS"
        $tag = [regex]::Escape($Node)
        Get-Content $prefs -Raw | Should -Match "<$tag>true</$tag>"
    }

    It "output prefs is valid XML" {
        Set-PremierePro $prefs "x.kys" "WS"
        { [xml](Get-Content $prefs -Raw) } | Should -Not -Throw
    }

    It "no BOM is introduced" {
        Set-PremierePro $prefs "x.kys" "WS"
        $bytes = [System.IO.File]::ReadAllBytes($prefs)
        $bytes[0] | Should -Be 0x3C  # '<' - would be 0xEF/0xFF if a BOM were prepended
    }

    It "idempotent: second run is byte-identical to first" {
        Set-PremierePro $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash1 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        Set-PremierePro $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash2 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        $hash2 | Should -Be $hash1
    }

    It "a renamed node is skipped without corrupting others, with an informative warning" {
        $content = Get-Content $prefs -Raw
        $content = $content -replace 'TL\.PREFLinkedSelectionState', 'TL.PREFLinkedSelectionStateRENAMED'
        Set-Content $prefs $content -Encoding UTF8 -NoNewline
        $output = Set-PremierePro $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor" 6>&1 | Out-String
        $output | Should -Match 'TL\.PREFLinkedSelectionState'
        $output | Should -Match 'fresh install'
        { [xml](Get-Content $prefs -Raw) } | Should -Not -Throw
        Get-Content $prefs -Raw | Should -Match '<BE\.Prefs\.AutoSave\.Interval>5</BE\.Prefs\.AutoSave\.Interval>'
        Get-Content $prefs -Raw | Should -Match '<TL\.PREFLinkedSelectionStateRENAMED>false</TL\.PREFLinkedSelectionStateRENAMED>'
    }
}

Describe "Get-WorkspaceName (Premiere <Version>)" -ForEach $PremiereVersions {
    It "extracts the UserName" {
        $ws = "$PSScriptRoot/fixtures/$Dir/UserWorkspace_truncated.xml"
        Get-WorkspaceName $ws | Should -Be 'LGG - Single monitor'
    }
}

# Set-PrefNode is the engine under Set-PremierePro. Its "no edit = no corruption"
# contract (a missing node must leave the file byte-for-byte untouched) is the
# safety guarantee the rest of the prefs handling relies on.
Describe "Set-PrefNode" {
    BeforeEach {
        $script:prefs = Join-Path $TestDrive "node-prefs"
        # Write without a BOM, matching what Premiere actually authors.
        [System.IO.File]::WriteAllText(
            $prefs, "<root><x>old</x></root>", (New-Object System.Text.UTF8Encoding $false))
    }

    It "replaces a present node's value and reports success" {
        Set-PrefNode $prefs "x" "new" | Should -BeTrue
        Get-Content $prefs -Raw | Should -Match '<x>new</x>'
    }

    It "returns false and leaves the file byte-for-byte untouched when the node is absent" {
        $before = (Get-FileHash $prefs -Algorithm SHA256).Hash
        Set-PrefNode $prefs "missing" "new" | Should -BeFalse
        (Get-FileHash $prefs -Algorithm SHA256).Hash | Should -Be $before
    }
}
