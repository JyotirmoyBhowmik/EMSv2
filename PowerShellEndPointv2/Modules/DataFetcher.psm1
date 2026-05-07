<#
.SYNOPSIS
    Data fetching orchestration module

.DESCRIPTION
    Implements dual-queue processing with topology-aware throttling
#>

function Invoke-DataFetch {
    <#
    .SYNOPSIS
        Main orchestration function for endpoint diagnostics
    
    .PARAMETER Targets
        Array of topology-enriched target objects
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Array of complete diagnostic results
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Targets,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    Write-EMSLog -Message "Starting data fetch for $($Targets.Count) targets" -Severity 'Info' -Category 'DataFetch'
    
    # Split into queues
    $queues = Split-TargetsByTopology -Targets $Targets
    
    $results = @()
    
    # Process HO Queue (High concurrency)
    if ($queues.HOQueue.Count -gt 0) {
        Write-EMSLog -Message "Processing HO Queue: $($queues.HOQueue.Count) targets with throttle limit $($Config.Topology.HOThrottleLimit)" `
            -Severity 'Info' -Category 'DataFetch'
        
        $hoResults = Start-HOQueue -Targets $queues.HOQueue -Config $Config
        $results += $hoResults
    }
    
    # Process Remote Queue (Low concurrency)
    if ($queues.RemoteQueue.Count -gt 0) {
        Write-EMSLog -Message "Processing Remote Queue: $($queues.RemoteQueue.Count) targets with throttle limit $($Config.Topology.RemoteThrottleLimit)" `
            -Severity 'Info' -Category 'DataFetch'
        
        $remoteResults = Start-MPLSQueue -Targets $queues.RemoteQueue -Config $Config
        $results += $remoteResults
    }
    
    Write-EMSLog -Message "Data fetch complete. Processed $($results.Count) endpoints" -Severity 'Success' -Category 'DataFetch'
    
    return $results
}

