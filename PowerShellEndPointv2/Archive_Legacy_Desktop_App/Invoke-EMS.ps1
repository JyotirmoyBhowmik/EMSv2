<#
.SYNOPSIS
    Enterprise Distributed Endpoint Monitoring System (EMS)

.DESCRIPTION
    Main entry point for the WPF-based endpoint monitoring and remediation platform.
    Implements asynchronous multi-threaded architecture using PowerShell Runspaces.

.NOTES
    Author: Enterprise IT Team
    Version: 1.0
    Date: 2025-12-23
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import required assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# Global variables
$Global:SyncHash = [hashtable]::Synchronized(@{})
$Global:RunspacePool = $null
$Global:Jobs = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
$Global:CurrentUser = $null
$Global:IsAuthorized = $false
$Global:Config = $null

# Import modules
$ModulePath = Join-Path $PSScriptRoot "Modules"
Get-ChildItem -Path $ModulePath -Filter "*.psm1" -Recurse | ForEach-Object {
    Import-Module $_.FullName -Force
}

#region Configuration Loading
function Initialize-Configuration {
    <#
    .SYNOPSIS
        Loads configuration from JSON file
    #>
    $configPath = Join-Path $PSScriptRoot "Config\EMSConfig.json"
    
    if (Test-Path $configPath) {
        $Global:Config = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Host "[INFO] Configuration loaded from $configPath" -ForegroundColor Green
    }
    else {
        # Default configuration
        $Global:Config = @{
            Topology            = @{
                HOSubnets           = @('10.192.10.0/23', '10.192.13.0/24', '10.192.14.0/24')
                RemoteSubnets       = @('10.192.15.0/24', '10.192.16.0/24', '10.192.20.0/24')
                HOThrottleLimit     = 40
                RemoteThrottleLimit = 4
            }
            Security            = @{
                AdminGroup        = 'EMS_Admins'
                AuditLogPath      = '\\FileServer\Logs\EMS'
                EnableRemediation = $true
            }
            UserResolution      = @{
                UseSCCM                   = $true
                EventLogTimeWindowMinutes = 60
                TimeoutSeconds            = 30
            }
            BlacklistedSoftware = @('Dropbox', 'Steam', 'Tor Browser')
        }
        Write-Warning "[WARN] Configuration file not found. Using defaults."
    }
}
#endregion

#region Runspace Pool Management
function Initialize-RunspacePool {
    <#
    .SYNOPSIS
        Creates a runspace pool for parallel processing
    #>
    param(
        [int]$MinRunspaces = 1,
        [int]$MaxRunspaces = 10
    )
    
    $Global:RunspacePool = [runspacefactory]::CreateRunspacePool($MinRunspaces, $MaxRunspaces)
    $Global:RunspacePool.ApartmentState = "STA"
    $Global:RunspacePool.ThreadOptions = "ReuseThread"
    $Global:RunspacePool.Open()
    
    Write-Host "[INFO] Runspace pool initialized ($MinRunspaces-$MaxRunspaces threads)" -ForegroundColor Green
}

function Invoke-AsyncJob {
    <#
    .SYNOPSIS
        Executes a script block asynchronously in the runspace pool
    #>
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [hashtable]$Parameters = @{}
    )
    
    $PowerShell = [powershell]::Create()
    $PowerShell.RunspacePool = $Global:RunspacePool
    
    # Add the script block
    [void]$PowerShell.AddScript($ScriptBlock)
    
    # Add parameters
    foreach ($key in $Parameters.Keys) {
        [void]$PowerShell.AddParameter($key, $Parameters[$key])
    }
    
    # Start async execution
    $AsyncHandle = $PowerShell.BeginInvoke()
    
    # Track the job
    $Job = [PSCustomObject]@{
        PowerShell = $PowerShell
        Handle     = $AsyncHandle
        StartTime  = Get-Date
    }
    
    [void]$Global:Jobs.Add($Job)
    
    return $Job
}

function Get-CompletedJobs {
    <#
    .SYNOPSIS
        Retrieves and cleans up completed jobs
    #>
    $completed = @()
    
    foreach ($job in $Global:Jobs) {
        if ($job.Handle.IsCompleted) {
            try {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()
                $completed += $job
                
                # Return results
                $result
            }
            catch {
                Write-EMSLog -Message "Job error: $_" -Severity 'Error'
            }
        }
    }
    
    # Remove completed jobs from tracking
    foreach ($job in $completed) {
        [void]$Global:Jobs.Remove($job)
    }
}
#endregion

