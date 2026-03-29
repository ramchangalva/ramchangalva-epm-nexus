#Requires -Version 5.1
<#
    Copy-SnapshotFromInstance.ps1
    Copies a snapshot directly from one EPM Cloud instance to another without
    downloading it locally first. Much faster than download + re-upload for large snapshots.

    After this runs, call Deploy-Artifacts.ps1 (importSnapshot step only) or
    run importSnapshot manually to apply the snapshot in the target environment.

    EPM Automate exit codes:
        0  - Snapshot copied successfully
        1  - Snapshot not found or insufficient privileges
        6  - Source environment unreachable or timed out
        7  - Invalid parameters or password file issue
        9  - Authentication failed on source or target
        11 - Server error on either side

    Usage:
        .\Copy-SnapshotFromInstance.ps1 -Env TEST -SnapshotName "Sprint_42_Release" `
            -SourceUrl "https://tenant-dev.pbcs.us1.oraclecloud.com" `
            -SourceUser "admin@company.com" -SourcePwdFile "config\passwords\dev.epw"
#>
param(
    [string]$Env            = "TEST",
    [string]$SnapshotName   = $(throw "-SnapshotName is required"),
    [string]$SourceUrl      = $(throw "-SourceUrl is required (source EPM environment URL)"),
    [string]$SourceUser     = $(throw "-SourceUser is required (service admin on source env)"),
    [string]$SourcePwdFile  = $(throw "-SourcePwdFile is required (.epw file for source env)"),
    [string]$AlertTo        = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Copy-SnapshotFromInstance"

if (-not (Test-Path $SourcePwdFile)) {
    Write-Log "Source password file not found: $SourcePwdFile" "ERROR"
    exit 7
}

Write-Log "Copying '$SnapshotName' from $SourceUrl into $Env" "INFO"
Write-Log "This can take several minutes for large snapshots..." "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Copy-Snapshot '$SnapshotName'" -AlertTo $AlertTo -Work {
        # Note: source credentials are passed directly - the target env handles the pull
        $r = Invoke-EPM -Cmd "copySnapshotFromInstance" `
            -CmdArgs @("`"$SnapshotName`"", $SourceUser, $SourcePwdFile, $SourceUrl)

        if (-not $r.OK) {
            throw "copySnapshotFromInstance failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName "CopySnapshotFromInstance"
        Write-Log "Snapshot '$SnapshotName' is now available in $Env - run importSnapshot to apply it" "OK"
    }
} catch {
    Write-Log "Copy-SnapshotFromInstance failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

exit 0
