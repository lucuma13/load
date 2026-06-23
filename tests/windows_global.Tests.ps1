# Whole-script checks for src/load-win.ps1 that aren't tied to Premiere prefs:
#   - PowerShell 5.1 syntax compatibility (no 7+-only syntax ships)
#   - file encoding (pure ASCII, no BOM) so legacy PowerShell doesn't garble it
#   - liveness of the external resources the installer pulls (plugins, winget, PyPI)
#
# Run:  Invoke-Pester tests\windows_global.Tests.ps1

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
        $violations = Invoke-ScriptAnalyzer -Path "$PSScriptRoot/../src/load-win.ps1" -Settings $settings -IncludeRule PSUseCompatibleSyntax
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

# These hit the network to confirm the hard-coded plugin installer URLs are still live. Exclude them
# on an offline run with:  Invoke-Pester -ExcludeTag Live

# Confirms every pinned winget id still resolves on the winget source
Describe "winget package ids resolve" -Tag 'Live' {
    BeforeDiscovery {
        $env:LOAD_LIB = "1"
        . "$PSScriptRoot\..\src\load-win.ps1"
        $env:LOAD_LIB = $null
        $wingetIds = @($CORE_PKGS + $FULL_PKGS)
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
        $uvTools = @($CORE_UV)
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
