#Requires -Version 5.1
<#
    Set-SubstVars.ps1
    Sets substitution variables on a specific cube or at the application level.
    Typically run at the start of each period to update CurYear, CurPeriod, etc.

    Use "ALL" for -Cube to set application-level variables (visible across all cubes).
    Use the cube name (e.g. "Plan1", "OEP_FS") for cube-specific variables.

    EPM Automate exit codes:
        0  - Variables set successfully
        1  - Invalid variable name or cube not found
        7  - Invalid parameters (e.g. trying to set multiple values for one variable)
        9  - Authentication failed
        11 - Server error

    Usage:
        # Set application-level period vars (most common use case)
        .\Set-SubstVars.ps1 -Env PROD -Cube ALL -Vars "CurYear=FY26 CurPeriod=Jan"

        # Set cube-specific var
        .\Set-SubstVars.ps1 -Env PROD -Cube "Plan1" -Vars "CurForecast=FY26"

        # Multiple vars at once
        .\Set-SubstVars.ps1 -Env PROD -Cube ALL -Vars "CurYear=FY26 CurPeriod=Feb PriorPeriod=Jan"
#>
param(
    [string]$Env      = "DEV",
    [string]$Cube     = "ALL",   # cube name or ALL for app-level
    [string]$Vars     = $(throw "-Vars is required (space-separated VAR=VALUE pairs, e.g. 'CurYear=FY26 CurPeriod=Jan')"),
    [string]$AlertTo  = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Set-SubstVars"

Write-Log "Setting substitution variables | Cube=$Cube | Vars=$Vars | Env=$Env" "INFO"

# split Vars string into individual VAR=VALUE tokens
$varTokens = $Vars -split '\s+' | Where-Object { $_ -match '=' }

if ($varTokens.Count -eq 0) {
    Write-Log "No valid VAR=VALUE pairs found in: $Vars" "ERROR"
    exit 7
}

try {
    Invoke-SafeEPMRun -Env $Env -JobName "Set-SubstVars ($Cube)" -AlertTo $AlertTo -Work {
        # setsubstvars takes: CUBE_NAME|ALL VAR=VALUE [VAR=VALUE ...]
        $cmdArgs = @($Cube) + $varTokens

        $r = Invoke-EPM -Cmd "setsubstvars" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "setsubstvars failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }

        Write-Log "Set $($varTokens.Count) variable(s) on $Cube" "OK"
    }
} catch {
    Write-Log "Set-SubstVars failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

exit 0
