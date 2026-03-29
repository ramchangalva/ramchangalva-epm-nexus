#Requires -Version 5.1
<#
    Export-Data.ps1
    Downloads a file from the EPM Cloud outbox to a local folder.
    The file must already exist in the outbox (run an export job first if needed).

    EPM Automate exit codes:
        0  - File downloaded successfully
        1  - File not found in outbox
        6  - Service unavailable or timed out
        7  - File path or access issue
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Export-Data.ps1 -Env DEV -FileName "TrialBalance_Jan2026.csv"
        .\Export-Data.ps1 -Env PROD -FileName "TrialBalance_Jan2026.csv" `
            -SaveTo "C:\Reports\output" -AlertTo "reporting@company.com"
#>
param(
    [string]$Env      = "DEV",
    [string]$FileName = $(throw "-FileName is required"),
    [string]$SaveTo   = "$PSScriptRoot\..\..\data\output",
    [string]$AlertTo  = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Export-Data"

Write-Log "Downloading '$FileName' from $Env to $SaveTo" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Export-Data ($FileName)" -AlertTo $AlertTo -Work {
        Get-FileFromEPM -FileName $FileName -SaveTo $SaveTo
    }
} catch {
    Write-Log "Export-Data failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Export done: $SaveTo\$FileName" "OK"
exit 0
