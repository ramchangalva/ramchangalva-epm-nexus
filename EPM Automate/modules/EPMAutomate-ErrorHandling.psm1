# Retry logic and a safe-run wrapper so we don't repeat try/finally everywhere.
# Invoke-SafeEPMRun also handles email notifications via EPM's sendMail command
# so you don't need to wire that up separately in each script.

Import-Module "$PSScriptRoot\EPMAutomate-Logging.psm1" -Force

function Invoke-WithRetry {
    param(
        [scriptblock]$Action,
        [int]$Attempts  = 3,
        [int]$WaitSecs  = 15,
        [string]$OpName = "operation"
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Write-Log "$OpName - attempt $i of $Attempts" "INFO"
            & $Action
            return
        } catch {
            if ($i -eq $Attempts) {
                Write-Log "$OpName failed after $Attempts attempts" "ERROR"
                throw
            }
            Write-Log "$OpName failed (attempt $i): $_ - retrying in ${WaitSecs}s..." "WARN"
            Start-Sleep -Seconds $WaitSecs
        }
    }
}

function Invoke-SafeEPMRun {
    # Guarantees Disconnect-EPM runs even if something blows up mid-script.
    # Pass -AlertTo to get a success/failure email via EPM's sendMail command.
    param(
        [scriptblock]$Work,
        [string]$Env      = "DEV",
        [string]$JobName  = "",      # used in the email subject line
        [string]$AlertTo  = ""       # email address(es), semicolon-separated
    )

    $jobLabel = if ($JobName) { $JobName } else { "EPM Job" }
    $success  = $false
    $errMsg   = ""

    try {
        Connect-EPM -Env $Env
        & $Work
        $success = $true
    } catch {
        $errMsg = "$_"
        Write-Log "Script failed: $errMsg" "ERROR"
        # don't re-throw yet - try to send alert first
    } finally {
        # send mail before logging out so we're still authenticated
        if ($AlertTo) {
            $subject = if ($success) { "[EPM] $jobLabel completed OK" } `
                                     else { "[EPM] $jobLabel FAILED" }
            $body    = if ($success) { "$jobLabel finished successfully on $Env at $(Get-Date -Format 'yyyy-MM-dd HH:mm')." } `
                                     else { "$jobLabel failed on $Env at $(Get-Date -Format 'yyyy-MM-dd HH:mm').`n`nError: $errMsg" }

            # sendMail syntax: epmautomate sendMail "to" "subject" Body="body"
            $r = Invoke-EPM -Cmd "sendMail" -CmdArgs @("`"$AlertTo`"", "`"$subject`"", "Body=`"$body`"")
            if ($r.OK) {
                Write-Log "Alert sent to $AlertTo" "DEBUG"
            } else {
                Write-Log "Alert email failed (non-critical): $($r.Output)" "WARN"
            }
        }

        Disconnect-EPM
    }

    # re-throw after cleanup so the script exits with an error
    if (-not $success) {
        throw $errMsg
    }
}

Export-ModuleMember -Function Invoke-WithRetry, Invoke-SafeEPMRun
