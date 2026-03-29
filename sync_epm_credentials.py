#!/usr/bin/env python3
"""
sync_epm_credentials.py

Fetches EPM Cloud credentials from the AWS Secrets Manager secret "oracleepm" and:
  1. Updates the environment config JSON (serviceUrl, username, identityDomain)
  2. Runs epmautomate encrypt to create/refresh the .epw password file

Run this from a pipeline or scheduled task whenever credentials rotate.
It replaces the manual steps of editing config files and running Encrypt-Password.ps1.

Expected secret structure in AWS Secrets Manager (secret name: "oracleepm"):
    {
        "tenant_url":       "https://mycompany.pbcs.us1.oraclecloud.com",
        "username":         "epm-admin@mycompany.com",
        "password":         "PlaintextPassword",
        "identity_domain":  "mycompany",
        "encryption_key":   "YourEncryptionKey123"
    }

    "encryption_key" is the private key you chose when first encrypting - must stay consistent.
    "identity_domain" is optional if your tenant URL already includes it.

Usage:
    python sync_epm_credentials.py --env PROD
    python sync_epm_credentials.py --env DEV
    python sync_epm_credentials.py --env TEST --dry-run   # preview without writing files

Requirements:
    pip install boto3
    AWS credentials configured (IAM role, env vars, or ~/.aws/credentials)
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError


SECRET_NAME    = "oracleepm"       # fixed - all EPM Cloud creds live in this one secret
DEFAULT_REGION = "us-east-2"

# paths relative to this script (project root)
PROJECT_ROOT  = Path(__file__).parent
SETTINGS_FILE = PROJECT_ROOT / "config" / "settings.json"
ENVS_DIR      = PROJECT_ROOT / "config" / "environments"
PASSWORDS_DIR = PROJECT_ROOT / "config" / "passwords"


# ---------------------------------------------------------------------------
# AWS
# ---------------------------------------------------------------------------

def get_secret(secret_name, region):
    session = boto3.session.Session()
    client  = session.client(service_name="secretsmanager", region_name=region)

    try:
        response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        code = e.response["Error"]["Code"]
        # give actionable messages instead of raw boto3 noise
        msgs = {
            "ResourceNotFoundException": f"Secret '{secret_name}' not found in {region}",
            "AccessDeniedException":     f"Permission denied reading '{secret_name}' - check IAM role/policy",
            "InvalidRequestException":   f"Invalid request for '{secret_name}' - secret may be scheduled for deletion",
            "DecryptionFailure":         f"KMS decryption failed for '{secret_name}' - check KMS key permissions",
        }
        print(f"[ERROR] {msgs.get(code, str(e))}")
        sys.exit(1)

    raw = response.get("SecretString")
    if not raw:
        print("[ERROR] Secret has no string value - binary secrets are not supported here")
        sys.exit(1)

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        print("[ERROR] Secret value is not valid JSON - expected a JSON object, got:", raw[:80])
        sys.exit(1)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_settings():
    if not SETTINGS_FILE.exists():
        print(f"[ERROR] settings.json not found at {SETTINGS_FILE}")
        print("        Make sure you're running this from the EPMCloud project root")
        sys.exit(1)

    with open(SETTINGS_FILE) as f:
        return json.load(f)


def update_env_config(env, tenant_url, username, identity_domain, dry_run=False):
    cfg_file = ENVS_DIR / f"{env.lower()}.json"

    if not cfg_file.exists():
        print(f"[WARN]  Config file not found: {cfg_file} - skipping env config update")
        return

    with open(cfg_file) as f:
        cfg = json.load(f)

    cfg["serviceUrl"]     = tenant_url
    cfg["username"]       = username
    cfg["identityDomain"] = identity_domain

    if dry_run:
        print(f"[DRY]   Would update {cfg_file.name}:")
        print(f"          serviceUrl     = {tenant_url}")
        print(f"          username       = {username}")
        print(f"          identityDomain = {identity_domain}")
        return

    with open(cfg_file, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")  # trailing newline - avoids noisy git diffs

    print(f"[OK]    Updated {cfg_file.name}")


# ---------------------------------------------------------------------------
# Encrypt
# ---------------------------------------------------------------------------

def run_encrypt(epm_exe, password, enc_key, out_file, dry_run=False):
    if dry_run:
        print(f"[DRY]   Would run: {epm_exe} encrypt *** *** {out_file}")
        return

    PASSWORDS_DIR.mkdir(parents=True, exist_ok=True)

    # don't log the password or key - just show the output path
    print(f"[INFO]  Running epmautomate encrypt -> {out_file}")

    result = subprocess.run(
        [epm_exe, "encrypt", password, enc_key, str(out_file)],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        output = (result.stdout or result.stderr or "").strip()
        print(f"[ERROR] encrypt failed (exit {result.returncode})")
        if output:
            print(f"        {output}")
        # exit 7 = client error (bad params, path issue) per EPM Automate docs
        sys.exit(result.returncode)

    print(f"[OK]    Password file written: {out_file}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args():
    parser = argparse.ArgumentParser(
        description=f"Sync EPM Cloud credentials from AWS Secrets Manager (secret: {SECRET_NAME})",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--env", default="DEV", choices=["DEV", "TEST", "PROD"],
        help="Target environment to update (default: DEV)"
    )
    parser.add_argument(
        "--region", default=DEFAULT_REGION,
        help=f"AWS region where the secret lives (default: {DEFAULT_REGION})"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would change without writing any files or running encrypt"
    )
    return parser.parse_args()


def main():
    args = parse_args()
    env  = args.env.upper()

    print(f"\n[INFO]  Fetching secret '{SECRET_NAME}' from {args.region}...")
    secret = get_secret(SECRET_NAME, args.region)

    # validate required fields up front
    required = ["tenant_url", "username", "password", "encryption_key"]
    missing  = [k for k in required if not secret.get(k)]
    if missing:
        print(f"[ERROR] Secret '{SECRET_NAME}' is missing: {', '.join(missing)}")
        print("        See the script docstring for the expected JSON structure")
        sys.exit(1)

    tenant_url      = secret["tenant_url"].rstrip("/")
    username        = secret["username"]
    password        = secret["password"]
    enc_key         = secret["encryption_key"]
    identity_domain = secret.get("identity_domain", "")

    settings = load_settings()
    epm_exe  = settings.get("epmAutomatePath", "epmautomate")
    pwd_file = PASSWORDS_DIR / f"{env.lower()}.epw"

    if not Path(epm_exe).exists():
        print(f"[ERROR] epmautomate not found at: {epm_exe}")
        print("        Update epmAutomatePath in config/settings.json")
        sys.exit(1)

    print(f"[INFO]  Environment : {env}")
    print(f"[INFO]  Tenant      : {tenant_url}")
    print(f"[INFO]  Username    : {username}")
    print(f"[INFO]  Password    : {pwd_file}")
    if args.dry_run:
        print("[INFO]  DRY RUN - no files will be written\n")

    # 1. patch env config with latest values from the secret
    update_env_config(env, tenant_url, username, identity_domain, dry_run=args.dry_run)

    # 2. create/refresh the encrypted password file
    run_encrypt(epm_exe, password, enc_key, pwd_file, dry_run=args.dry_run)

    print(f"\n[OK]    EPM credentials synced for {env}\n")


if __name__ == "__main__":
    main()
