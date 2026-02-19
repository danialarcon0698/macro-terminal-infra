<#
.SYNOPSIS
    Update a user's tier (premium/free) via the admin API.

.DESCRIPTION
    Calls POST /api/admin/set-tier with the admin secret.

.PARAMETER Email
    The user's email address.

.PARAMETER Tier
    The tier to set: "premium" or "free".

.EXAMPLE
    .\set-tier.ps1 -Email "user@example.com" -Tier premium
    .\set-tier.ps1 -Email "user@example.com" -Tier free
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Email,

    [Parameter(Mandatory=$true)]
    [ValidateSet("premium", "free")]
    [string]$Tier
)

# ---- Configuration ----
$API_BASE_URL = "https://api.veridialy.com"

# Read admin_secret from terraform.tfvars (which is gitignored)
$tfvarsPath = Join-Path $PSScriptRoot "terraform.tfvars"
if (-not (Test-Path $tfvarsPath)) {
    Write-Host "  Error: terraform.tfvars not found at $tfvarsPath" -ForegroundColor Red
    exit 1
}
$match = Select-String -Path $tfvarsPath -Pattern 'admin_secret\s*=\s*"(.+)"'
if (-not $match) {
    Write-Host "  Error: admin_secret not found in terraform.tfvars" -ForegroundColor Red
    exit 1
}
$ADMIN_SECRET = $match.Matches[0].Groups[1].Value

# ---- Make the request ----
$headers = @{
    Authorization  = "Bearer $ADMIN_SECRET"
    "Content-Type" = "application/json"
}

$body = @{
    email = $Email
    tier  = $Tier.ToLower()
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod `
        -Uri "$API_BASE_URL/api/admin/set-tier" `
        -Method Post `
        -Headers $headers `
        -Body $body

    Write-Host ""
    Write-Host "  User updated successfully!" -ForegroundColor Green
    Write-Host "  Email:   $($response.email)"
    Write-Host "  Tier:    $($response.tier)"
    Write-Host "  User ID: $($response.user_id)"
    Write-Host ""
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorBody = $_.ErrorDetails.Message
    
    Write-Host ""
    Write-Host "  Failed to update user (HTTP $statusCode)" -ForegroundColor Red
    if ($errorBody) {
        Write-Host "  $errorBody" -ForegroundColor Yellow
    }
    Write-Host ""
    exit 1
}

