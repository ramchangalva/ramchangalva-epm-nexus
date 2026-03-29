# EPM Cloud Automate Scripts

PowerShell automation scripts for Oracle EPM Cloud using the EPM Automate CLI. Built to replace a bunch of manual steps that kept getting missed during month-end close — loading actuals, running allocations, kicking off consolidation, taking a backup. All of that now runs from a single script or gets scheduled.

The AWS Secrets Manager integration (`sync_epm_credentials.py`) came later once we stopped wanting to store passwords in config files.

---

## What you need before starting

- Oracle EPM Automate installed locally — [download from Oracle](https://docs.oracle.com/en/cloud/saas/enterprise-performance-management-common/cepma/epm_automate_overview.html)
- PowerShell 5.1 or later (it's on Windows 10/11 by default, run `$PSVersionTable` to check)
- Python 3.8+ and `boto3` if you're using the AWS credential sync
- An EPM Cloud service admin account for each environment you're automating

---

## Setup

### 1. Point the scripts at your EPM Automate installation

Open `config/settings.json` and set `epmAutomatePath` to wherever `epmautomate.bat` lives on your machine:

```json
{
  "epmAutomatePath": "C:\\Oracle\\EPMAutomate\\bin\\epmautomate.bat"
}
```

### 2. Fill in your environment URLs

Edit the three files under `config/environments/`. Each one has the same fields:

```json
{
  "serviceUrl":     "https://your-tenant.pbcs.us1.oraclecloud.com",
  "identityDomain": "your-domain",
  "username":       "epm-admin@yourcompany.com",
  "passwordFile":   "config/passwords/prod.epw",
  "applicationName": "YourAppName"
}
```

The `serviceUrl` format varies slightly depending on your Oracle data center region (`us1`, `us6`, `eu1`, etc.) — check what's in your browser URL when you log into EPM Cloud.

### 3. Create the encrypted password files

EPM Automate doesn't accept plaintext passwords — it needs a `.epw` file created with its own `encrypt` command. The encryption key is just a string you pick; it doesn't have to be complex but you need to keep it the same forever (or re-encrypt when you change it).

```powershell
.\scripts\maintenance\Encrypt-Password.ps1 `
    -Password "YourEPMPassword" `
    -Key "YourChosenKey" `
    -OutFile "config\passwords\dev.epw"
```

Do this once per environment. The `config/passwords/` folder is gitignored so the `.epw` files won't get committed.

**If you're using AWS Secrets Manager**, skip steps 2 and 3 and run this instead:

```bash
pip install -r requirements.txt
python sync_epm_credentials.py --env PROD
```

That pulls the tenant URL, username, password, and encryption key out of the `oracleepm` secret and does steps 2 and 3 automatically.

### 4. Run the smoke tests

```powershell
.\tests\Test-EPMModules.ps1
```

This just checks that all the config files and modules load correctly. It doesn't connect to EPM Cloud. Takes about 5 seconds and will tell you if something's misconfigured before you try to run anything real.

---

## Folder layout

```
config/
  environments/     dev, test, prod connection settings
  passwords/        .epw files (gitignored - don't commit these)
  settings.json     global settings (epmautomate path, log retention, alert email)

modules/            shared PowerShell modules imported by all scripts
  EPMAutomate-Core.psm1          login/logout, run any epmautomate command
  EPMAutomate-Logging.psm1       write to console + daily rolling log file
  EPMAutomate-Utilities.psm1     file transfers, job polling, period helpers
  EPMAutomate-ErrorHandling.psm1 retry logic, safe-run wrapper, email on failure

scripts/
  data-management/  Load-Data, Export-Data, Clear-Data
  business-rules/   Run-Calculation, Run-RuleSet
  integrations/     Run-Integration, Copy-FromSFTP, Copy-ToSFTP
  maintenance/      Backup, Deploy, Reset-Service, Encrypt-Password, etc.
  reporting/        Run-Report
  user-management/  Import-Users
  Invoke-MonthEndClose.ps1   orchestrates the full close sequence

data/
  input/    drop source files here before uploading (gitignored)
  output/   downloaded exports and reports land here (gitignored)

logs/       one log file per script per day, kept for 30 days
tests/      Test-EPMModules.ps1
```

---

## Common operations

### Load data

```powershell
.\scripts\data-management\Load-Data.ps1 `
    -Env PROD `
    -Location "GL_Actuals" `
    -File ".\data\input\actuals_jan26.csv" `
    -Period "Jan-2026" `
    -AlertTo "finance-team@yourcompany.com"
```

`-AlertTo` sends a success/failure email via EPM Cloud's built-in mail service. Leave it out if you don't want notifications.

### Run a business rule

```powershell
.\scripts\business-rules\Run-Calculation.ps1 `
    -Env PROD `
    -Rule "Allocate_Costs" `
    -Prompts "Scenario=Actual Year=FY26"
```

Runtime prompts are space-separated `KEY=VALUE` pairs matching the rule's prompt names exactly (case-sensitive in some EPM versions).

### Take a backup

```powershell
# Quick backup with auto-generated name
.\scripts\maintenance\Backup-Environment.ps1 -Env PROD -Download

# Named backup
.\scripts\maintenance\Backup-Environment.ps1 -Env PROD -Name "PreRelease_Sprint47" -Download
```

`-Download` pulls the `.zip` locally into `scripts/artifacts/`. Leave it off if you just want the snapshot sitting in EPM Cloud.

### Promote DEV -> TEST

```powershell
.\scripts\maintenance\Deploy-Artifacts.ps1 -From DEV -To TEST -Name "Sprint47_Release"
```

This exports from source, downloads locally, uploads to target, imports. Takes 20-30 minutes for larger snapshots. The `-AlertTo` flag works here too.

### Update substitution variables at period start

```powershell
.\scripts\maintenance\Set-SubstVars.ps1 `
    -Env PROD `
    -Cube ALL `
    -Vars "CurYear=FY26 CurPeriod=Feb PriorPeriod=Jan"
```

Run this at the start of each new period before any calcs or loads.

### Copy a snapshot directly between instances

Faster than download + re-upload for large snapshots:

```powershell
.\scripts\maintenance\Copy-SnapshotFromInstance.ps1 `
    -Env TEST `
    -SnapshotName "Backup_20260328_2200" `
    -SourceUrl "https://tenant-prod.pbcs.us1.oraclecloud.com" `
    -SourceUser "admin@yourcompany.com" `
    -SourcePwdFile "config\passwords\prod.epw"
```

---

## Month-end close

The `Invoke-MonthEndClose.ps1` script runs the full 5-step sequence:

1. Load actuals from Data Management
2. Run cost allocation rule
3. Run consolidation ruleset
4. Generate income statement PDF
5. Take a post-close snapshot

```powershell
.\scripts\Invoke-MonthEndClose.ps1 `
    -Env PROD `
    -File ".\data\input\actuals_feb26.csv" `
    -Period "Feb-2026" `
    -AlertTo "finance-team@yourcompany.com"
```

It defaults to prior period if you leave out `-Period`, which is usually what you want when it's scheduled. Each step calls its own script and checks the exit code — if step 2 fails, steps 3-5 don't run.

The `-AlertTo` email at this level comes from `Send-EPMMail.ps1` rather than the per-script alert, so it gives you one summary email at the end instead of five separate ones.

---

## Email notifications

Set `alertEmail` in `config/settings.json` to get notifications without passing `-AlertTo` to every script individually. Scripts that use `Invoke-SafeEPMRun` (most of them) will pick this up automatically.

Email goes through EPM Cloud's own mail service so there's no SMTP server to configure. It needs a valid EPM session, which means notifications are sent before logout — including failure alerts. The `smtp` block in `settings.json` is there as a fallback for the orchestration scripts that don't hold a session.

If your EPM Cloud tenant has email disabled, the notification will fail silently (logged as WARN, doesn't affect the actual job).

---

## Troubleshooting

**Exit code 9 — authentication failed**
Almost always a stale `.epw` file. Re-run `Encrypt-Password.ps1` (or `sync_epm_credentials.py`) and try again. Also check that `identityDomain` in the env config matches what's in your EPM Cloud URL.

**Exit code 11 — server error**
Could mean the service is being reset by someone else, or an internal Oracle issue. Wait a few minutes and retry. If it keeps happening, check the EPM Cloud activity reports in the UI.

**Exit code 6 — timeout**
The 15-minute socket timeout is EPM Automate's fixed limit. If a snapshot export or integration job is taking longer than that, the command times out but the job usually keeps running in EPM Cloud. You can check job status manually in the UI, or increase the poll interval in `Wait-ForJob`.

**"too many sessions" error on login**
Happens when a previous script crashed without logging out. EPM Cloud allows a limited number of concurrent sessions per user. Either wait a bit for them to expire, or log in through the UI and terminate the orphaned sessions from the user activity page.

**`epmautomate.bat` not found**
Check the path in `config/settings.json`. On some machines Oracle installs to `C:\EPMAutomate\bin\` instead of `C:\Oracle\EPMAutomate\bin\`. Run `where epmautomate` in a command prompt to find it.

**Script runs fine manually but fails when scheduled**
The working directory matters. EPM Automate writes downloaded files to wherever the process is running from. When run as a scheduled task, make sure the start directory is set to the project root, not `System32` or wherever the task scheduler defaults to.

---

## AWS Secrets Manager

The `oracleepm` secret in `us-east-2` should have this structure:

```json
{
    "tenant_url":       "https://your-tenant.pbcs.us1.oraclecloud.com",
    "username":         "epm-admin@yourcompany.com",
    "password":         "PlaintextPassword",
    "identity_domain":  "your-domain",
    "encryption_key":   "YourEncryptionKey"
}
```

The IAM role or user running `sync_epm_credentials.py` needs `secretsmanager:GetSecretValue` on that secret ARN. If you're running it from an EC2 instance or Lambda, attach the policy to the instance role. If running locally, your `~/.aws/credentials` or environment variables need to have the right access.

```bash
# test AWS access before running the sync
aws secretsmanager get-secret-value --secret-id oracleepm --region us-east-2
```

---

## Logs

Each script writes to a daily rolling log in `logs/`. The filename format is `ScriptName_YYYYMMDD.log`. Logs older than 30 days are cleaned up automatically (configurable in `settings.json`).

If something fails and you need the full output, the logs have timestamps and the raw epmautomate output for every command. They're the first place to look before escalating.