#region UI Helpers
function Update-UIElement {
    <#
    .SYNOPSIS
        Thread-safe UI update using Dispatcher
    #>
    param(
        [Parameter(Mandatory)]
        [System.Windows.UIElement]$Element,
        
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    
    $Element.Dispatcher.Invoke([action]$Action, "Normal")
}

function Write-LogToUI {
    <#
    .SYNOPSIS
        Appends message to activity log
    #>
    param(
        [string]$Message,
        [string]$Severity = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Severity] $Message"
    
    if ($Global:SyncHash.txtLog) {
        Update-UIElement -Element $Global:SyncHash.txtLog -Action {
            $Global:SyncHash.txtLog.AppendText("$logEntry`n")
            $Global:SyncHash.txtLog.ScrollToEnd()
        }
    }
    
    # Also write to console
    switch ($Severity) {
        'Error' { Write-Host $logEntry -ForegroundColor Red }
        'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
        'Success' { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor White }
    }
}

function Update-StatusBar {
    <#
    .SYNOPSIS
        Updates status bar text and progress
    #>
    param(
        [string]$Message,
        [int]$ProgressValue = -1,
        [switch]$ShowProgress
    )
    
    if ($Global:SyncHash.txtStatus) {
        Update-UIElement -Element $Global:SyncHash.txtStatus -Action {
            $Global:SyncHash.txtStatus.Text = $Message
        }
    }
    
    if ($ShowProgress -and $Global:SyncHash.progressBar) {
        Update-UIElement -Element $Global:SyncHash.progressBar -Action {
            $Global:SyncHash.progressBar.Visibility = 'Visible'
            if ($ProgressValue -ge 0) {
                $Global:SyncHash.progressBar.Value = $ProgressValue
            }
        }
    }
    elseif ($Global:SyncHash.progressBar) {
        Update-UIElement -Element $Global:SyncHash.progressBar -Action {
            $Global:SyncHash.progressBar.Visibility = 'Collapsed'
        }
    }
}
#endregion

#region Event Handlers
function Register-EventHandlers {
    <#
    .SYNOPSIS
        Registers all UI event handlers
    #>
    
    # Login button
    $Global:SyncHash.btnLogin.Add_Click({
            $username = $Global:SyncHash.txtUsername.Text
            $password = $Global:SyncHash.txtPassword.SecurePassword
        
            if ([string]::IsNullOrWhiteSpace($username)) {
                $Global:SyncHash.txtLoginStatus.Text = "Please enter a username"
                return
            }
        
            # Disable login button during authentication
            $Global:SyncHash.btnLogin.IsEnabled = $false
            $Global:SyncHash.txtLoginStatus.Text = "Authenticating..."
        
            # Perform authentication asynchronously
            $authJob = Invoke-AsyncJob -ScriptBlock {
                param($user, $pass, $config)
            
                # Import authentication module
                Import-Module "$($config.ModulePath)\Authentication.psm1" -Force
            
                # Validate credentials
                $isValid = Test-ADCredential -Username $user -SecurePassword $pass
            
                if ($isValid) {
                    # Check authorization
                    $isAuthorized = Test-UserAuthorization -Username $user -RequiredGroup $config.AdminGroup
                
                    return @{
                        Success    = $true
                        Authorized = $isAuthorized
                        User       = $user
                    }
                }
                else {
                    return @{
                        Success = $false
                        Message = "Invalid credentials"
                    }
                }
            } -Parameters @{
                user   = $username
                pass   = $password
                config = @{
                    ModulePath = $ModulePath
                    AdminGroup = $Global:Config.Security.AdminGroup
                }
            }
        
            # Poll for completion (this would be better with a timer)
            Start-Sleep -Milliseconds 500
        
            $result = Get-CompletedJobs
        
            if ($result.Success) {
                if ($result.Authorized) {
                    # Successful login
                    $Global:CurrentUser = $result.User
                    $Global:IsAuthorized = $true
                
                    Update-UIElement -Element $Global:SyncHash.LoginOverlay -Action {
                        $Global:SyncHash.LoginOverlay.Visibility = 'Collapsed'
                        $Global:SyncHash.MainContent.Visibility = 'Visible'
                        $Global:SyncHash.txtLoggedInUser.Text = "User: $($Global:CurrentUser)"
                    }
                
                    Write-LogToUI -Message "User $($Global:CurrentUser) logged in successfully" -Severity 'Success'
                    Write-AuditLog -Action 'Login' -User $Global:CurrentUser -Result 'Success'
                }
                else {
                    $Global:SyncHash.txtLoginStatus.Text = "Access denied. Not in $($Global:Config.Security.AdminGroup) group."
                    $Global:SyncHash.btnLogin.IsEnabled = $true
                    Write-AuditLog -Action 'Login' -User $username -Result 'Unauthorized'
                }
            }
            else {
                $Global:SyncHash.txtLoginStatus.Text = $result.Message
                $Global:SyncHash.btnLogin.IsEnabled = $true
                Write-AuditLog -Action 'Login' -User $username -Result 'Failed'
            }
        })
    
    # Logout button
    $Global:SyncHash.btnLogout.Add_Click({
            Write-AuditLog -Action 'Logout' -User $Global:CurrentUser -Result 'Success'
        
            Update-UIElement -Element $Global:SyncHash.LoginOverlay -Action {
                $Global:SyncHash.LoginOverlay.Visibility = 'Visible'
                $Global:SyncHash.MainContent.Visibility = 'Collapsed'
                $Global:SyncHash.txtUsername.Text = ''
                $Global:SyncHash.txtPassword.Clear()
                $Global:SyncHash.txtLoginStatus.Text = ''
                $Global:SyncHash.btnLogin.IsEnabled = $true
            }
        
            $Global:CurrentUser = $null
            $Global:IsAuthorized = $false
        })
    
    # Scan button
    $Global:SyncHash.btnScan.Add_Click({
            $target = $Global:SyncHash.txtTarget.Text.Trim()
        
            if ([string]::IsNullOrWhiteSpace($target)) {
                [System.Windows.MessageBox]::Show("Please enter a target hostname, IP, or User ID", "Input Required", 'OK', 'Warning')
                return
            }
        
            Write-LogToUI -Message "Initiating scan for target: $target" -Severity 'Info'
            Update-StatusBar -Message "Processing target..." -ShowProgress
        
            # Process asynchronously
            $scanJob = Invoke-AsyncJob -ScriptBlock {
                param($input, $config, $modulePath)
            
                # Import modules
                Import-Module "$modulePath\InputBroker.psm1" -Force
                Import-Module "$modulePath\DataFetcher.psm1" -Force
                Import-Module "$modulePath\TopologyDetector.psm1" -Force
                Import-Module "$modulePath\UserResolution.psm1" -Force
                Import-Module "$modulePath\Logging.psm1" -Force
            
                # Route input
                $targets = Invoke-InputRouter -Input $input -Config $config
            
                if ($targets) {
                    # Fetch data
                    $results = Invoke-DataFetch -Targets $targets -Config $config
                    return $results
                }
            
                return $null
            
            } -Parameters @{
                input      = $target
                config     = $Global:Config
                modulePath = $ModulePath
            }
        
            # Poll for results (in production, use a timer)
            Start-Sleep -Milliseconds 100
            $completedResults = Get-CompletedJobs
        
            if ($completedResults) {
                foreach ($result in $completedResults) {
                    Update-UIElement -Element $Global:SyncHash.dgResults -Action {
                        $Global:SyncHash.dgResults.Items.Add($result)
                    }
                
                    # Update statistics
                    $total = $Global:SyncHash.dgResults.Items.Count
                    $healthy = ($Global:SyncHash.dgResults.Items | Where-Object { $_.HealthScore -ge 80 }).Count
                    $critical = ($Global:SyncHash.dgResults.Items | Where-Object CriticalAlerts -gt 0).Count
                
                    Update-UIElement -Element $Global:SyncHash.txtTotalScanned -Action {
                        $Global:SyncHash.txtTotalScanned.Text = $total
                    }
                    Update-UIElement -Element $Global:SyncHash.txtHealthy -Action {
                        $Global:SyncHash.txtHealthy.Text = $healthy
                    }
                    Update-UIElement -Element $Global:SyncHash.txtCritical -Action {
                        $Global:SyncHash.txtCritical.Text = $critical
                    }
                }
            
                Update-StatusBar -Message "Scan complete"
                Write-LogToUI -Message "Scan completed successfully" -Severity 'Success'
            }
        })
    
    # Load File button
    $Global:SyncHash.btnLoadFile.Add_Click({
            $dialog = New-Object Microsoft.Win32.OpenFileDialog
            $dialog.Filter = "CSV Files (*.csv)|*.csv|Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            $dialog.Title = "Select Target List"
        
            if ($dialog.ShowDialog()) {
                $filePath = $dialog.FileName
                Write-LogToUI -Message "Loading target list from: $filePath" -Severity 'Info'
                Update-StatusBar -Message "Importing targets..." -ShowProgress
            
                # Process asynchronously
                $bulkJob = Invoke-AsyncJob -ScriptBlock {
                    param($path, $config, $modulePath)
                
                    # Import modules
                    Import-Module "$modulePath\InputBroker.psm1" -Force
                    Import-Module "$modulePath\DataFetcher.psm1" -Force
                    Import-Module "$modulePath\TopologyDetector.psm1" -Force
                    Import-Module "$modulePath\Logging.psm1" -Force
                
                    # Import targets
                    $targets = Import-TargetList -FilePath $path -Config $config
                
                    if ($targets) {
                        # Fetch data
                        $results = Invoke-DataFetch -Targets $targets -Config $config
                        return $results
                    }
                
                    return $null
                
                } -Parameters @{
                    path       = $filePath
                    config     = $Global:Config
                    modulePath = $ModulePath
                }
            
                Write-LogToUI -Message "Bulk scan initiated. This may take several minutes..." -Severity 'Info'
            }
        })
    
    # Export button
    $Global:SyncHash.btnExport.Add_Click({
            if ($Global:SyncHash.dgResults.Items.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No results to export", "Export", 'OK', 'Information')
                return
            }
        
            $dialog = New-Object Microsoft.Win32.SaveFileDialog
            $dialog.Filter = "CSV Files (*.csv)|*.csv"
            $dialog.FileName = "EMS_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        
            if ($dialog.ShowDialog()) {
                $exportPath = $dialog.FileName
            
                try {
                    # Get results from grid
                    $results = @($Global:SyncHash.dgResults.Items)
                
                    # Export
                    Export-ScanResults -Results $results -OutputPath $exportPath
                
                    Write-LogToUI -Message "Report exported successfully to: $exportPath" -Severity 'Success'
                    [System.Windows.MessageBox]::Show("Export completed: $exportPath", "Success", 'OK', 'Information')
                
                }
                catch {
                    Write-LogToUI -Message "Export failed: $_" -Severity 'Error'
                    [System.Windows.MessageBox]::Show("Export failed: $_", "Error", 'OK', 'Error')
                }
            }
        })
    
    # Clear button
    $Global:SyncHash.btnClear.Add_Click({
            $Global:SyncHash.dgResults.Items.Clear()
            $Global:SyncHash.dgSystemHealth.Items.Clear()
            $Global:SyncHash.dgSecurity.Items.Clear()
            $Global:SyncHash.dgNetwork.Items.Clear()
            $Global:SyncHash.dgSoftware.Items.Clear()
            $Global:SyncHash.dgUserExperience.Items.Clear()
        
            $Global:SyncHash.txtTotalScanned.Text = "0"
            $Global:SyncHash.txtHealthy.Text = "0"
            $Global:SyncHash.txtCritical.Text = "0"
            $Global:SyncHash.txtInProgress.Text = "0"
        
            Write-LogToUI -Message "Results cleared" -Severity 'Info'
        })
}
#endregion

#region Main Application
function Start-EMSApplication {
    <#
    .SYNOPSIS
        Main application entry point
    #>
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Enterprise Endpoint Monitoring System  " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Initialize configuration
    Initialize-Configuration
    
    # Initialize runspace pool
    Initialize-RunspacePool -MinRunspaces 2 -MaxRunspaces 50
    
    # Load XAML
    $xamlPath = Join-Path $PSScriptRoot "MainWindow.xaml"
    
    if (-not (Test-Path $xamlPath)) {
        Write-Host "[ERROR] XAML file not found: $xamlPath" -ForegroundColor Red
        return
    }
    
    [xml]$xaml = Get-Content $xamlPath
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Global:SyncHash.Window = [Windows.Markup.XamlReader]::Load($reader)
    
    # Extract named elements
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
        $name = $_.Name
        if ($name) {
            $Global:SyncHash[$name] = $Global:SyncHash.Window.FindName($name)
        }
    }
    
    # Register event handlers
    Register-EventHandlers
    
    Write-Host "[INFO] UI initialized successfully" -ForegroundColor Green
    Write-Host "[INFO] Waiting for user authentication..." -ForegroundColor Yellow
    
    # Show window
    $Global:SyncHash.Window.ShowDialog() | Out-Null
    
    # Cleanup
    if ($Global:RunspacePool) {
        $Global:RunspacePool.Close()
        $Global:RunspacePool.Dispose()
    }
}
#endregion

# Start the application
Start-EMSApplication
