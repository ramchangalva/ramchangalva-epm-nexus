#Requires -Version 5.1
<#
    Run-Report.ps1
    Runs a Financial Reporting document and downloads the output file.

    EPM Automate exit codes:
        0  - Report generated and downloaded
        1  - Report not found or POV member is invalid
        6  - Timed out
        7  - Invalid format or parameter
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Run-Report.ps1 -Env DEV -Report "Income_Statement" -POV "Scenario=Actual;Period=Jan-2026"
        .\Run-Report.ps1 -Env PROD -Report "Balance_Sheet" -Format XLSX `
            -POV "Scenario=Actual;Period=Jan-2026" -AlertTo "cfo@company.com"
#>
param(
    [string]$Env     = "DEV",
    [string]$Report  = $(throw "-Report is required"),
    [string]$Format  = "PDF",    # PDF | HTML | XLS | XLSX
    [string]$POV     = "",       # semicolon-separated key=value, e.g. "Scenario=Actual;Period=Jan-2026"
    [string]$SaveTo  = "$PSScriptRoot\..\..\data\output",
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Run-Report"

Write-Log "Running report '$Report' as $Format | POV: $POV | env: $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Run-Report ($Report)" -AlertTo $AlertTo -Work {
        $cmdArgs = @($Report, $Format)
        if ($POV) { $cmdArgs += $POV }

        $r = Invoke-EPM -Cmd "runReport" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "runReport failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        $outFile = "$Report.$($Format.ToLower())"
        Get-FileFromEPM -FileName $outFile -SaveTo $SaveTo
    }
} catch {
    Write-Log "Run-Report failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Report saved to $SaveTo" "OK"
exit 0
