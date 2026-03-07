# ============================================================
# Pause Macro Terminal — API, data-provider, and RDS (save cost)
# Usage: .\pause-service.ps1
# Resume with: .\resume-service.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$AWS_REGION = "us-east-1"
$PROJECT_NAME = "macro-terminal"
$CLUSTER = "${PROJECT_NAME}-cluster"
$API_SERVICE = "${PROJECT_NAME}-api"
$SCHEDULE_RULE = "${PROJECT_NAME}-data-provider-schedule"
$DB_ID = "${PROJECT_NAME}-db"

Write-Host "`n=== Pausing Macro Terminal ===" -ForegroundColor Cyan
Write-Host ""

# 1. Scale API ECS service to 0
Write-Host "Scaling API service to 0..." -ForegroundColor Yellow
aws ecs update-service --cluster $CLUSTER --service $API_SERVICE --desired-count 0 --region $AWS_REGION | Out-Null
Write-Host "  API (Fargate) paused." -ForegroundColor Green

# 2. Disable data-provider schedule (no scheduled runs)
Write-Host "Disabling data-provider schedule..." -ForegroundColor Yellow
aws events disable-rule --name $SCHEDULE_RULE --region $AWS_REGION
Write-Host "  Data-provider schedule disabled." -ForegroundColor Green

# 3. Stop RDS instance (saves instance cost; storage still bills)
Write-Host "Stopping RDS instance..." -ForegroundColor Yellow
$rdsResult = aws rds stop-db-instance --db-instance-identifier $DB_ID --region $AWS_REGION 2>&1
if ($LASTEXITCODE -ne 0) {
    if ($rdsResult -match "is not in available state") {
        Write-Host "  RDS already stopped or stopping." -ForegroundColor Gray
    } else {
        Write-Host $rdsResult -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  RDS stop initiated (available in a few min)." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. API down, data-provider off, RDS stopping." -ForegroundColor Cyan
Write-Host "VPC, Route 53, etc. still bill. To resume: .\resume-service.ps1" -ForegroundColor Gray
Write-Host ""
