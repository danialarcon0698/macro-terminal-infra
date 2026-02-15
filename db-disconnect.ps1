# ============================================================
# DB Disconnect - Kills SSM tunnel and stops Bastion
# Usage: .\db-disconnect.ps1
# ============================================================

$ErrorActionPreference = "Stop"

# Ensure PATH is up-to-date
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

$AWS_REGION = "us-east-1"

# ---- Kill the tunnel process ----
Write-Host "=== Closing SSM tunnel ===" -ForegroundColor Cyan

$pidFile = ".\.db-tunnel-pid"
if (Test-Path $pidFile) {
    $tunnelPid = Get-Content $pidFile
    try {
        $proc = Get-Process -Id $tunnelPid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $tunnelPid -Force
            Write-Host "Tunnel process ($tunnelPid) terminated." -ForegroundColor Green
        } else {
            Write-Host "Tunnel process was already closed." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Tunnel process was already closed." -ForegroundColor Yellow
    }
    Remove-Item $pidFile -Force
} else {
    Write-Host "No active tunnel found (no PID file)." -ForegroundColor Yellow
}

# ---- Stop the Bastion ----
Write-Host "`n=== Stopping Bastion ===" -ForegroundColor Cyan

$INSTANCE_ID = terraform output -raw bastion_instance_id 2>$null
if ($INSTANCE_ID) {
    $STATE = aws ec2 describe-instances `
        --instance-ids $INSTANCE_ID `
        --query "Reservations[0].Instances[0].State.Name" `
        --output text `
        --region $AWS_REGION

    if ($STATE -eq "running") {
        aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $AWS_REGION | Out-Null
        Write-Host "Bastion is stopping (saves cost when not in use)." -ForegroundColor Green
    } else {
        Write-Host "Bastion is already '$STATE'." -ForegroundColor Yellow
    }
} else {
    Write-Host "Could not get bastion instance ID." -ForegroundColor Yellow
}

Write-Host "`nDisconnected! RDS is fully private again." -ForegroundColor Green
