# Tests for Set-PremiereProPrefs and Get-WorkspaceName in src/load-win.ps1.
# The script is sourced with $env:LOAD_LIB so only its functions load (no installer).
#
# Run:  Invoke-Pester tests\windows_premiere_pro.Tests.ps1

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

# The prefs format is Premiere-version-dependent (not platform-dependent), so
# these run against every captured version.
Describe "Set-PremiereProPrefs (Premiere <Version>)" -ForEach $PremiereVersions {
    BeforeEach {
        $fixture = "$PSScriptRoot\fixtures\$Dir\Adobe Premiere Pro Prefs_truncated"
        $prefs   = Join-Path $TestDrive "prefs"
        Copy-Item $fixture $prefs
    }

    It "shortcut set is activated" {
        Set-PremiereProPrefs $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Prefs\.Shortcuts\.Filename>LGG_25\.1_WINDOWS\.kys</FE\.Prefs\.Shortcuts\.Filename>'
    }

    It "workspace is activated, spaces preserved" {
        Set-PremiereProPrefs $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Application\.LastWorkspaceName>LGG - Single monitor</FE\.Application\.LastWorkspaceName>'
    }

    It "labels switch to Classic (names + colours + marker)" {
        Set-PremiereProPrefs $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.LabelNames\.0>Violet</BE\.Prefs\.LabelNames\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelNames\.15>Yellow</BE\.Prefs\.LabelNames\.15>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.0>14717094</BE\.Prefs\.LabelColors\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.15>6611682</BE\.Prefs\.LabelColors\.15>'
        $content | Should -Match '"name":"Classic"'
        $content | Should -Not -Match 'Vibrant'
    }

    It "auto-save enabled every 5 minutes" {
        Set-PremiereProPrefs $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.AutoSave\.DoSave>true</BE\.Prefs\.AutoSave\.DoSave>'
        $content | Should -Match '<BE\.Prefs\.AutoSave\.Interval>5</BE\.Prefs\.AutoSave\.Interval>'
    }

    # One test per active node in the script's $node loop (see $TimelineNodes above).
    It "timeline node <Node> is enabled" -ForEach $TimelineNodes {
        Set-PremiereProPrefs $prefs "x.kys" "WS"
        $tag = [regex]::Escape($Node)
        Get-Content $prefs -Raw | Should -Match "<$tag>true</$tag>"
    }

    It "output prefs is valid XML" {
        Set-PremiereProPrefs $prefs "x.kys" "WS"
        { [xml](Get-Content $prefs -Raw) } | Should -Not -Throw
    }

    It "no BOM is introduced" {
        Set-PremiereProPrefs $prefs "x.kys" "WS"
        $bytes = [System.IO.File]::ReadAllBytes($prefs)
        $bytes[0] | Should -Be 0x3C  # '<' - would be 0xEF/0xFF if a BOM were prepended
    }

    It "idempotent: second run is byte-identical to first" {
        Set-PremiereProPrefs $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash1 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        Set-PremiereProPrefs $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash2 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        $hash2 | Should -Be $hash1
    }

    It "a renamed node is skipped without corrupting others, with an informative warning" {
        $content = Get-Content $prefs -Raw
        $content = $content -replace 'TL\.PREFLinkedSelectionState', 'TL.PREFLinkedSelectionStateRENAMED'
        Set-Content $prefs $content -Encoding UTF8 -NoNewline
        $output = Set-PremiereProPrefs $prefs "LGG_25.1_WINDOWS.kys" "LGG - Single monitor" 6>&1 | Out-String
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
