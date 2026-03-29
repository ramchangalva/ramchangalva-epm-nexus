#Requires -Version 5.1
<#
    Send-EPMMail.ps1
    Sends an email via EPM Cloud's built-in mail service.
    Useful for manual notifications or testing your alert setup.

    Note: most scripts call this automatically via -AlertTo param.
    Use this standalone script when you need to send a one-off message
    or attach a file from the EPM outbox.

    EPM Automate exit codes:
        0  - Email sent
        1  - Delivery failed (bad address, or mail not enabled for tenant)
        7  - Invalid parameters
        9  - Authentication failed
        11 - Server error

    Usage:
        # Simple message
        .\Send-EPMMail.ps1 -Env PROD -To "finance-team@company.com" -Subject "Close complete" -Body "Jan close finished OK"

        # With attachment from EPM outbox
        .\Send-EPMMail.ps1 -Env PROD -To "cfo@company.com;controller@company.com" `
            -Subject "Income Statement Jan-2026" -Body "See attached" `
            -Attachments "outbox/Income_Statement_Jan2026.pdf"
#>
param(
    [string]$Env         = "DEV",
    [string]$To          = $(throw "-To is required (semicolon-separated email addresses)"),
    [string]$Subject     = $(throw "-Subject is required"),
    [string]$Body        = "",
    [string]$Attachments = ""    # comma-separated file paths from EPM outbox, e.g. "outbox/file1.csv,outbox/file2.pdf"
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Core.psm1"          -Force
Import-Module "$root\modules\EPMAutomate-ErrorHandling.psm1" -Force

Start-Log -Name "Send-EPMMail"

Write-Log "Sending mail to '$To' | Subject: $Subject" "INFO"

try {
    Invoke-SafeEPMRun -Env $Env -Work {
        # sendMail syntax: epmautomate sendMail "to" "subject" [Body="..."] [Attachments=file1,file2]
        $cmdArgs = @("`"$To`"", "`"$Subject`"")

        if ($Body)        { $cmdArgs += "Body=`"$Body`"" }
        if ($Attachments) { $cmdArgs += "Attachments=$Attachments" }

        $r = Invoke-EPM -Cmd "sendMail" -CmdArgs $cmdArgs
        if (-not $r.OK) {
            throw "sendMail failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode)): $($r.Output)"
        }
    }
} catch {
    Write-Log "Send-EPMMail failed: $_" "ERROR"
    exit (Get-LastEPMExitCode)
}

Write-Log "Email sent to $To" "OK"
exit 0
