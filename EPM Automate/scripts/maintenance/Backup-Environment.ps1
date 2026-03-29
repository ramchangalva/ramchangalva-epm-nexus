#Requires -Version 5.1
<#
    Backup-Environment.ps1
    Exports a named snapshot from EPM Cloud. Use -Download to also pull it locally.
    Schedule this nightly for PROD - snapshot export takes 10-20 min on larger envs.

    EPM Automate exit codes:
        0  - Snapshot exported (and downloaded if -Download was set)
        1  - Export failed - another snapshot job may already be running
        6  - Timed out waiting for export to finish
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Backup-Environment.ps1 -Env PROD
        .\Backup-Environment.ps1 -Env PROD -Name "PreRelease_Sprint42" -Download `
            -AlertTo "admin@company.com"
#>
param(
    [string]$Env      = "DEV",
    [string]$Name     = "",       # defaults to a timestamped name
    [switch]$Download,            # pull the zip locally after export
    [string]$AlertTo  = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Backup-Environment"

if (-not $Name) {
    $Name = "Backup_$(Get-Date -Format 'yyyyMMdd_HHmm')"
}

Write-Log "Creating snapshot '$Name' on $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Backup ($Name)" -AlertTo $AlertTo -Work {
        $r = Invoke-EPM -Cmd "exportSnapshot" -CmdArgs @($Name)
        if (-not $r.OK) {
            throw "exportSnapshot failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Wait-ForJob -JobName "ExportSnapshot"

        if ($Download) {
            $dest = "$root\scripts\artifacts"
            Get-FileFromEPM -FileName "$Name.zip" -SaveTo $dest
            Write-Log "Snapshot saved to $dest\$Name.zip" "OK"
        }
    }
} catch {
    Write-Log "Backup-Environment failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Backup '$Name' complete" "OK"
exit 0
