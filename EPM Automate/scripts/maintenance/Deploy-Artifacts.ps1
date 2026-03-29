#Requires -Version 5.1
<#
    Deploy-Artifacts.ps1
    Migrates a snapshot from one environment to another.
    Typical use: promote a DEV snapshot to TEST after sprint sign-off.

    EPM Automate exit codes:
        0  - Snapshot deployed successfully
        1  - Snapshot not found or import failed
        6  - Timeout during export or import
        7  - File access issue during local transfer step
        9  - Authentication failed on source or target
        11 - Server error on either environment

    Usage:
        .\Deploy-Artifacts.ps1 -From DEV -To TEST -Name "Sprint_42_Release"
        .\Deploy-Artifacts.ps1 -From TEST -To PROD -Name "Sprint_42_Release" `
            -AlertTo "release-team@company.com"
#>
param(
    [string]$From    = "DEV",
    [string]$To      = "TEST",
    [string]$Name    = $(throw "-Name is required (snapshot name without .zip)"),
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Deploy-Artifacts"

$localArtifacts = "$root\scripts\artifacts"
Write-Log "Deploying '$Name' from $From -> $To" "INFO"

try {
    # Step 1: pull snapshot out of source env
    Write-Log "Step 1/2 - Exporting from $From..." "INFO"
    Import-EnvConfig -Env $From
    Connect-EPM -Env $From
    try {
        $r = Invoke-EPM -Cmd "exportSnapshot" -CmdArgs @($Name)
        if (-not $r.OK) {
            throw "exportSnapshot failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName "ExportSnapshot"
        Get-FileFromEPM -FileName "$Name.zip" -SaveTo $localArtifacts
    } finally {
        Disconnect-EPM
    }

    # Step 2: push into target env
    Write-Log "Step 2/2 - Importing into $To..." "INFO"
    Import-EnvConfig -Env $To
    Connect-EPM -Env $To
    try {
        Send-FileToEPM -FilePath "$localArtifacts\$Name.zip"

        $r = Invoke-EPM -Cmd "importSnapshot" -CmdArgs @($Name)
        if (-not $r.OK) {
            throw "importSnapshot failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName "ImportSnapshot"

        # send notification while still logged in to target
        if ($AlertTo) {
            Invoke-EPM -Cmd "sendMail" -CmdArgs @(
                "`"$AlertTo`"",
                "`"[EPM] Deploy '$Name' to $To completed`"",
                "Body=`"Snapshot '$Name' was successfully deployed from $From to $To at $(Get-Date -Format 'yyyy-MM-dd HH:mm').`""
            ) | Out-Null
        }
    } finally {
        Disconnect-EPM
    }

} catch {
    Write-Log "Deploy-Artifacts failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Deployment of '$Name' to $To complete" "OK"
exit 0
