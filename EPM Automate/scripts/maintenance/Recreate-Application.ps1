#Requires -Version 5.1
<#
    Recreate-Application.ps1
    Refreshes the application database (cube rebuild).
    Needed after metadata changes - clears all data so only run when expected.

    EPM Automate exit codes:
        0  - Application recreated
        1  - App not found or insufficient privileges
        9  - Authentication failed
        11 - Server error or another operation already in progress

    Usage:
        .\Recreate-Application.ps1 -Env DEV -App "Vision"
        .\Recreate-Application.ps1 -Env TEST -App "Vision" -AlertTo "admin@company.com"
#>
param(
    [string]$Env     = "DEV",
    [string]$App     = $(throw "-App is required (application name)"),
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Recreate-Application"

Write-Log "Recreating '$App' on $Env - this clears all data" "WARN"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Recreate-Application ($App)" -AlertTo $AlertTo -Work {
        $r = Invoke-EPM -Cmd "recreate" -CmdArgs @($App)
        if (-not $r.OK) {
            throw "recreate failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Recreate-Application failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Application '$App' recreated" "OK"
exit 0