function Start-HOQueue {
    <#
    .SYNOPSIS
        Processes Head Office targets with high concurrency
    #>
    param(
        [array]$Targets,
        [PSCustomObject]$Config
    )
    
    $scriptBlock = {
        param($hostname, $criticalServices)
        
        # Import diagnostic modules
        $modulePath = "$using:PSScriptRoot"
        Import-Module "$modulePath\Diagnostics\SystemHealth.psm1" -Force
        Import-Module "$modulePath\Diagnostics\SecurityPosture.psm1" -Force
        
        try {
            $results = @{
                Hostname     = $hostname
                IP           = (Resolve-DnsName $hostname -Type A -ErrorAction Stop)[0].IPAddress
                Topology     = 'HO'
                SystemHealth = @()
                Security     = @()
                Status       = 'InProgress'
                LastScan     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            # Run diagnostics
            $results.SystemHealth = Invoke-SystemHealthChecks -ComputerName $hostname -CriticalServices $criticalServices
            $results.Security = Invoke-SecurityChecks -ComputerName $hostname
            
            # Calculate health score
            $criticalCount = ($results.SystemHealth + $results.Security | Where-Object { $_.Status -eq 'Critical' -or $_.Compliance -eq 'Critical' }).Count
            $warningCount = ($results.SystemHealth + $results.Security | Where-Object { $_.Status -eq 'Warning' -or $_.Compliance -eq 'Warning' }).Count
            
            $healthScore = 100 - ($criticalCount * 15) - ($warningCount * 5)
            if ($healthScore -lt 0) { $healthScore = 0 }
            
            $results.HealthScore = $healthScore
            $results.CriticalAlerts = $criticalCount
            $results.Status = 'Complete'
            
            return $results
            
        }
        catch {
            return @{
                Hostname = $hostname
                IP       = 'Unknown'
                Topology = 'HO'
                Status   = 'Error'
                Error    = $_.Exception.Message
                LastScan = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    }
    
    # Execute in parallel
    $jobs = @()
    foreach ($target in $Targets) {
        $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $target.Hostname, $Config.Remediation.CriticalServices
    }
    
    # Wait for completion with progress
    $completed = 0
    while ($jobs | Where-Object { $_.State -eq 'Running' }) {
        $completedJobs = $jobs | Where-Object { $_.State -eq 'Completed' }
        $newCompleted = $completedJobs.Count - $completed
        
        if ($newCompleted -gt 0) {
            $completed = $completedJobs.Count
            Write-EMSLog -Message "HO Queue progress: $completed / $($jobs.Count) complete" -Severity 'Info' -Category 'DataFetch'
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    # Collect results
    $results = $jobs | Receive-Job
    $jobs | Remove-Job
    
    # Save diagnostics to granular metric tables
    foreach ($result in $results) {
        if ($result.Status -eq 'Complete') {
            Save-DiagnosticsToMetrics -ScanResult $result -Config $Config
        }
    }
    
    return $results
}

function Save-DiagnosticsToMetrics {
    <#
    .SYNOPSIS
        Saves diagnostic scan results to granular metric tables
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$ScanResult,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        # Import metrics module
        Import-Module "$PSScriptRoot\Database\MetricsData.psm1" -Force
        
        $computerName = $ScanResult.Hostname
        
        # Register/update computer
        Register-Computer -ComputerName $computerName `
            -IPAddress $ScanResult.IP `
            -OperatingSystem "Windows" `
            -IsDomainJoined $true `
            -ComputerType "Desktop"
        
        # Extract and save metrics from diagnostic results
        foreach ($diagnostic in $ScanResult.SystemHealth) {
            switch ($diagnostic.CheckName) {
                "CPU_Usage" {
                    if ($diagnostic.Details) {
                        Save-CPUMetric -ComputerName $computerName `
                            -UsagePercent ([decimal]$diagnostic.Details.UsagePercent) `
                            -CoreCount $diagnostic.Details.CoreCount `
                            -LogicalProcessors $diagnostic.Details.LogicalProcessors `
                            -ProcessorName $diagnostic.Details.ProcessorName `
                            -ProcessorSpeedMHz $diagnostic.Details.SpeedMHz
                    }
                }
                "Memory_Usage" {
                    if ($diagnostic.Details) {
                        Save-MemoryMetric -ComputerName $computerName `
                            -TotalGB ([decimal]$diagnostic.Details.TotalGB) `
                            -AvailableGB ([decimal]$diagnostic.Details.AvailableGB) `
                            -UsedGB ([decimal]$diagnostic.Details.UsedGB) `
                            -UsagePercent ([decimal]$diagnostic.Details.UsagePercent)
                    }
                }
                "Disk_Space" {
                    if ($diagnostic.Details -and $diagnostic.Details.Disks) {
                        Save-DiskMetrics -ComputerName $computerName `
                            -Disks $diagnostic.Details.Disks
                    }
                }
            }
        }
        
        # Save security metrics
        foreach ($diagnostic in $ScanResult.Security) {
            switch ($diagnostic.CheckName) {
                "Windows_Updates" {
                    if ($diagnostic.Details) {
                        Save-WindowsUpdateMetric -ComputerName $computerName `
                            -TotalUpdates $diagnostic.Details.TotalUpdates `
                            -PendingUpdates $diagnostic.Details.PendingUpdates `
                            -FailedUpdates $diagnostic.Details.FailedUpdates `
                            -LastUpdateDate $diagnostic.Details.LastUpdateDate `
                            -AutoUpdateEnabled $diagnostic.Details.AutoUpdateEnabled `
                            -RebootRequired $diagnostic.Details.RebootRequired
                    }
                }
                "Antivirus_Status" {
                    if ($diagnostic.Details) {
                        Save-AntivirusMetric -ComputerName $computerName `
                            -AVProduct $diagnostic.Details.Product `
                            -AVVersion $diagnostic.Details.Version `
                            -DefinitionsVersion $diagnostic.Details.DefinitionsVersion `
                            -DefinitionsDate $diagnostic.Details.DefinitionsDate `
                            -RealTimeProtection $diagnostic.Details.RealTimeProtection `
                            -LastScanDate $diagnostic.Details.LastScanDate `
                            -ThreatCount $diagnostic.Details.ThreatCount
                    }
                }
            }
        }
        
        Write-EMSLog -Message "Saved metrics for $computerName to granular tables" -Severity 'Success' -Category 'Metrics'
    }
    catch {
        Write-EMSLog -Message "Error saving metrics for $($ScanResult.Hostname): $_" -Severity 'Error' -Category 'Metrics'
    }
}

function Start-MPLSQueue {
    <#
    .SYNOPSIS
        Processes Remote/MPLS targets with throttling
    #>
    param(
        [array]$Targets,
        [PSCustomObject]$Config
    )
    
    $results = @()
    $batchSize = $Config.Topology.RemoteThrottleLimit
    $batches = [Math]::Ceiling($Targets.Count / $batchSize)
    
    for ($i = 0; $i -lt $batches; $i++) {
        $batchStart = $i * $batchSize
        $batchTargets = $Targets[$batchStart..($batchStart + $batchSize - 1)]
        
        Write-EMSLog -Message "Processing MPLS batch $($i + 1) of $batches ($($batchTargets.Count) targets)" `
            -Severity 'Info' -Category 'DataFetch'
        
        $scriptBlock = {
            param($hostname, $criticalServices)
            
            # Import diagnostic modules
            $modulePath = "$using:PSScriptRoot"
            Import-Module "$modulePath\Diagnostics\SystemHealth.psm1" -Force
            Import-Module "$modulePath\Diagnostics\SecurityPosture.psm1" -Force
            
            try {
                # Create optimized CIM session
                $sessionOption = New-CimSessionOption -Protocol Wsman
                $cimSession = New-CimSession -ComputerName $hostname -OperationTimeoutSec 15 -SessionOption $sessionOption -ErrorAction Stop
                
                $results = @{
                    Hostname     = $hostname
                    IP           = (Resolve-DnsName $hostname -Type A -ErrorAction Stop)[0].IPAddress
                    Topology     = 'Remote'
                    SystemHealth = @()
                    Security     = @()
                    Status       = 'InProgress'
                    LastScan     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                # Run diagnostics using CIM session
                $results.SystemHealth = Invoke-SystemHealthChecks -CimSession $cimSession -CriticalServices $criticalServices
                $results.Security = Invoke-SecurityChecks -ComputerName $hostname -CimSession $cimSession
                
                # Calculate health score
                $criticalCount = ($results.SystemHealth + $results.Security | Where-Object { $_.Status -eq 'Critical' -or $_.Compliance -eq 'Critical' }).Count
                $warningCount = ($results.SystemHealth + $results.Security | Where-Object { $_.Status -eq 'Warning' -or $_.Compliance -eq 'Warning' }).Count
                
                $healthScore = 100 - ($criticalCount * 15) - ($warningCount * 5)
                if ($healthScore -lt 0) { $healthScore = 0 }
                
                $results.HealthScore = $healthScore
                $results.CriticalAlerts = $criticalCount
                $results.Status = 'Complete'
                
                # Cleanup
                Remove-CimSession -CimSession $cimSession
                
                return $results
                
            }
            catch {
                return @{
                    Hostname = $hostname
                    IP       = 'Unknown'
                    Topology = 'Remote'
                    Status   = 'Error'
                    Error    = $_.Exception.Message
                    LastScan = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
            }
        }
        
        # Execute batch
        $batchJobs = @()
        foreach ($target in $batchTargets) {
            $batchJobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $target.Hostname, $Config.Remediation.CriticalServices
        }
        
        # Wait for batch completion
        $batchJobs | Wait-Job | Out-Null
        $batchResults = $batchJobs | Receive-Job
        $batchJobs | Remove-Job
        
        $results += $batchResults
        
        # Save batch results to granular metrics
        foreach ($result in $batchResults) {
            if ($result.Status -eq 'Complete') {
                Save-DiagnosticsToMetrics -ScanResult $result -Config $Config
            }
        }
        
        # Delay between batches to prevent MPLS saturation
        if ($i -lt ($batches - 1)) {
            Write-EMSLog -Message "Delaying $($Config.BulkProcessing.DelayBetweenRemoteBatchesSeconds)s before next MPLS batch" `
                -Severity 'Info' -Category 'DataFetch'
            Start-Sleep -Seconds $Config.BulkProcessing.DelayBetweenRemoteBatchesSeconds
        }
    }
    
    return $results
}

Export-ModuleMember -Function Invoke-DataFetch, Start-HOQueue, Start-MPLSQueue, Save-DiagnosticsToMetrics
