#Requires -Version 5.1
<#
    Load-Data.ps1
    Uploads a data file to EPM Cloud and triggers a Data Management load rule.

    EPM Automate exit codes:
        0  - Load completed successfully
        1  - Rule not found, or load errors (check job details in DM)
        6  - Service unavailable or timed out
        7  - File not found locally, or upload issue
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Load-Data.ps1 -Env DEV -Location "GL_Actuals" -File ".\data\input\actuals_jan26.csv"
        .\Load-Data.ps1 -Env PROD -Location "GL_Actuals" -File ".\data\input\actuals_jan26.csv" `
            -Period "Jan-2026" -AlertTo "finance-team@company.com"
#>
param(
    [string]$Env      = "DEV",
    [string]$Location = $(throw "-Location is required (Data Management location name)"),
    [string]$File     = $(throw "-File is required (path to the data file)"),
    [string]$Period   = "",      # defaults to current period if not supplied
    [string]$AlertTo  = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Load-Data"

if (-not $Period) { $Period = Get-CurrentPeriod }

Write-Log "Data load starting | Env=$Env | Location=$Location | Period=$Period | File=$File" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Load-Data ($Location $Period)" -AlertTo $AlertTo -Work {
        Send-FileToEPM -FilePath $File

        $fileName = Split-Path $File -Leaf
        # arg order: location, startPeriod, endPeriod, importMode, fileName
        $r = Invoke-EPM -Cmd "runDataRule" -CmdArgs @($Location, $Period, $Period, "REPLACE_EXPORT", $fileName)
        if (-not $r.OK) {
            throw "runDataRule failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName $Location
        Remove-EPMFile -FileName $fileName
    }
} catch {
    Write-Log "Load-Data failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Load completed successfully" "OK"
exit 0
