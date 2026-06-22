# PSScriptAnalyzer config for load-win.ps1
# Runs the full default rule set MINUS the rules below, which are false positives
# for a standalone interactive installer script.
@{
    ExcludeRules = @(
        # The script's UX *is* console output - the [done]/[skipped]/[would run]
        # checklist. Write-Output would land in the pipeline and corrupt the return
        # values of the functions that emit it, so Write-Host is correct here.
        'PSAvoidUsingWriteHost'

        # Wants -WhatIf/-Confirm plumbing on Set-*/Remove-* functions. The script
        # already has its own --dry-run path; this is module-cmdlet advice that
        # doesn't apply to an internal script.
        'PSUseShouldProcessForStateChangingFunctions'

        # Prefs/Apps/Macros are deliberately plural (Set-PremiereProPrefs sets many
        # prefs, Install-AhkMacros installs many macros). Singularising would mislead.
        'PSUseSingularNouns'

        # The two empty catches are intentional best-effort registry operations
        # (unlock-or-ignore); failure is an acceptable no-op.
        'PSAvoidUsingEmptyCatchBlock'
    )
}
