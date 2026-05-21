<#
    EMS REST API - Enterprise Monitoring System (Service Controller)
    Version: 3.5-Enterprise (Modular Structure)
    Runtime: PowerShell 7.x
#>

#Requires -Version 7.0

# -------------------------
# 1. Initialization & Config
# -------------------------
$ErrorActionPreference = 'Stop'
$RootPath   = Split-Path $PSScriptRoot -Parent
$ModuleRoot = Join-Path $RootPath 'Modules'
$ConfigPath = Join-Path $RootPath 'Config\EMSConfig.json'

# Load Base Infrastructure
Import-Module "$ModuleRoot\Logging.psm1" -Force
Import-Module "$ModuleRoot\Database\PSPGSql.psm1" -Force
Import-Module "$ModuleRoot\Authentication.psm1" -Force
Import-Module "$ModuleRoot\Authentication\AuthProviders.psm1" -Force

# Load New Core Modules
Import-Module "$ModuleRoot\Core\EMS.Core.psm1" -Force
Import-Module "$ModuleRoot\Core\EMS.Auth.psm1" -Force

# Load API Controllers
Import-Module "$ModuleRoot\API\EMS.API.Admin.psm1" -Force
Import-Module "$ModuleRoot\API\EMS.API.Auth.psm1" -Force
Import-Module "$ModuleRoot\API\EMS.API.Inventory.psm1" -Force
Import-Module "$ModuleRoot\API\EMS.API.Scan.psm1" -Force
Import-Module "$ModuleRoot\API\EMS.API.Reports.psm1" -Force

# Load Worker Modules (Existing)
Import-Module "$ModuleRoot\Scan\ScanWorker.psm1" -Force
Import-Module "$ModuleRoot\BulkProcessor.psm1" -Force

# Load Configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] Configuration file not found at $ConfigPath" -ForegroundColor Red
    exit 1
}

