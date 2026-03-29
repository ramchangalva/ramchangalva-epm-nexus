#Requires -Version 5.1
<#
    Reset-Service.ps1
    Resets (restarts) the EPM Cloud service. Use this when users report slow performance
    or the service is stuck. Can take up to 15 minutes to complete.

    Make sure no batch jobs or business rules are running before triggering this -
    they'll get killed mid-run if you don't check first.

    EPM Automate exit codes:
        0  - Reset initiated successfully
        1  - Command failed (e.g. another reset already in progress)
        9  - Authentication failed
        11 - Server error or reset already in progress

    Usage:
        .\Reset-Service.ps1 -Env PROD -Comment "Users reporting slow cube calcs since 2pm"
        .\Reset-Service.ps1 -Env PROD -Comment "Post-deploy restart" -AutoTune -AlertTo "admin@company.com"
#>
param(
    [string]$Env      = "DEV",
    [string]$Comment  = $(throw "-Comment is required (describe why you're resetting)"),
    [switch]$AutoTune,            # tunes Essbase BSO caches after restart - good idea for PROD
    [switch]$Force,               # skip the confirmation prompt
    [string]$AlertTo  = ""        # email notification on completion
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Reset-Service"

Write-Log "Resetting service on $Env - Reason: $Comment" "WARN"
if ($AutoTune) { Write-Log "AutoTune is enabled - BSO caches will be optimised after restart" "INFO" }

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Reset-Service ($Env)" -AlertTo $AlertTo -Work {
        $cmdArgs = @("`"$Comment`"")
        if ($AutoTune) { $cmdArgs += "AutoTune=true" }
        if ($Force)    { $cmdArgs += "-f" }

        $r = Invoke-EPM -Cmd "resetService" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "resetService failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        # resetService is async - service comes back within ~15 min
        Write-Log "Reset initiated. Service will be unavailable for up to 15 minutes." "WARN"
    }
} catch {
    Write-Log "Reset-Service failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Reset-Service completed" "OK"
exit 0
