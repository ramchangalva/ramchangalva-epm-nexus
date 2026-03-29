#Requires -Version 5.1
<#
    Encrypt-Password.ps1
    Creates an encrypted .epw password file needed by all other EPM scripts.
    Run this once per environment when setting up or when a password changes.
    Does NOT require login - runs entirely locally.

    EPM Automate exit codes:
        0  - Success
        7  - Client error (bad params, file path issue, or epmautomate not found)

    Usage:
        .\Encrypt-Password.ps1 -Password "MyP@ssw0rd" -Key "mySecretKey" -OutFile "config\passwords\dev.epw"

    The same key must be used consistently for all .epw files in this project.
    Store the key somewhere safe - you'll need it if you ever re-encrypt.
#>
param(
    [string]$Password = $(throw "-Password is required"),
    [string]$Key      = $(throw "-Key is required (private encryption key)"),
    [string]$OutFile  = $(throw "-OutFile is required (e.g. config\passwords\dev.epw)"),
    [string]$ProxyPwd = ""    # only needed if your network uses an authenticated proxy
)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\..\.."

Import-Module "$root\modules\EPMAutomate-Logging.psm1" -Force
Import-Module "$root\modules\EPMAutomate-Core.psm1"    -Force

Start-Log -Name "Encrypt-Password"

# make sure the output folder exists
$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Initialize-EPM

Write-Log "Encrypting password to: $OutFile" "INFO"

$cmdArgs = @($Password, $Key, $OutFile)
if ($ProxyPwd) { $cmdArgs += "ProxyServerPassword=$ProxyPwd" }

$r = Invoke-EPM -Cmd "encrypt" -CmdArgs $cmdArgs

if (-not $r.OK) {
    Write-Log "Encryption failed (exit $($r.ExitCode) - $(Get-ExitMsg $r.ExitCode))" "ERROR"
    exit $r.ExitCode
}

Write-Log "Password file created: $OutFile" "OK"
Write-Log "Keep your key safe - you'll need it again if the password changes" "INFO"
exit 0
