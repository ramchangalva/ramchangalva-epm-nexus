# Shared helpers: file transfers, job polling, period labels, SMTP fallback alerts.
# Import this alongside EPMAutomate-Core.psm1.
#
# Note: for scripts that already have an active EPM session, prefer passing -AlertTo
# to Invoke-SafeEPMRun (uses EPM's built-in sendMail). Send-SmtpAlert here is the
# fallback for orchestration scripts that don't hold a session (e.g. MonthEndClose).

Import-Module "$PSScriptRoot\EPMAutomate-Logging.psm1" -Force

function Send-FileToEPM {
    param(
        [string]$FilePath,
        [string]$RemoteDest = ""
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $cmdArgs = @($FilePath)
    if ($RemoteDest) { $cmdArgs += $RemoteDest }

    $r = Invoke-EPM -Cmd "uploadFile" -CmdArgs $cmdArgs
    if (-not $r.OK) { throw "Upload failed (exit $($r.ExitCode)): $($r.Output)" }

    Write-Log "Uploaded: $(Split-Path $FilePath -Leaf)" "OK"
}

function Get-FileFromEPM {
    param(
        [string]$FileName,
        [string]$SaveTo = ".\data\output"
    )

    if (-not (Test-Path $SaveTo)) {
        New-Item -ItemType Directory -Path $SaveTo -Force | Out-Null
    }

    $r = Invoke-EPM -Cmd "downloadFile" -CmdArgs @($FileName)
    if (-not $r.OK) { throw "Download failed (exit $($r.ExitCode)): $($r.Output)" }

    # epmautomate drops the file in the working directory - move it to the right place
    if (Test-Path ".\$FileName") {
        Move-Item ".\$FileName" $SaveTo -Force
    }

    Write-Log "Downloaded $FileName -> $SaveTo" "OK"
}

function Remove-EPMFile {
    param([string]$FileName)

    $r = Invoke-EPM -Cmd "deleteFile" -CmdArgs @($FileName)
    if (-not $r.OK) { throw "Delete failed (exit $($r.ExitCode)): $($r.Output)" }

    Write-Log "Deleted remote file: $FileName" "DEBUG"
}

function Wait-ForJob {
    # Polls until the job shows Completed or Error in its status output.
    # EPM Automate's getJobStatus writes to stdout, not just exit code.
    param(
        [string]$JobName,
        [int]$PollSecs    = 30,
        [int]$TimeoutMins = 120
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMins)
    Write-Log "Waiting on '$JobName' (max ${TimeoutMins}m, poll every ${PollSecs}s)..." "INFO"

    while ((Get-Date) -lt $deadline) {
        $r = Invoke-EPM -Cmd "getJobStatus" -CmdArgs @($JobName)

        if ($r.Output -match "Completed") {
            Write-Log "Job '$JobName' finished OK" "OK"
            return
        }
        if ($r.Output -match "Error|Failed") {
            throw "Job '$JobName' reported failure:`n$($r.Output)"
        }

        Start-Sleep -Seconds $PollSecs
    }

    throw "Job '$JobName' still running after $TimeoutMins minutes - giving up"
}

function Get-CurrentPeriod {
    $d = Get-Date
    return "$($d.ToString('MMM'))-$($d.Year)"
}

function Get-PriorPeriod {
    $d = (Get-Date).AddMonths(-1)
    return "$($d.ToString('MMM'))-$($d.Year)"
}

function Send-SmtpAlert {
    # SMTP fallback for scripts that don't hold an EPM session when they need to notify.
    # Scripts with an active session should use -AlertTo on Invoke-SafeEPMRun instead.
    param(
        [string]$Subject,
        [string]$Body,
        [string[]]$To,
        [string]$Smtp,
        [string]$From = "epm-automate@yourcompany.com"
    )

    if (-not $Smtp -or -not $To) {
        Write-Log "SMTP alert skipped (not configured)" "DEBUG"
        return
    }

    try {
        Send-MailMessage -From $From -To $To -Subject $Subject `
                         -Body $Body -SmtpServer $Smtp -ErrorAction Stop
        Write-Log "SMTP alert sent: $Subject" "INFO"
    } catch {
        Write-Log "SMTP alert failed (non-critical): $_" "WARN"
    }
}

Export-ModuleMember -Function Send-FileToEPM, Get-FileFromEPM, Remove-EPMFile,
                               Wait-ForJob, Get-CurrentPeriod, Get-PriorPeriod, Send-SmtpAlert
