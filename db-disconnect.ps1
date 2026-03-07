# ============================================================
# DB Disconnect - Kills SSM tunnel (Bastion was removed from infra)
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

# ---- Bastion removed from infra (no-op) ----
$INSTANCE_ID = terraform output -raw bastion_instance_id 2>$null
if (-not $INSTANCE_ID) {
    Write-Host "`n(Bastion was removed from infra; nothing to stop.)" -ForegroundColor Gray
}

Write-Host "`nDisconnected." -ForegroundColor Green
