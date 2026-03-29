<#
    Test-EPMModules.ps1
    Quick sanity checks - run this after first setup or after pulling changes
    to make sure configs and modules are all loading correctly before a live run.

    Usage:
        .\tests\Test-EPMModules.ps1
#>

$root  = Split-Path $PSScriptRoot -Parent
$pass  = 0
$fail  = 0

function Check {
    param([string]$Label, [scriptblock]$Test)

    try {
        $ok = & $Test
        if ($ok) {
            Write-Host "  PASS  $Label" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  FAIL  $Label" -ForegroundColor Red
            $script:fail++
        }
    } catch {
        Write-Host "  FAIL  $Label  ($_)" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "`nEPM Module checks`n" -ForegroundColor Cyan

# config files
Check "settings.json exists"  { Test-Path "$root\config\settings.json" }
Check "dev.json exists"        { Test-Path "$root\config\environments\dev.json" }
Check "test.json exists"       { Test-Path "$root\config\environments\test.json" }
Check "prod.json exists"       { Test-Path "$root\config\environments\prod.json" }
Check "settings.json is valid JSON" {
    $null -ne (Get-Content "$root\config\settings.json" -Raw | ConvertFrom-Json)
}
Check "dev.json has serviceUrl field" {
    $cfg = Get-Content "$root\config\environments\dev.json" -Raw | ConvertFrom-Json
    $cfg.serviceUrl -ne ""
}

# module files
foreach ($m in @("EPMAutomate-Core","EPMAutomate-Logging","EPMAutomate-Utilities","EPMAutomate-ErrorHandling")) {
    Check "$m.psm1 exists" { Test-Path "$root\modules\$m.psm1" }
}

# module loads without errors
Check "Logging module imports OK" {
    Import-Module "$root\modules\EPMAutomate-Logging.psm1" -Force
    $true
}
Check "Write-Log function available" {
    $null -ne (Get-Command Write-Log -ErrorAction SilentlyContinue)
}

# helper functions work
Check "Get-CurrentPeriod returns MMM-YYYY format" {
    Import-Module "$root\modules\EPMAutomate-Utilities.psm1" -Force
    (Get-CurrentPeriod) -match '^\w{3}-\d{4}$'
}
Check "Get-PriorPeriod returns MMM-YYYY format" {
    (Get-PriorPeriod) -match '^\w{3}-\d{4}$'
}

# exit code helper
Check "Core module imports OK" {
    Import-Module "$root\modules\EPMAutomate-Core.psm1" -Force
    $true
}
Check "Get-ExitMsg returns correct text for code 0"  { (Get-ExitMsg 0)  -match "Success" }
Check "Get-ExitMsg returns correct text for code 1"  { (Get-ExitMsg 1)  -match "privileges" }
Check "Get-ExitMsg returns correct text for code 6"  { (Get-ExitMsg 6)  -match "timeout" }
Check "Get-ExitMsg returns correct text for code 7"  { (Get-ExitMsg 7)  -match "Client error" }
Check "Get-ExitMsg returns correct text for code 9"  { (Get-ExitMsg 9)  -match "Authentication" }
Check "Get-ExitMsg returns correct text for code 11" { (Get-ExitMsg 11) -match "Server error" }

# all script files exist
$scripts = @(
    "scripts\data-management\Load-Data.ps1",
    "scripts\data-management\Export-Data.ps1",
    "scripts\data-management\Clear-Data.ps1",
    "scripts\business-rules\Run-Calculation.ps1",
    "scripts\business-rules\Run-RuleSet.ps1",
    "scripts\maintenance\Backup-Environment.ps1",
    "scripts\maintenance\Deploy-Artifacts.ps1",
    "scripts\maintenance\Recreate-Application.ps1",
    "scripts\maintenance\Encrypt-Password.ps1",
    "scripts\maintenance\Reset-Service.ps1",
    "scripts\maintenance\Copy-SnapshotFromInstance.ps1",
    "scripts\maintenance\Send-EPMMail.ps1",
    "scripts\maintenance\Set-SubstVars.ps1",
    "scripts\maintenance\Start-Upgrade.ps1",
    "scripts\integrations\Run-Integration.ps1",
    "scripts\integrations\Copy-FromSFTP.ps1",
    "scripts\integrations\Copy-ToSFTP.ps1",
    "scripts\reporting\Run-Report.ps1",
    "scripts\user-management\Import-Users.ps1"
)
foreach ($s in $scripts) {
    Check "$s exists" { Test-Path "$root\$s" }
}

$color = if ($fail -eq 0) { "Green" } else { "Red" }
Write-Host "`n$pass passed, $fail failed`n" -ForegroundColor $color

if ($fail -gt 0) { exit 1 }
exit 0
