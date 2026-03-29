#Requires -Version 5.1
<#
    Import-Users.ps1
    Bulk-import users and role assignments from a CSV file.
    CSV format must match the EPM Cloud user import template (see docs/user-import-template.csv).

    EPM Automate exit codes:
        0  - Users imported successfully
        1  - Some users failed (check the job details in the UI for row-level errors)
        7  - CSV file not found or upload failed
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Import-Users.ps1 -Env DEV -CsvFile ".\data\input\users_q2.csv"
        .\Import-Users.ps1 -Env PROD -CsvFile ".\data\input\users_q2.csv" `
            -AlertTo "security-admin@company.com"
#>
param(
    [string]$Env     = "DEV",
    [string]$CsvFile = $(throw "-CsvFile is required"),
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Import-Users"

Write-Log "Importing users from '$CsvFile' to $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Import-Users" -AlertTo $AlertTo -Work {
        Send-FileToEPM -FilePath $CsvFile

        $fileName = Split-Path $CsvFile -Leaf
        $r = Invoke-EPM -Cmd "importUsers" -CmdArgs @($fileName)
        if (-not $r.OK) {
            throw "importUsers failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        # clean up the uploaded file from the server
        Remove-EPMFile -FileName $fileName
    }
} catch {
    Write-Log "Import-Users failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "User import complete" "OK"
exit 0
