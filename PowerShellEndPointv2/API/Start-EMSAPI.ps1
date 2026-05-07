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
Import-Module "$ModuleRoot\API\EMS.API.Inventory.psm1" -Force
Import-Module "$ModuleRoot\API\EMS.API.Scan.psm1" -Force

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
if (Get-Command Initialize-PostgreSQLConnection -ErrorAction SilentlyContinue) {
    Initialize-PostgreSQLConnection -Config $Global:EMSConfig
} else {
    Write-Host "[ERROR] Initialize-PostgreSQLConnection command not found. Database module failed to load." -ForegroundColor Red
    exit 1
}

# Ensure Security Defaults
if (-not $Global:EMSConfig.PSObject.Properties['Security']) { $Global:EMSConfig | Add-Member -NotePropertyName Security -NotePropertyValue ([pscustomobject]@{}) }
if (-not $Global:EMSConfig.Security.PSObject.Properties['AdminGroup']) { $Global:EMSConfig.Security | Add-Member -NotePropertyName AdminGroup -NotePropertyValue 'EMS_Admins' }
if (-not $Global:EMSConfig.Security.PSObject.Properties['MonitorGroup']) { $Global:EMSConfig.Security | Add-Member -NotePropertyName MonitorGroup -NotePropertyValue 'EMS_Monitor' }

Write-Host '[INFO] EMS REST API (Modular) initializing on port 5000...' -ForegroundColor Cyan

# -------------------------
# 2. Main Service Loop
# -------------------------
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://*:5000/')

try {
    $listener.Start()
    Write-EMSLog -Message "API Service started on http://*:5000/" -Severity Success
    
    while ($listener.IsListening) {
        $context = $null
        try {
            $context  = $listener.GetContext()
            $request  = $context.Request
            $response = $context.Response
            
            $method = $request.HttpMethod
            $path   = $request.Url.AbsolutePath
            $start  = [DateTime]::Now

            # 1. Handle CORS Preflight
            if ($method -eq 'OPTIONS') {
                Add-CorsHeaders -Request $request -Response $response
                $response.StatusCode = 204
                $response.Close()
                continue
            }

            # 2. Authentication Logic (Legacy compatibility for /auth routes)
            if ($Method -eq 'GET' -and $Path -eq '/auth/providers') {
                $providers = $Global:EMSConfig.Authentication.Providers | Where-Object Enabled | Sort-Object Priority | ForEach-Object {
                    [pscustomobject]@{ Name=$_.Name; DisplayName="$($_.Name) Authentication"; RequiresCredentials=$true; Priority=[int]$_.Priority; Id=$_.Name; Value=$_.Name; Label="$($_.Name) Authentication" }
                }
                Write-JsonResponse $request $response 200 @{ providers = $providers; defaultProvider = if ($providers.Count -gt 0) { $providers[0].Name } else { $null } }
                continue
            }

            if ($Method -eq 'GET' -and $Path -eq '/auth/validate') {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { continue }
                $ctx  = Get-RequestUserContext -Request $request
                $role = Resolve-UserRole -Groups $ctx.Groups -Config $Global:EMSConfig
                Write-JsonResponse $request $response 200 @{ valid = $true; role = $role; permissions = (Get-UserPermissionsObject -Role $role) }
                continue
            }

            if ($Method -eq 'POST' -and $Path -eq '/auth/login') {
                $body = Read-JsonBody $request
                if (-not $body.username -or -not $body.password) {
                    Write-JsonResponse $request $response 400 @{ success = $false; message = 'Username and password are required' }
                    continue
                }
                $provider = Resolve-ProviderValue -ProviderInput $body.provider
                $securePassword = ConvertTo-SecureString $body.password -AsPlainText -Force
                $auth = Invoke-MultiProviderAuth -Username $body.username -SecurePassword $securePassword -Provider $provider -Config $Global:EMSConfig
                
                if (-not $auth.Success) {
                    Write-JsonResponse $request $response 401 @{ success = $false; message = 'Authentication failed' }
                    continue
                }
                
                $role = Resolve-UserRole -Groups $auth.Groups -Config $Global:EMSConfig
                if (-not $role) {
                    Write-JsonResponse $request $response 403 @{ success = $false; message = 'Access denied. Missing role assignment.' }
                    continue
                }
                
                Write-JsonResponse $request $response 200 @{ success=$true; user=@{ username=$auth.User; displayName=$auth.DisplayName; role=$role; permissions=(Get-UserPermissionsObject -Role $role) } }
                continue
            }

            # 3. Delegate to Modular Controllers
            $handled = $false
            
            # Inventory & Dashboards
            if (-not $handled) { $handled = Invoke-InventoryRoutes -Request $request -Response $response -Method $method -Path $path -Config $Global:EMSConfig }
            
            # Administrative Operations
            if (-not $handled) { $handled = Invoke-AdminRoutes -Request $request -Response $response -Method $method -Path $path -Config $Global:EMSConfig }
            
            # Scans & Errors
            if (-not $handled) { $handled = Invoke-ScanRoutes -Request $request -Response $response -Method $method -Path $path -Config $Global:EMSConfig }

            # 4. Final Fallback
            if (-not $handled) {
                Write-JsonResponse $request $response 404 @{ error = "Endpoint '$path' not found" }
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
                try { Write-JsonResponse $context.Request $context.Response 500 @{ error = $err } } catch {}
            }
        }
    }
}
catch {
    Write-EMSLog -Message "Critical Service Failure: $($_.Exception.Message)" -Severity Error
}
finally {
    if ($listener) { $listener.Stop(); $listener.Close() }
}
