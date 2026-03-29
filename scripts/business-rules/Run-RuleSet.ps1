#Requires -Version 5.1
<#
    Run-RuleSet.ps1
    Runs a ruleset (ordered collection of business rules) in EPM Cloud.

    EPM Automate exit codes:
        0  - Ruleset ran successfully
        1  - Ruleset not found or one of the rules failed
        7  - Invalid prompts or parameter format
        9  - Authentication failed
        11 - Server error

    Usage:
        .\Run-RuleSet.ps1 -Env DEV -RuleSet "Month_End_Close"
        .\Run-RuleSet.ps1 -Env PROD -RuleSet "Month_End_Close" `
            -Prompts "Scenario=Actual Period=Jan-2026" -AlertTo "finance@company.com"
#>
param(
    [string]$Env     = "DEV",
    [string]$RuleSet = $(throw "-RuleSet is required"),
    [string]$Prompts = "",
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Run-RuleSet"

Write-Log "Running ruleset '$RuleSet' on $Env" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Run-RuleSet ($RuleSet)" -AlertTo $AlertTo -Work {
        $cmdArgs = @($RuleSet)
        if ($Prompts) { $cmdArgs += $Prompts }

        $r = Invoke-EPM -Cmd "runRuleSet" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "runRuleSet failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Run-RuleSet failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Ruleset '$RuleSet' done" "OK"
exit 0
