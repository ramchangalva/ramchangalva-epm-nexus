#Requires -Version 5.1
<#
    Run-Calculation.ps1
    Runs a single business rule with optional runtime prompt values.

    EPM Automate exit codes:
        0  - Rule ran successfully
        1  - Rule not found or calc errors (check Essbase logs)
        7  - Invalid prompts or parameter format
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Run-Calculation.ps1 -Env DEV -Rule "Allocate_Costs"
        .\Run-Calculation.ps1 -Env PROD -Rule "Allocate_Costs" -Prompts "Scenario=Actual Year=FY26" `
            -AlertTo "finance@company.com"
#>
param(
    [string]$Env     = "DEV",
    [string]$Rule    = $(throw "-Rule is required"),
    [string]$Prompts = "",    # runtime prompts as space-separated key=value pairs
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Run-Calculation"

Write-Log "Running rule '$Rule' | prompts: $Prompts | env: $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Run-Calculation ($Rule)" -AlertTo $AlertTo -Work {
        $cmdArgs = @($Rule)
        if ($Prompts) { $cmdArgs += $Prompts }

        $r = Invoke-EPM -Cmd "runBusinessRule" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "runBusinessRule failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Run-Calculation failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Rule '$Rule' completed" "OK"
exit 0
