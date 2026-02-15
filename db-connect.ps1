# ============================================================
# DB Connect - SSM tunnel to private RDS via Bastion
# Usage: .\db-connect.ps1
# Connects DBeaver to localhost:5432 -> RDS (fully private)
# ============================================================

$ErrorActionPreference = "Stop"

# Ensure PATH is up-to-date
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$AWS_REGION = "us-east-1"
$PROJECT_NAME = "macro-terminal"
$LOCAL_PORT = 5432

# ---- Check prerequisites ----
Write-Host "=== Checking prerequisites ===" -ForegroundColor Cyan

# Check AWS CLI
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: AWS CLI not found. Install it first." -ForegroundColor Red
    exit 1
}

# Check Session Manager plugin
try {
    $ssmPlugin = & "session-manager-plugin" 2>&1
} catch {
    $ssmPlugin = $null
}
if (-not $ssmPlugin -or $ssmPlugin -match "not recognized") {
    Write-Host "ERROR: AWS Session Manager plugin not installed." -ForegroundColor Red
    Write-Host "Install from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" -ForegroundColor Yellow
    exit 1
}
Write-Host "Prerequisites OK" -ForegroundColor Green

# ---- Get Bastion Instance ID ----
Write-Host "`n=== Getting Bastion instance ===" -ForegroundColor Cyan
$INSTANCE_ID = terraform output -raw bastion_instance_id 2>$null
if (-not $INSTANCE_ID) {
    Write-Host "ERROR: Could not get bastion instance ID from Terraform outputs." -ForegroundColor Red
    Write-Host "Run 'terraform apply' first." -ForegroundColor Yellow
    exit 1
}
Write-Host "Bastion: $INSTANCE_ID" -ForegroundColor Yellow

# ---- Start Bastion if stopped ----
$STATE = aws ec2 describe-instances `
    --instance-ids $INSTANCE_ID `
    --query "Reservations[0].Instances[0].State.Name" `
    --output text `
    --region $AWS_REGION

if ($STATE -ne "running") {
    Write-Host "Bastion is '$STATE' - starting it..." -ForegroundColor Yellow
    aws ec2 start-instances --instance-ids $INSTANCE_ID --region $AWS_REGION | Out-Null

    Write-Host "Waiting for instance to be running..." -ForegroundColor Yellow
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $AWS_REGION

    Write-Host "Waiting for SSM agent to register (this may take up to 60s)..." -ForegroundColor Yellow
    $maxRetries = 12
    $retry = 0
    $ssmReady = $false
    while ($retry -lt $maxRetries) {
        $retry++
        Start-Sleep -Seconds 5
        $ssmStatus = aws ssm describe-instance-information `
            --filters "Key=InstanceIds,Values=$INSTANCE_ID" `
            --query "InstanceInformationList[0].PingStatus" `
            --output text `
            --region $AWS_REGION 2>$null
        if ($ssmStatus -eq "Online") {
            $ssmReady = $true
            break
        }
        Write-Host "  Waiting... ($retry/$maxRetries)" -ForegroundColor Gray
    }
    if (-not $ssmReady) {
        Write-Host "ERROR: SSM agent did not come online. Try again in a minute." -ForegroundColor Red
        exit 1
    }
    Write-Host "Bastion is ready!" -ForegroundColor Green
} else {
    Write-Host "Bastion is already running." -ForegroundColor Green
}

# ---- Get RDS endpoint ----
$RDS_ENDPOINT = aws rds describe-db-instances `
    --db-instance-identifier "${PROJECT_NAME}-db" `
    --query "DBInstances[0].Endpoint.Address" `
    --output text `
    --region $AWS_REGION

Write-Host "`n=== Starting SSM port forwarding tunnel ===" -ForegroundColor Cyan
Write-Host "Tunnel: localhost:$LOCAL_PORT --> $RDS_ENDPOINT`:5432" -ForegroundColor Yellow

# ---- Start tunnel in background ----
$tunnelProcess = Start-Process -FilePath "aws" -ArgumentList @(
    "ssm", "start-session",
    "--target", $INSTANCE_ID,
    "--document-name", "AWS-StartPortForwardingSessionToRemoteHost",
    "--parameters", "host=$RDS_ENDPOINT,portNumber=5432,localPortNumber=$LOCAL_PORT",
    "--region", $AWS_REGION
) -PassThru -NoNewWindow

# Give it a moment to establish
Start-Sleep -Seconds 3

if ($tunnelProcess.HasExited) {
    Write-Host "ERROR: Tunnel failed to start. Check that the Session Manager plugin is installed." -ForegroundColor Red
    exit 1
}

# Save PID for disconnect script
$tunnelProcess.Id | Out-File -FilePath ".\.db-tunnel-pid" -Encoding ASCII

Write-Host "`n=== TUNNEL IS ACTIVE ===" -ForegroundColor Green
Write-Host ""
Write-Host "--- DBeaver Connection Details ---" -ForegroundColor Cyan
Write-Host "Host:     localhost"
Write-Host "Port:     $LOCAL_PORT"
Write-Host "Database: macro_terminal"
Write-Host "Username: macro_admin"
Write-Host "Password: (from terraform.tfvars)"
Write-Host "----------------------------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "Tunnel PID: $($tunnelProcess.Id)" -ForegroundColor Gray
Write-Host 'When done, run: .\db-disconnect.ps1' -ForegroundColor Yellow
