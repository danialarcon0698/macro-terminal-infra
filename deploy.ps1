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

# Ensure PATH is up-to-date
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Action
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

function Test-DockerDaemon {
    docker info | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Assert-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI not found in PATH. Install Docker Desktop (or Docker Engine) and try again."
    }

    if (-not (Test-DockerDaemon)) {
        throw "Docker daemon is not running. Start Docker Desktop and retry."
    }
}

function Login-Ecr {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Target
    )

    # Use cmd.exe pipe to keep --password-stdin secure and avoid PowerShell stdin encoding issues.
    cmd /c "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $Target"
    Assert-LastExitCode "Docker login to ECR for $Target"
}

# Configuration
$AWS_REGION = "us-east-1"
$PROJECT_NAME = "macro-terminal"
$REPOS_DIR = Split-Path -Parent (Get-Location)

Write-Host "=== Getting AWS Account ID ===" -ForegroundColor Cyan
$AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text).Trim()
Assert-LastExitCode "Fetching AWS account ID"
if ($AWS_ACCOUNT_ID -notmatch "^\d{12}$") {
    throw "Unexpected AWS account ID value: '$AWS_ACCOUNT_ID'. Check AWS credentials/profile."
}
$ECR_BASE = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# ---- Deploy API ----
function Deploy-Api {
    Write-Host "`n=== Deploying API ===" -ForegroundColor Green
    Assert-DockerReady
    
    Login-Ecr -Target $ECR_BASE
    
    Push-Location "$REPOS_DIR\macro-terminal-api"
    docker build -t "${PROJECT_NAME}-api:latest" .
    Assert-LastExitCode "Building API image"
    docker tag "${PROJECT_NAME}-api:latest" "${ECR_BASE}/${PROJECT_NAME}-api:latest"
    Assert-LastExitCode "Tagging API image"
    docker push "${ECR_BASE}/${PROJECT_NAME}-api:latest"
    Assert-LastExitCode "Pushing API image"
    Pop-Location
    
    aws ecs update-service `
        --cluster "${PROJECT_NAME}-cluster" `
        --service "${PROJECT_NAME}-api" `
        --force-new-deployment `
        --region $AWS_REGION | Out-Null
    Assert-LastExitCode "Updating API ECS service"
    
    Write-Host "API deploy initiated!" -ForegroundColor Green
}

# ---- Deploy Data Provider ----
function Deploy-Data {
    Write-Host "`n=== Deploying Data Provider ===" -ForegroundColor Green
    Assert-DockerReady
    
    Login-Ecr -Target $ECR_BASE
    
    Push-Location "$REPOS_DIR\macro-terminal-data-provider"
    docker build -t "${PROJECT_NAME}-data-provider:latest" .
    Assert-LastExitCode "Building data provider image"
    docker tag "${PROJECT_NAME}-data-provider:latest" "${ECR_BASE}/${PROJECT_NAME}-data-provider:latest"
    Assert-LastExitCode "Tagging data provider image"
    docker push "${ECR_BASE}/${PROJECT_NAME}-data-provider:latest"
    Assert-LastExitCode "Pushing data provider image"
    Pop-Location
    
    Write-Host "Data provider image pushed." -ForegroundColor Green
    Write-Host "This worker is scheduled by EventBridge (no always-on ECS service)." -ForegroundColor Yellow
    Write-Host "To run immediately once, execute:" -ForegroundColor Cyan
    Write-Host "aws ecs run-task --cluster ${PROJECT_NAME}-cluster --task-definition ${PROJECT_NAME}-data-provider --launch-type FARGATE --network-configuration <awsvpcConfiguration> --region $AWS_REGION" -ForegroundColor Gray
}

# ---- Deploy Frontend ----
function Deploy-Frontend {
    Write-Host "`n=== Deploying Frontend ===" -ForegroundColor Green
    
    Push-Location "$REPOS_DIR\macro-terminal-app"
    $env:VITE_API_URL = "https://api.veridialy.com/api"
    npm run build
    Assert-LastExitCode "Building frontend"
    
    $BUCKET = (terraform -chdir="$REPOS_DIR\macro-terminal-infra" output -raw frontend_bucket_name).Trim()
    Assert-LastExitCode "Reading frontend bucket output"
    $CF_ID = (terraform -chdir="$REPOS_DIR\macro-terminal-infra" output -raw cloudfront_distribution_id).Trim()
    Assert-LastExitCode "Reading CloudFront distribution output"
    
    # Upload hashed assets with long cache (immutable — filename changes on every build)
    aws s3 sync dist/assets/ "s3://$BUCKET/assets/" --delete `
        --cache-control "public, max-age=31536000, immutable"
    Assert-LastExitCode "Uploading frontend assets to S3"
    
    # Upload index.html with no-cache (browser must always revalidate)
    aws s3 cp dist/index.html "s3://$BUCKET/index.html" `
        --cache-control "no-cache, no-store, must-revalidate"
    Assert-LastExitCode "Uploading index.html to S3"
    
    aws cloudfront create-invalidation --distribution-id $CF_ID --paths "/*" | Out-Null
    Assert-LastExitCode "Invalidating CloudFront cache"
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
