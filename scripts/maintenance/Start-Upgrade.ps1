#Requires -Version 5.1
<#
    Start-Upgrade.ps1
    Upgrades the local EPM Automate client to the latest version available
    from the connected environment.

    Run this after a new EPM Cloud release if you notice version mismatch warnings
    during login. Safe to run anytime - it's a no-op if already on latest version.

    EPM Automate exit codes:
        0  - Already up to date or upgrade completed
        6  - Service unreachable during upgrade
        7  - Client-side issue (file permissions, disk space)
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Start-Upgrade.ps1 -Env DEV
        .\Start-Upgrade.ps1 -Env PROD -AlertTo "admin@company.com"

    Note: After upgrade the epmautomate.bat path in settings.json stays the same.
          The binary is updated in-place.
#>
param(
    [string]$Env     = "DEV",
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Start-Upgrade"

Write-Log "Checking for EPM Automate updates on $Env..." "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "EPM Automate Upgrade" -AlertTo $AlertTo -Work {
        $r = Invoke-EPM -Cmd "upgrade"
        if (-not $r.OK) {
            throw "upgrade failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        # output tells you if it upgraded or was already current
        if ($r.Output -match "up.to.date|no upgrade|latest") {
            Write-Log "EPM Automate is already on the latest version" "INFO"
        } else {
            Write-Log "Upgrade complete: $($r.Output)" "OK"
        }
    }
} catch {
    Write-Log "Start-Upgrade failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

exit 0
