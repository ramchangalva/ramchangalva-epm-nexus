# Logging helpers used across all EPM scripts
# Using a daily rolling file per script name - easier to grep than per-run timestamps
# Dot-source or import this before calling Write-Log

$script:LogFile = $null

function Start-Log {
    param(
        [string]$Name,
        [string]$Dir = "$PSScriptRoot\..\logs"
    )

    if (-not (Test-Path $Dir)) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }

    $date = Get-Date -Format "yyyyMMdd"
    $script:LogFile = Join-Path $Dir "${Name}_${date}.log"

    Write-Log "--- Session started $(Get-Date -Format 'HH:mm:ss') ---" "INFO"
}

function Write-Log {
    param(
        [string]$Msg,
        [string]$Level = "INFO"
    )

    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "[$ts][$Level] $Msg"

    $color = switch ($Level) {
        "ERROR"   { "Red"    }
        "WARN"    { "Yellow" }
        "OK"      { "Green"  }
        "DEBUG"   { "Gray"   }
        default   { "Cyan"   }
    }

    Write-Host $line -ForegroundColor $color

    if ($script:LogFile) {
        # append full timestamp to file, short one to console
        Add-Content -Path $script:LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Msg"
    }
}

function Remove-OldLogs {
    param(
        [int]$KeepDays = 30,
        [string]$Dir   = "$PSScriptRoot\..\logs"
    )

    if (-not (Test-Path $Dir)) { return }

    $cutoff = (Get-Date).AddDays(-$KeepDays)
    $files  = Get-ChildItem $Dir -Filter "*.log" | Where-Object { $_.LastWriteTime -lt $cutoff }

    foreach ($f in $files) {
        Remove-Item $f.FullName -Force
        Write-Log "Deleted old log: $($f.Name)" "DEBUG"
    }
}

Export-ModuleMember -Function Start-Log, Write-Log, Remove-OldLogs
