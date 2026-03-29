#Requires -Version 5.1
<#
    Run-Integration.ps1
    Triggers a Data Management integration process in EPM Cloud.

    Import modes : REPLACE | APPEND
    Export modes : STORE_DATA | ADD_DATA | SUBTRACT_DATA | REPLACE_DATA

    EPM Automate exit codes:
        0  - Integration ran successfully
        1  - Integration not found, or data load errors (check DM job log)
        6  - Timed out waiting for integration to finish
        7  - Invalid period format or parameter issue
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Run-Integration.ps1 -Env DEV -Integration "GL_Actuals" -From "Jan-2026" -To "Jan-2026"
        .\Run-Integration.ps1 -Env PROD -Integration "GL_Actuals" -From "Jan-2026" -To "Mar-2026" `
            -ImportMode APPEND -AlertTo "finance@company.com"
#>
param(
    [string]$Env         = "DEV",
    [string]$Integration = $(throw "-Integration is required"),
    [string]$From        = $(throw "-From period is required (e.g. Jan-2026)"),
    [string]$To          = $(throw "-To period is required"),
    [string]$ImportMode  = "REPLACE",
    [string]$ExportMode  = "STORE_DATA",
    [string]$AlertTo     = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Run-Integration"

Write-Log "Running '$Integration' | $From-$To | $ImportMode/$ExportMode on $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Run-Integration ($Integration $From)" -AlertTo $AlertTo -Work {
        $r = Invoke-EPM -Cmd "runIntegration" `
            -CmdArgs @($Integration, $From, $To, $ImportMode, $ExportMode)
        if (-not $r.OK) {
            throw "runIntegration failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName $Integration
    }
} catch {
    Write-Log "Run-Integration failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Integration '$Integration' done" "OK"
exit 0
