# ============================================================
# Resume Macro Terminal — RDS, API, and data-provider
# Usage: .\resume-service.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$AWS_REGION = "us-east-1"
$PROJECT_NAME = "macro-terminal"
$CLUSTER = "${PROJECT_NAME}-cluster"
$API_SERVICE = "${PROJECT_NAME}-api"
$SCHEDULE_RULE = "${PROJECT_NAME}-data-provider-schedule"
$DB_ID = "${PROJECT_NAME}-db"

# API desired count (match Terraform default; change if you run with more)
$DesiredCount = 1

Write-Host "`n=== Resuming Macro Terminal ===" -ForegroundColor Cyan
Write-Host ""

# 1. Start RDS (must be up before API connects)
Write-Host "Starting RDS instance..." -ForegroundColor Yellow
$status = (aws rds describe-db-instances --db-instance-identifier $DB_ID --region $AWS_REGION --query "DBInstances[0].DBInstanceStatus" --output text 2>$null)
if ($status -eq "stopped") {
    aws rds start-db-instance --db-instance-identifier $DB_ID --region $AWS_REGION | Out-Null
    Write-Host "  Waiting for RDS to be available (a few minutes)..." -ForegroundColor Gray
    aws rds wait db-instance-available --db-instance-identifier $DB_ID --region $AWS_REGION
    Write-Host "  RDS is available." -ForegroundColor Green
} elseif ($status -eq "available") {
    Write-Host "  RDS already available." -ForegroundColor Green
} elseif ($status -match "starting|modifying") {
    Write-Host "  RDS is starting (waiting for available)..." -ForegroundColor Gray
    aws rds wait db-instance-available --db-instance-identifier $DB_ID --region $AWS_REGION
    Write-Host "  RDS is available." -ForegroundColor Green
} else {
    Write-Host "  RDS status: $status. Starting if needed..." -ForegroundColor Gray
    aws rds start-db-instance --db-instance-identifier $DB_ID --region $AWS_REGION 2>$null | Out-Null
    aws rds wait db-instance-available --db-instance-identifier $DB_ID --region $AWS_REGION
    Write-Host "  RDS is available." -ForegroundColor Green
}

# 2. Scale API ECS service back up
Write-Host "Scaling API service to $DesiredCount..." -ForegroundColor Yellow
aws ecs update-service --cluster $CLUSTER --service $API_SERVICE --desired-count $DesiredCount --region $AWS_REGION | Out-Null
Write-Host "  API (Fargate) resuming." -ForegroundColor Green

# 3. Enable data-provider schedule
Write-Host "Enabling data-provider schedule..." -ForegroundColor Yellow
aws events enable-rule --name $SCHEDULE_RULE --region $AWS_REGION
Write-Host "  Data-provider schedule enabled (runs every 6h)." -ForegroundColor Green

Write-Host ""
Write-Host "Done. API will be back once the new task is running." -ForegroundColor Cyan
Write-Host ""
