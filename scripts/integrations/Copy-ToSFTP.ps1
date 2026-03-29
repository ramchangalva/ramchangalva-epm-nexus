#Requires -Version 5.1
<#
    Copy-ToSFTP.ps1
    Pushes a file from the EPM Cloud outbox to an SFTP server.
    Typically used to deliver report outputs or data exports to downstream systems.

    SFTP server must be running on port 22.
    For snapshot files, omit the .zip extension in both -EpmFileName and the SFTP path.

    EPM Automate exit codes:
        0  - File pushed successfully
        1  - File not found in EPM outbox or insufficient access
        6  - SFTP server unreachable or timed out
        7  - Invalid parameters or SFTP path format
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Copy-ToSFTP.ps1 -Env PROD -EpmFileName "IncomeStatement_Jan2026.pdf" `
            -SftpPath "sftp://sftp.company.com/reports/IncomeStatement_Jan2026.pdf" `
            -SftpUser "sftpuser" -SftpPassword "P@ssw0rd"
#>
param(
    [string]$Env          = "DEV",
    [string]$EpmFileName  = $(throw "-EpmFileName is required (file in EPM outbox/inbox)"),
    [string]$SftpPath     = $(throw "-SftpPath is required (full SFTP destination URL)"),
    [string]$SftpUser     = "",
    [string]$SftpPassword = "",
    [string]$AlertTo      = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Copy-ToSFTP"

Write-Log "Copying EPM:$EpmFileName -> SFTP:$SftpPath on $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Copy-ToSFTP '$EpmFileName'" -AlertTo $AlertTo -Work {
        $cmdArgs = @($SftpPath, $EpmFileName)
        if ($SftpUser)     { $cmdArgs += "username=$SftpUser" }
        if ($SftpPassword) { $cmdArgs += "password=$SftpPassword" }

        $r = Invoke-EPM -Cmd "copyToSftp" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "copyToSftp failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Copy-ToSFTP failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "$EpmFileName delivered to $SftpPath" "OK"
exit 0
