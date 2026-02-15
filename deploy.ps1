# ============================================================
# Deploy Script — Build, push, and deploy all services
# Usage:
#   .\deploy.ps1 all           — deploy everything
#   .\deploy.ps1 api           — deploy API only
#   .\deploy.ps1 data          — deploy data provider only
#   .\deploy.ps1 frontend      — deploy frontend only
# ============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("all", "api", "data", "frontend")]
    [string]$Service = "all"
)

$ErrorActionPreference = "Stop"

# Configuration
$AWS_REGION = "us-east-1"
$PROJECT_NAME = "macro-terminal"
$REPOS_DIR = Split-Path -Parent (Get-Location)

Write-Host "=== Getting AWS Account ID ===" -ForegroundColor Cyan
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$ECR_BASE = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# ---- Deploy API ----
function Deploy-Api {
    Write-Host "`n=== Deploying API ===" -ForegroundColor Green
    
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_BASE
    
    Push-Location "$REPOS_DIR\macro-terminal-api"
    docker build -t "${PROJECT_NAME}-api:latest" .
    docker tag "${PROJECT_NAME}-api:latest" "${ECR_BASE}/${PROJECT_NAME}-api:latest"
    docker push "${ECR_BASE}/${PROJECT_NAME}-api:latest"
    Pop-Location
    
    aws ecs update-service `
        --cluster "${PROJECT_NAME}-cluster" `
        --service "${PROJECT_NAME}-api" `
        --force-new-deployment `
        --region $AWS_REGION | Out-Null
    
    Write-Host "API deploy initiated!" -ForegroundColor Green
}

# ---- Deploy Data Provider ----
function Deploy-Data {
    Write-Host "`n=== Deploying Data Provider ===" -ForegroundColor Green
    
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_BASE
    
    Push-Location "$REPOS_DIR\macro-terminal-data-provider"
    docker build -t "${PROJECT_NAME}-data-provider:latest" .
    docker tag "${PROJECT_NAME}-data-provider:latest" "${ECR_BASE}/${PROJECT_NAME}-data-provider:latest"
    docker push "${ECR_BASE}/${PROJECT_NAME}-data-provider:latest"
    Pop-Location
    
    aws ecs update-service `
        --cluster "${PROJECT_NAME}-cluster" `
        --service "${PROJECT_NAME}-data-provider" `
        --force-new-deployment `
        --region $AWS_REGION | Out-Null
    
    Write-Host "Data provider deploy initiated!" -ForegroundColor Green
}

# ---- Deploy Frontend ----
function Deploy-Frontend {
    Write-Host "`n=== Deploying Frontend ===" -ForegroundColor Green
    
    Push-Location "$REPOS_DIR\macro-terminal-app"
    npm run build
    
    $BUCKET = terraform -chdir="$REPOS_DIR\macro-terminal-infra" output -raw frontend_bucket_name
    $CF_ID = terraform -chdir="$REPOS_DIR\macro-terminal-infra" output -raw cloudfront_distribution_id
    
    aws s3 sync dist/ "s3://$BUCKET" --delete
    aws cloudfront create-invalidation --distribution-id $CF_ID --paths "/*" | Out-Null
    Pop-Location
    
    Write-Host "Frontend deployed and cache invalidated!" -ForegroundColor Green
}

# ---- Execute ----
switch ($Service) {
    "all" {
        Deploy-Api
        Deploy-Data
        Deploy-Frontend
    }
    "api"      { Deploy-Api }
    "data"     { Deploy-Data }
    "frontend" { Deploy-Frontend }
}

Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "API:      https://api.veridialy.com"
Write-Host "Frontend: https://veridialy.com"
