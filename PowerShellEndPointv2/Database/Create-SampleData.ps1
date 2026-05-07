<#
.SYNOPSIS
    Creates sample test data for EMS development
    
.DESCRIPTION
    Populates the database with:
    - Sample users
    - Mock scan results
    - Various health scores
    - Different topologies
    
.EXAMPLE
    .\Create-SampleData.ps1 -Count 50
#>

[CmdletBinding()]
param(
    [int]$Count = 20,
    [switch]$IncludeDiagnostics
)

# Import modules
Import-Module ..\Modules\Logging.psm1 -Force
Import-Module ..\Modules\Database\PSPGSql.psm1 -Force

# Load config
$config = Get-Content ..\Config\EMSConfig.json -Raw | ConvertFrom-Json
Initialize-PostgreSQLConnection -Config $config

Write-Host "`nGenerating $Count sample scan results...`n" -ForegroundColor Cyan

# Sample data arrays
$hostnames = @(
    "DESKTOP-HO-01", "DESKTOP-HO-02", "DESKTOP-HO-03", "DESKTOP-HO-04",
    "LAPTOP-HO-05", "LAPTOP-HO-06", "LAPTOP-REMOTE-07", "LAPTOP-REMOTE-08",
    "WKSTN-DEV-01", "WKSTN-DEV-02", "SERVER-APP-01", "SERVER-DB-01"
)

$users = @("jsmith", "mjohnson", "agarcia", "lwilliams", "kbrown", "admin", "testuser")
$topologies = @("HO", "HO", "HO", "Remote")  # 75% HO, 25% Remote

# Create sample users first
Write-Host "Creating sample users..." -ForegroundColor Yellow
foreach ($username in $users) {
    try {
        $existing = Get-EMSUser -Username $username
        if (-not $existing) {
            New-EMSUser -Username $username -DisplayName $username -Role "operator" | Out-Null
            Write-Host "  ✓ Created user: $username" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  ⚠ Could not create user $username" -ForegroundColor Yellow
    }
}

# Get admin user ID for InitiatedBy
$adminUser = Get-EMSUser -Username "admin"
$initiatedBy = if ($adminUser) { $adminUser.user_id } else { 1 }

Write-Host "`nGenerating scan results..." -ForegroundColor Yellow

# Generate scan results
for ($i = 1; $i -le $Count; $i++) {
    $hostname = $hostnames | Get-Random
    $hostname = "$hostname-$(Get-Random -Minimum 100 -Maximum 999)"
    
    # Generate health score with realistic distribution
    # 60% healthy (80-100), 30% fair (50-79), 10% poor (0-49)
    $rand = Get-Random -Minimum 1 -Maximum 100
    if ($rand -le 60) {
        $healthScore = Get-Random -Minimum 80 -Maximum 100
    }
    elseif ($rand -le 90) {
        $healthScore = Get-Random -Minimum 50 -Maximum 79
    }
    else {
        $healthScore = Get-Random -Minimum 20 -Maximum 49
    }
    
    # Create diagnostics based on health
    $diagnostics = @()
    if ($IncludeDiagnostics) {
        if ($healthScore -lt 50) {
            $diagnostics += @{
                Category             = "System Health"
                SubCategory          = "Performance"
                Severity             = "Critical"
                CheckName            = "CPU_Usage"
                Status               = "Failed"
                Message              = "CPU usage exceeds 90%"
                RemediationAvailable = $true
            }
        }
        if ($healthScore -lt 80) {
            $diagnostics += @{
                Category             = "Security"
                SubCategory          = "Updates"
                Severity             = "Warning"
                CheckName            = "Windows_Updates"
                Status               = "Warning"
                Message              = "Missing security updates"
                RemediationAvailable = $false
            }
        }
    }
    
    # Create scan data
    $scanData = [PSCustomObject]@{
        Hostname             = $hostname
        IPAddress            = "192.168.$(Get-Random -Minimum 1 -Maximum 254).$(Get-Random -Minimum 1 -Maximum 254)"
        UserID               = $users | Get-Random
        ScanTimestamp        = (Get-Date).AddDays( - (Get-Random -Minimum 0 -Maximum 30)).AddHours( - (Get-Random -Minimum 0 -Maximum 23))
        HealthScore          = $healthScore
        Topology             = $topologies | Get-Random
        ExecutionTimeSeconds = [Math]::Round((Get-Random -Minimum 5 -Maximum 25) + (Get-Random) * 10, 1)
        Diagnostics          = $diagnostics
    }
    
    try {
        $scanId = Save-ScanResult -ScanData $scanData -InitiatedBy $initiatedBy
        
        $healthColor = switch ($healthScore) {
            { $_ -ge 90 } { "Green" }
            { $_ -ge 70 } { "Cyan" }
            { $_ -ge 50 } { "Yellow" }
            default { "Red" }
        }
        
        Write-Host ("  [{0,3}/{1}] " -f $i, $Count) -NoNewline
        Write-Host $hostname -NoNewline -ForegroundColor White
        Write-Host " | Score: " -NoNewline
        Write-Host ("{0,3}" -f $healthScore) -NoNewline -ForegroundColor $healthColor
        Write-Host " | ID: $scanId" -ForegroundColor Gray
        
    }
    catch {
        Write-Host "  ✗ Error creating scan $i : $_" -ForegroundColor Red
    }
    
    # Small delay to vary timestamps
    Start-Sleep -Milliseconds 100
}

# Refresh dashboard stats
Write-Host "`nRefreshing dashboard statistics..." -ForegroundColor Yellow
try {
    Invoke-PGQuery -Query "REFRESH MATERIALIZED VIEW dashboard_statistics" -NonQuery | Out-Null
    Write-Host "  ✓ Dashboard statistics updated" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Could not refresh stats: $_" -ForegroundColor Yellow
}

# Display summary
Write-Host "`n========================================" -ForegroundColor Cyan
$stats = Get-DashboardStats
if ($stats) {
    Write-Host "Sample Data Summary:" -ForegroundColor Cyan
    Write-Host "  Total Scans:      $($stats.total_scans)" -ForegroundColor White
    Write-Host "  Unique Endpoints: $($stats.unique_endpoints)" -ForegroundColor White
    Write-Host "  Health Distribution:" -ForegroundColor White
    Write-Host "    Excellent: $($stats.excellent_health)" -ForegroundColor Green
    Write-Host "    Good:      $($stats.good_health)" -ForegroundColor Cyan
    Write-Host "    Fair:      $($stats.fair_health)" -ForegroundColor Yellow
    Write-Host "    Poor:      $($stats.poor_health)" -ForegroundColor Red
}
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "✓ Sample data created successfully!`n" -ForegroundColor Green
