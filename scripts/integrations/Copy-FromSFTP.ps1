#Requires -Version 5.1
<#
    Copy-FromSFTP.ps1
    Pulls a file from an SFTP server into the EPM Cloud environment (inbox/outbox).
    Useful for automating data file delivery from source systems.

    SFTP server must be running on port 22 - EPM Automate doesn't support other ports.
    For snapshot files, omit the .zip extension in -SftpPath (EPM handles it automatically).

    EPM Automate exit codes:
        0  - File copied successfully
        1  - File not found on SFTP or insufficient access
        6  - SFTP server unreachable or timed out
        7  - Invalid SFTP path, credentials format, or connection issue
        9  - Authentication failed on EPM side
        11 - Server error

    Usage:
        .\Copy-FromSFTP.ps1 -Env DEV -SftpPath "sftp://sftp.company.com/exports/actuals_jan26.csv" `
            -EpmFileName "actuals_jan26.csv" -SftpUser "sftpuser" -SftpPassword "P@ssw0rd"
#>
param(
    [string]$Env         = "DEV",
    [string]$SftpPath    = $(throw "-SftpPath is required (full SFTP URL, e.g. sftp://host/path/file.csv)"),
    [string]$EpmFileName = $(throw "-EpmFileName is required (target name in EPM inbox)"),
    [string]$SftpUser    = "",     # leave blank if SFTP uses key-based auth configured server-side
    [string]$SftpPassword= "",
    [string]$AlertTo     = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Copy-FromSFTP"

Write-Log "Copying from SFTP: $SftpPath -> EPM:$EpmFileName on $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Copy-FromSFTP '$EpmFileName'" -AlertTo $AlertTo -Work {
        $cmdArgs = @($SftpPath, $EpmFileName)
        if ($SftpUser)     { $cmdArgs += "username=$SftpUser" }
        if ($SftpPassword) { $cmdArgs += "password=$SftpPassword" }

        $r = Invoke-EPM -Cmd "copyFromSftp" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "copyFromSftp failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Copy-FromSFTP failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "$EpmFileName is now in the EPM inbox on $Env" "OK"
exit 0
