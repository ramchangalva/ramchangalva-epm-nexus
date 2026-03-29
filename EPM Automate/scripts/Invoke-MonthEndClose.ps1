#Requires -Version 5.1
<#
    Invoke-MonthEndClose.ps1
    Full month-end close sequence for EPM Cloud.

    Steps:
        1. Load actuals via Data Management
        2. Run cost allocation rule
        3. Run consolidation ruleset
        4. Generate income statement (PDF)
        5. Take a post-close backup

    EPM Automate exit codes:
        0  - All steps completed successfully
        Non-zero - The step that failed will set the exit code; check logs for detail

    Usage:
        .\Invoke-MonthEndClose.ps1 -Env PROD -File ".\data\input\actuals_jan26.csv"
        .\Invoke-MonthEndClose.ps1 -Env DEV  -File ".\data\input\actuals_jan26.csv" `
            -Period "Jan-2026" -AlertTo "finance-team@company.com"

    Notes:
        - Runs against prior period by default (most common scheduling scenario)
        - PROD runs should be kicked off manually after sign-off, not scheduled blindly
#>
param(
    [string]$Env     = "DEV",
    [string]$File    = $(throw "-File is required (path to actuals data file)"),
    [string]$Period  = "",     # defaults to prior period if not specified
    [string]$AlertTo = ""
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-Utilities.psm1"     -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "MonthEndClose"

if (-not $Period) { $Period = Get-PriorPeriod }

$start = Get-Date
Write-Log "=== Month-End Close | $Env | $Period ===" "INFO"

try {
    # 1. Load actuals
    Write-Log "[1/5] Loading actuals..." "INFO"
    & "$root\scripts\data-management\Load-Data.ps1" `
        -Env $Env -Location "GL_Actuals" -File $File -Period $Period
    if ($LASTEXITCODE -ne 0) { throw "Load-Data failed with exit $LASTEXITCODE" }

    # 2. Allocations
    Write-Log "[2/5] Running cost allocations..." "INFO"
    & "$root\scripts\business-rules\Run-Calculation.ps1" `
        -Env $Env -Rule "Allocate_Costs" -Prompts "Scenario=Actual Period=$Period"
    if ($LASTEXITCODE -ne 0) { throw "Run-Calculation failed with exit $LASTEXITCODE" }

    # 3. Consolidation
    Write-Log "[3/5] Running consolidation ruleset..." "INFO"
    & "$root\scripts\business-rules\Run-RuleSet.ps1" `
        -Env $Env -RuleSet "Consolidation" -Prompts "Scenario=Actual Period=$Period"
    if ($LASTEXITCODE -ne 0) { throw "Run-RuleSet failed with exit $LASTEXITCODE" }

    # 4. Report
    Write-Log "[4/5] Generating Income Statement..." "INFO"
    & "$root\scripts\reporting\Run-Report.ps1" `
        -Env $Env -Report "Income_Statement" -Format "PDF" `
        -POV "Scenario=Actual;Period=$Period"
    if ($LASTEXITCODE -ne 0) { throw "Run-Report failed with exit $LASTEXITCODE" }

    # 5. Backup
    Write-Log "[5/5] Post-close snapshot..." "INFO"
    $snapName = "MonthEnd_$($Period -replace '-','')_PostClose"
    & "$root\scripts\maintenance\Backup-Environment.ps1" `
        -Env $Env -Name $snapName -Download
    if ($LASTEXITCODE -ne 0) { throw "Backup-Environment failed with exit $LASTEXITCODE" }

    $mins = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    Write-Log "=== Month-End Close complete in ${mins}m ===" "OK"

    # send summary email after everything's done
    if ($AlertTo) {
        & "$root\scripts\maintenance\Send-EPMMail.ps1" -Env $Env `
            -To $AlertTo `
            -Subject "[EPM] Month-End Close $Period completed" `
            -Body "All 5 steps completed successfully on $Env in ${mins} minutes."
    }

} catch {
    Write-Log "Month-End Close FAILED at: $_" "ERROR"

    if ($AlertTo) {
        & "$root\scripts\maintenance\Send-EPMMail.ps1" -Env $Env `
            -To $AlertTo `
            -Subject "[EPM] Month-End Close $Period FAILED" `
            -Body "Month-End Close failed on $Env.`n`nError: $_`n`nCheck the log for details."
    }

    exit 1
}

exit 0
