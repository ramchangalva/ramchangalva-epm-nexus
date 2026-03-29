#Requires -Version 5.1
<#
    Clear-Data.ps1
    Clears data from a cube for a given scenario/version/period range.
    Double-check the params before running this in PROD - there's no undo.

    EPM Automate exit codes:
        0  - Data cleared
        1  - Invalid scenario/version, or insufficient privileges
        7  - Invalid period format or parameter issue
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Clear-Data.ps1 -Env DEV -Scenario Actual -Version "Working" -From "Jan-2026" -To "Mar-2026"
        .\Clear-Data.ps1 -Env PROD -Scenario Actual -Version "Working" -From "Jan-2026" -To "Jan-2026" `
            -AlertTo "admin@company.com"
#>
param(
    [string]$Env      = "DEV",
    [string]$Scenario = $(throw "-Scenario is required"),
    [string]$Version  = $(throw "-Version is required"),
    [string]$From     = $(throw "-From period is required (e.g. Jan-2026)"),
    [string]$To       = $(throw "-To period is required (e.g. Mar-2026)"),
    [string]$AlertTo  = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Clear-Data"

Write-Log "Clearing data: $Scenario / $Version / $From - $To in $Env" "WARN"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Clear-Data ($Scenario $From-$To)" -AlertTo $AlertTo -Work {
        $r = Invoke-EPM -Cmd "clearCube" -CmdArgs @($Scenario, $Version, $From, $To)
        if (-not $r.OK) {
            throw "clearCube failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Clear-Data failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Data cleared" "OK"
exit 0
