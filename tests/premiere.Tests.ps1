# Tests for Apply-PremierePrefs and Get-WorkspaceName in src/load-win.ps1.
# The script is sourced with $env:LOAD_LIB so only its functions load (no installer).
#
# Run:  Invoke-Pester tests\premiere.Tests.ps1

BeforeAll {
    $env:LOAD_LIB = "1"
    . "$PSScriptRoot\..\src\load-win.ps1"
    $env:LOAD_LIB = $null
}

Describe "Apply-PremierePrefs (Premiere 25.0)" {
    BeforeEach {
        $fixture = "$PSScriptRoot\fixtures\premiere_pro_v25.0\Adobe Premiere Pro Prefs_truncated"
        $prefs   = Join-Path $TestDrive "prefs"
        Copy-Item $fixture $prefs
    }

    It "shortcut set is activated" {
        Apply-PremierePrefs $prefs "Luis_Mengo_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Prefs\.Shortcuts\.Filename>Luis_Mengo_25\.1_WINDOWS\.kys</FE\.Prefs\.Shortcuts\.Filename>'
    }

    It "workspace is activated, spaces preserved" {
        Apply-PremierePrefs $prefs "Luis_Mengo_25.1_WINDOWS.kys" "LGG - Single monitor"
        Get-Content $prefs -Raw | Should -Match '<FE\.Application\.LastWorkspaceName>LGG - Single monitor</FE\.Application\.LastWorkspaceName>'
    }

    It "labels switch to Classic (names + colours + marker)" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.LabelNames\.0>Violet</BE\.Prefs\.LabelNames\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelNames\.15>Yellow</BE\.Prefs\.LabelNames\.15>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.0>14717094</BE\.Prefs\.LabelColors\.0>'
        $content | Should -Match '<BE\.Prefs\.LabelColors\.15>6611682</BE\.Prefs\.LabelColors\.15>'
        $content | Should -Match '"name":"Classic"'
        $content | Should -Not -Match 'Vibrant'
    }

    It "auto-save enabled every 5 minutes" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<BE\.Prefs\.AutoSave\.DoSave>true</BE\.Prefs\.AutoSave\.DoSave>'
        $content | Should -Match '<BE\.Prefs\.AutoSave\.Interval>5</BE\.Prefs\.AutoSave\.Interval>'
    }

    It "timeline Link Selection is enabled" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        Get-Content $prefs -Raw | Should -Match '<TL\.PREFLinkedSelectionState>true</TL\.PREFLinkedSelectionState>'
    }

    It "all 8 timeline display settings are enabled" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        $content = Get-Content $prefs -Raw
        $content | Should -Match '<be\.Prefs\.Timeline\.Show\.Video\.Thumbnails>true</be\.Prefs\.Timeline\.Show\.Video\.Thumbnails>'
        $content | Should -Match '<be\.Prefs\.Timeline\.Show\.Video\.Names>true</be\.Prefs\.Timeline\.Show\.Video\.Names>'
        $content | Should -Match '<be\.Prefs\.Timeline\.Show\.Audio\.Waveforms>true</be\.Prefs\.Timeline\.Show\.Audio\.Waveforms>'
        $content | Should -Match '<be\.Prefs\.Timeline\.Show\.Audio\.Names>true</be\.Prefs\.Timeline\.Show\.Audio\.Names>'
        $content | Should -Match '<be\.Prefs\.Timeline\.Show\.Proxy\.Badges>true</be\.Prefs\.Timeline\.Show\.Proxy\.Badges>'
        $content | Should -Match '<TL\.PREFShowFXBadges>true</TL\.PREFShowFXBadges>'
        $content | Should -Match '<TL\.PREFShowThroughEditsState>true</TL\.PREFShowThroughEditsState>'
        $content | Should -Match '<MZ\.SQShowDuplicateMarkers>true</MZ\.SQShowDuplicateMarkers>'
    }

    It "output prefs is valid XML" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        { [xml](Get-Content $prefs -Raw) } | Should -Not -Throw
    }

    It "no BOM is introduced" {
        Apply-PremierePrefs $prefs "x.kys" "WS"
        $bytes = [System.IO.File]::ReadAllBytes($prefs)
        $bytes[0] | Should -Be 0x3C  # '<' — would be 0xEF/0xFF if a BOM were prepended
    }

    It "idempotent: second run is byte-identical to first" {
        Apply-PremierePrefs $prefs "Luis_Mengo_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash1 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        Apply-PremierePrefs $prefs "Luis_Mengo_25.1_WINDOWS.kys" "LGG - Single monitor"
        $hash2 = (Get-FileHash $prefs -Algorithm SHA256).Hash
        $hash2 | Should -Be $hash1
    }

    It "a renamed node is skipped without corrupting others, with an informative warning" {
        $content = Get-Content $prefs -Raw
        $content = $content -replace 'TL\.PREFLinkedSelectionState', 'TL.PREFLinkedSelectionStateRENAMED'
        Set-Content $prefs $content -Encoding UTF8 -NoNewline
        $output = Apply-PremierePrefs $prefs "Luis_Mengo_25.1_WINDOWS.kys" "LGG - Single monitor" 6>&1 | Out-String
        $output | Should -Match 'TL\.PREFLinkedSelectionState'
        $output | Should -Match 'fresh install'
        { [xml](Get-Content $prefs -Raw) } | Should -Not -Throw
        Get-Content $prefs -Raw | Should -Match '<BE\.Prefs\.AutoSave\.Interval>5</BE\.Prefs\.AutoSave\.Interval>'
        Get-Content $prefs -Raw | Should -Match '<TL\.PREFLinkedSelectionStateRENAMED>false</TL\.PREFLinkedSelectionStateRENAMED>'
    }
}

Describe "Get-WorkspaceName" {
    It "extracts the UserName" {
        $ws = "$PSScriptRoot\fixtures\premiere_pro_v25.0\UserWorkspace_truncated.xml"
        Get-WorkspaceName $ws | Should -Be 'LGG - Single monitor'
    }
}