try {
    $rawConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $Global:EMSConfig = $rawConfig
} catch {
    Write-Host "[ERROR] Failed to parse configuration file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Ensure Database Connection
$dbModule = Import-Module "$ModuleRoot\Database\PSPGSql.psm1" -Force -PassThru
if ($dbModule) {
    Write-Host "[DEBUG] Database module loaded. Exported commands: $($dbModule.ExportedCommands.Keys -join ', ')" -ForegroundColor Gray
}

if (Get-Command Initialize-PostgreSQLConnection -ErrorAction SilentlyContinue) {
    Initialize-PostgreSQLConnection -Config $Global:EMSConfig
} else {
    Write-Host "[ERROR] Initialize-PostgreSQLConnection command not found. Database module failed to load." -ForegroundColor Red
    Write-Host "[DEBUG] Available modules: $((Get-Module).Name -join ', ')" -ForegroundColor Gray
    exit 1
}

# Ensure Security Defaults
if (-not $Global:EMSConfig.PSObject.Properties['Security']) { $Global:EMSConfig | Add-Member -NotePropertyName Security -NotePropertyValue ([pscustomobject]@{}) }
if (-not $Global:EMSConfig.Security.PSObject.Properties['AdminGroup']) { $Global:EMSConfig.Security | Add-Member -NotePropertyName AdminGroup -NotePropertyValue 'EMS_Admins' }
if (-not $Global:EMSConfig.Security.PSObject.Properties['MonitorGroup']) { $Global:EMSConfig.Security | Add-Member -NotePropertyName MonitorGroup -NotePropertyValue 'EMS_Monitor' }

# Parse Listen Port from Config
$prefixes = @("https://+:5443/")
if ($Global:EMSConfig.API -and $Global:EMSConfig.API.Prefixes) {
    $prefixes = $Global:EMSConfig.API.Prefixes
}

# -------------------------
# 2. Main Service Loop
# -------------------------
$listener = [System.Net.HttpListener]::new()
foreach ($prefix in $prefixes) {
    $p = $prefix
    if (-not $p.EndsWith('/')) { $p += '/' }
    $listener.Prefixes.Add($p)
}

Write-Host "[INFO] EMS REST API (Modular) initializing on $($prefixes -join ', ') ..." -ForegroundColor Cyan

$Global:ScanReaperTimer = New-Object System.Timers.Timer 30000
Register-ObjectEvent -InputObject $Global:ScanReaperTimer -EventName Elapsed `
    -Action { Invoke-EMSScanReaper } | Out-Null
$Global:ScanReaperTimer.Start()

try {
    try {
        $listener.Start()
        Write-EMSLog -Message "API Service started on $($prefixes -join ', ')" -Severity Success
    } catch {
        $exMsg = $_.Exception.Message
        if ($exMsg -match "conflicts with an existing registration") {
            Write-Host "[ERROR] A port is already in use." -ForegroundColor Red

            # Try to extract a port to check for a blocking process
            $port = 5443
            if ($prefixes -and $prefixes.Count -gt 0 -and $prefixes[0] -match ':(\d+)') {
                $port = $matches[1]
            }

            # Try to find the blocking process
            $netstat = netstat -ano | Select-String ":$port\s" | Select-Object -First 1
            if ($netstat) {
                $parts = -split $netstat.ToString().Trim()
                $pidValue = $parts[-1]
                Write-Host "[ACTION REQUIRED] Port $port is held by Process ID (PID): $pidValue" -ForegroundColor Yellow
                Write-Host "                To kill it, run: Stop-Process -Id $pidValue -Force" -ForegroundColor Yellow
                
                try {
                    $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
                    if ($proc) {
                        Write-Host "                Process Name: $($proc.ProcessName)" -ForegroundColor Yellow
                    }
                } catch { }
            }
            Write-EMSLog -Message "Failed to start API listener: Port $port in use." -Severity Error
            exit 1
        } elseif ($exMsg -match "Access is denied") {
            Write-Host "[ERROR] Access is denied when binding to the port." -ForegroundColor Red
            Write-Host "[ACTION REQUIRED] You must run PowerShell as Administrator to start the API Service." -ForegroundColor Yellow
            Write-EMSLog -Message "Failed to start API listener: Access Denied. Requires Administrator privileges." -Severity Error
            exit 1
        } else {
            throw $_
        }
    }
    
    # 3. Rate Limiting Setup
    $Global:RateLimitCache = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
    $RateLimitMaxRequests = 100
    $RateLimitWindowSeconds = 60

    function Test-EMSRateLimit {
        param(
            [Parameter(Mandatory)][string]$Key,
            [int]$Max         = $RateLimitMaxRequests,
            [int]$WindowSec   = $RateLimitWindowSeconds
        )
        $now = Get-Date
        $entry = $Global:RateLimitCache.AddOrUpdate(
            $Key,
            [Func[string, object]]{ @{ Count = 1; WindowStart = $now } },
            [Func[string, object, object]]{ param($k,$old)
                if (($now - $old.WindowStart).TotalSeconds -gt $WindowSec) {
                    @{ Count = 1; WindowStart = $now }
                } else {
                    @{ Count = $old.Count + 1; WindowStart = $old.WindowStart }
                } })
        return $entry.Count -le $Max
    }

    while ($listener.IsListening) {
        $context = $null
        try {
            $context  = $listener.GetContext()
            $request  = $context.Request
            $response = $context.Response
            
            # 1.4 Route Processing

            $method = $request.HttpMethod
            # Support both /api/... and /... for all routes
            $rawPath = $request.Url.AbsolutePath
            $path    = $rawPath -replace '^/api', ''
            if ($path -eq '') { $path = '/' }
            
            Write-Host "[DEBUG] Incoming Request: $method $rawPath -> Routed as: $path" -ForegroundColor Gray
            $start  = [DateTime]::Now

            # Apply Security Headers
            $response.Headers.Add('Strict-Transport-Security','max-age=31536000; includeSubDomains')
            $response.Headers.Add('X-Content-Type-Options','nosniff')
            $response.Headers.Add('X-Frame-Options','DENY')
            $response.Headers.Add('Referrer-Policy','strict-origin-when-cross-origin')

            # 1. Handle CORS Preflight
            if ($method -eq 'OPTIONS') {
                Add-EMSCORSHeaders -Request $request -Response $response -Config $Global:EMSConfig
                $response.StatusCode = 204
                $response.Close()
                continue
            }

            # 1.5 Rate Limiting
            $clientIp = $request.RemoteEndPoint.Address.ToString()
            $now = [DateTime]::Now
            if (-not $Global:RateLimitCache.ContainsKey($clientIp)) {
                $Global:RateLimitCache[$clientIp] = @{ Count = 1; ResetTime = $now.AddSeconds($RateLimitWindowSeconds) }
            } else {
                $limitInfo = $Global:RateLimitCache[$clientIp]
                if ($now -gt $limitInfo.ResetTime) {
                    $limitInfo.Count = 1
                    $limitInfo.ResetTime = $now.AddSeconds($RateLimitWindowSeconds)
                } else {
                    $limitInfo.Count++
                    if ($limitInfo.Count -gt $RateLimitMaxRequests) {
                        Write-EMSLog -Message "Rate limit exceeded for IP: $clientIp" -Severity Warning -Category "Security"
                        Add-EMSCORSHeaders -Request $request -Response $response -Config $Global:EMSConfig
                        Write-EMSJsonResponse $request $response 429 @{ success = $false; error = "Too Many Requests. Please try again later." }
                        continue
                    }
                }
            }

            # 1.6 Health Check / Root
            if ($Method -eq 'GET' -and $Path -eq '/') {
                Write-EMSJsonResponse $request $response 200 @{ success = $true; version = '5.0.0-Enterprise'; status = 'Running' }
                continue
            }

            # 2. Authentication Logic (Legacy compatibility for /auth routes)
            if ($Method -eq 'GET' -and $Path -match '^(/api)?/auth/providers$') {
                $providers = $Global:EMSConfig.Authentication.Providers | Where-Object Enabled | Sort-Object Priority | ForEach-Object {
                    [pscustomobject]@{ Name=$_.Name; DisplayName="$($_.Name) Authentication"; RequiresCredentials=$true; Priority=[int]$_.Priority; Id=$_.Name; Value=$_.Name; Label="$($_.Name) Authentication" }
                }
                Write-EMSJsonResponse $request $response 200 @{ providers = $providers; defaultProvider = if ($providers.Count -gt 0) { $providers[0].Name } else { $null } }
                continue
            }

            if ($Method -eq 'GET' -and $Path -match '^(/api)?/auth/validate$') {
                if (-not (Test-ViewerAccessRequirement -Request $request -Response $response -Config $Global:EMSConfig)) { continue }
                $ctx  = Get-RequestUserContext -Request $request
                $role = Resolve-UserRole -Groups $ctx.Groups -Config $Global:EMSConfig
                Write-EMSJsonResponse $request $response 200 @{ valid = $true; role = $role; permissions = (Get-UserPermissionsObject -Role $role) }
                continue
            }

            if ($Method -eq 'POST' -and $Path -match '^(/api)?/auth/login$') {
                $body = Read-JsonBody $request
                if (-not $body.username -or -not $body.password) {
                    Write-EMSJsonResponse $request $response 400 @{ success = $false; message = 'Username and password are required' }
                    continue
                }

                $maxAttempts = if ($Global:EMSConfig.Authentication.MaxFailedAttempts) { $Global:EMSConfig.Authentication.MaxFailedAttempts } else { 5 }
                if (-not (Test-EMSRateLimit -Key "login:$($body.username)" -Max $maxAttempts -WindowSec 300)) {
                    Write-EMSLog -Message "Login rate limit exceeded for user: $($body.username)" -Severity Warning -Category "Security"
                    Add-EMSCORSHeaders -Request $request -Response $response -Config $Global:EMSConfig
                    Write-EMSJsonResponse $request $response 429 @{ success = $false; error = "Too many failed login attempts. Please try again later." }
                    continue
                }

                $provider = Resolve-ProviderValue -ProviderInput $body.provider
                $securePassword = ConvertTo-SecureString $body.password -AsPlainText -Force
                $auth = Invoke-MultiProviderAuth -Username $body.username -SecurePassword $securePassword -Provider $provider -Config $Global:EMSConfig
                
                if (-not $auth.Success) {
                    Write-EMSJsonResponse $request $response 401 @{ success = $false; message = 'Authentication failed' }
                    continue
                }
                
                $role = Resolve-UserRole -Groups $auth.Groups -Config $Global:EMSConfig
                if (-not $role) {
                    Write-EMSJsonResponse $request $response 403 @{ success = $false; message = 'Access denied. Missing role assignment.' }
                    continue
                }
                
                Write-EMSJsonResponse $request $response 200 @{ success=$true; user=@{ username=$auth.User; displayName=$auth.DisplayName; role=$role; permissions=(Get-UserPermissionsObject -Role $role) } }
                continue
            }

            # 3. Delegate to Modular Controllers
            $handled = $false
            $modulePath = $path -replace '^/api', ''
            if (-not $modulePath.StartsWith('/')) { $modulePath = "/$modulePath" }
            
            # Auth
            if (-not $handled) { $handled = Invoke-AuthRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }

            # Inventory & Dashboards
            if (-not $handled) { $handled = Invoke-InventoryRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }
            
            # Administrative Operations
            if (-not $handled) { $handled = Invoke-AdminRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }
            
            # Credential & Environment Management
            if (-not $handled) { $handled = Invoke-CredentialRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }
            
            # Scans & Errors
            if (-not $handled) { $handled = Invoke-ScanRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }

            # Advanced Reports
            if (-not $handled) { $handled = Invoke-ReportRoutes -Request $request -Response $response -Method $method -Path $modulePath -Config $Global:EMSConfig }

            # 4. Final Fallback
            if (-not $handled) {
                Write-EMSJsonResponse $request $response 404 @{ error = "Endpoint '$method $path' not found (Raw: $rawPath)" }
            }

            # 5. Telemetry
            $duration = ([DateTime]::Now - $start).TotalMilliseconds
            $ctx = Get-RequestUserContext -Request $request
            Invoke-PGQuery -NonQuery -Query "INSERT INTO audit_api_requests (method, path, username, ip_address, status_code, response_time_ms, timestamp) VALUES (@m, @p, @u, CAST(@ip AS inet), @s, @d, NOW());" -Parameters @{ m=$method; p=$path; u=$ctx.Username; ip=$request.RemoteEndPoint.Address.ToString(); s=$response.StatusCode; d=$duration }
        }
        catch {
            $err = $_.Exception.Message
            Write-EMSLog -Message "Request Error ($path): $err" -Severity Error
            if ($context -and $context.Response) {
                try { Write-EMSJsonResponse $context.Request $context.Response 500 @{ error = $err } } catch {}
            }
        }
    }
}
catch {
    Write-EMSLog -Message "Critical Service Failure: $($_.Exception.Message)" -Severity Error
}
finally {
    if ($null -ne $listener) {
        try {
            if ($listener.IsListening) { $listener.Stop() }
            $listener.Close()
        } catch { }
    }
}
