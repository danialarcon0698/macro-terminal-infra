# ============================================================
# AWS Cost Review — Cost Explorer summary and simple anomaly check
# Usage: .\review-costs.ps1 [-Days 30] [-Month]
# Requires: AWS CLI, credentials with ce:GetCostAndUsage
# ============================================================

param(
    [int]$Days = 30,
    [switch]$Month
)

$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ---- Date range ----
if ($Month) {
    $end = Get-Date
    $start = (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0)
    $startStr = $start.ToString("yyyy-MM-dd")
    $endStr = $end.AddDays(1).ToString("yyyy-MM-dd")
    $label = "Current month (through $($end.ToString('yyyy-MM-dd')))"
} else {
    $end = Get-Date
    $start = $end.AddDays(-$Days)
    $startStr = $start.ToString("yyyy-MM-dd")
    $endStr = $end.AddDays(1).ToString("yyyy-MM-dd")
    $label = "Last $Days days"
}

Write-Host "`n=== AWS Cost Review ===" -ForegroundColor Cyan
Write-Host "Period: $label" -ForegroundColor Gray
Write-Host ""

# ---- 1. Cost by service (monthly-style total for the period) ----
Write-Host "--- Cost by service ---" -ForegroundColor Yellow
$byServiceJson = aws ce get-cost-and-usage `
    --time-period Start=$startStr,End=$endStr `
    --granularity DAILY `
    --metrics "UnblendedCost" `
    --group-by Type=DIMENSION,Key=SERVICE `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Cost Explorer call failed. Ensure AWS CLI is configured and you have ce:GetCostAndUsage." -ForegroundColor Red
    Write-Host $byServiceJson -ForegroundColor Red
    exit 1
}

$byService = $byServiceJson | ConvertFrom-Json
$groups = $byService.ResultsByTime | ForEach-Object { $_.Groups } | ForEach-Object { $_ }

# Sum cost per service over the period
$serviceTotals = @{}
foreach ($g in $groups) {
    $name = $g.Keys[0]
    $amount = [double]$g.Metrics.UnblendedCost.Amount
    if (-not $serviceTotals.ContainsKey($name)) { $serviceTotals[$name] = 0 }
    $serviceTotals[$name] += $amount
}

$total = ($serviceTotals.Values | Measure-Object -Sum).Sum
$sorted = $serviceTotals.GetEnumerator() | Sort-Object -Property Value -Descending

foreach ($s in $sorted) {
    if ($s.Value -lt 0.001) { continue }
    $pct = if ($total -gt 0) { [math]::Round(100 * $s.Value / $total, 1) } else { 0 }
    $color = "White"
    if ($pct -ge 50) { $color = "Cyan" }
    elseif ($pct -ge 20) { $color = "Green" }
    Write-Host ("  {0,-40} ${1,8:N2}  ({2}%)" -f $s.Key, $s.Value, $pct) -ForegroundColor $color
}
Write-Host ("  {0,-40} ${1,8:N2}  (100%)" -f "TOTAL", $total) -ForegroundColor Cyan
Write-Host ""

# ---- 1b. Macro Terminal share (approx = total minus domain; optional tag-based) ----
Write-Host "--- Macro Terminal (this infra) ---" -ForegroundColor Yellow
$registrarCost = 0
if ($serviceTotals.ContainsKey("Amazon Registrar")) { $registrarCost = $serviceTotals["Amazon Registrar"] }
$macroApprox = $total - $registrarCost
Write-Host ("  Total account:           {0:N2}" -f $total) -ForegroundColor Gray
if ($registrarCost -gt 0) {
    Write-Host ("  Domain (Registrar):     -{0:N2}" -f $registrarCost) -ForegroundColor Gray
}
Write-Host ("  Macro Terminal (approx): {0:N2}" -f $macroApprox) -ForegroundColor Cyan
# Optional: cost by Project tag (only works if cost allocation tag "Project" is enabled in Billing)
$tagFilter = 'Tags={Key=Project,Values=[macro-terminal]}'
$taggedJson = aws ce get-cost-and-usage --time-period Start=$startStr,End=$endStr --granularity MONTHLY --metrics UnblendedCost --filter $tagFilter --output json 2>&1
if ($LASTEXITCODE -eq 0 -and $taggedJson) {
    $tagged = $taggedJson | ConvertFrom-Json
    $taggedTotal = [double]$tagged.ResultsByTime[0].Total.UnblendedCost.Amount
    if ($taggedTotal -gt 0) {
        Write-Host ("  Macro Terminal (tagged):  {0:N2}" -f $taggedTotal) -ForegroundColor Green
    }
} else {
    Write-Host "  (Enable cost allocation tag 'Project' in Billing for tagged breakdown.)" -ForegroundColor DarkGray
}
Write-Host ""

# ---- 2. Daily trend (for anomaly check) ----
Write-Host "--- Daily trend ---" -ForegroundColor Yellow
$dailyJson = aws ce get-cost-and-usage `
    --time-period Start=$startStr,End=$endStr `
    --granularity DAILY `
    --metrics "UnblendedCost" `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Daily cost call failed." -ForegroundColor Red
    exit 1
}

$daily = $dailyJson | ConvertFrom-Json
$dailyAmounts = @()
foreach ($r in $daily.ResultsByTime) {
    $date = $r.TimePeriod.Start
    $amt = [double]$r.Total.UnblendedCost.Amount
    $dailyAmounts += [pscustomobject]@{ Date = $date; Amount = $amt }
}

if ($dailyAmounts.Count -eq 0) {
    Write-Host "  No daily data in range." -ForegroundColor Gray
} else {
    $avg = ($dailyAmounts | Measure-Object -Property Amount -Average).Average
    $median = ($dailyAmounts | Sort-Object Amount)[[math]::Floor($dailyAmounts.Count / 2)].Amount
    $max = ($dailyAmounts | Measure-Object -Property Amount -Maximum).Maximum
    $maxDate = ($dailyAmounts | Sort-Object Amount -Descending)[0].Date

    foreach ($d in ($dailyAmounts | Sort-Object Date)) {
        $flag = ""
        if ($avg -gt 0 -and $d.Amount -gt 2 * $median -and $d.Amount -gt 0.5) { $flag = " << possible spike" }
        Write-Host ("  {0}  ${1,8:N2}{2}" -f $d.Date, $d.Amount, $flag) -ForegroundColor $(if ($flag) { "Yellow" } else { "Gray" })
    }
    Write-Host ""
    Write-Host "  Average: `$$([math]::Round($avg, 2))/day  |  Max: `$$([math]::Round($max, 2)) on $maxDate" -ForegroundColor Gray
}
Write-Host ""

# ---- 3. Today / yesterday (if in range) ----
$todayStr = (Get-Date).ToString("yyyy-MM-dd")
$yesterdayStr = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$todayRow = $dailyAmounts | Where-Object { $_.Date -eq $todayStr }
$yesterdayRow = $dailyAmounts | Where-Object { $_.Date -eq $yesterdayStr }
if ($todayRow) {
    Write-Host "--- Recent ---" -ForegroundColor Yellow
    Write-Host ("  Today (so far):     {0:N2}" -f $todayRow.Amount) -ForegroundColor White
}
if ($yesterdayRow) {
    Write-Host ("  Yesterday:          {0:N2}" -f $yesterdayRow.Amount) -ForegroundColor White
}
Write-Host ""

Write-Host "Done. Use -Month for current calendar month only." -ForegroundColor DarkGray
