<#
.SYNOPSIS
    Export and reporting module

.DESCRIPTION
    Handles CSV export and compliance reporting
#>

function Export-ScanResults {
    <#
    .SYNOPSIS
        Exports scan results to CSV format
    
    .PARAMETER Results
        Array of scan result objects
    
    .PARAMETER OutputPath
        Path for output CSV file
    
    .RETURNS
        Path to exported file
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Results,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    try {
        Write-EMSLog -Message "Exporting $($Results.Count) results to $OutputPath" -Severity 'Info' -Category 'Export'
        
        # Flatten results for CSV export
        $exportData = @()
        
        foreach ($result in $Results) {
            $exportData += [PSCustomObject]@{
                Hostname       = $result.Hostname
                IPAddress      = $result.IP
                Topology       = $result.Topology
                HealthScore    = $result.HealthScore
                CriticalAlerts = $result.CriticalAlerts
                Status         = $result.Status
                LastScan       = $result.LastScan
                SystemHealth   = ($result.SystemHealth | Where-Object { $_.Status -ne 'OK' } | ForEach-Object { "$($_.Check): $($_.Value)" }) -join '; '
                SecurityIssues = ($result.Security | Where-Object { $_.Compliance -ne 'OK' } | ForEach-Object { "$($_.Check): $($_.Result)" }) -join '; '
            }
        }
        
        # Export to CSV
        $exportData | Export-Csv -Path $OutputPath -NoTypeInformation
        
        Write-EMSLog -Message "Export completed successfully: $OutputPath" -Severity 'Success' -Category 'Export'
        
        return $OutputPath
        
    }
    catch {
        Write-EMSLog -Message "Export failed: $_" -Severity 'Error' -Category 'Export'
        throw
    }
}

function New-ComplianceReport {
    <#
    .SYNOPSIS
        Generates a compliance summary report
    
    .PARAMETER Results
        Array of scan result objects
    
    .RETURNS
        Compliance summary object
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Results
    )
    
    try {
        $totalScanned = $Results.Count
        $completed = ($Results | Where-Object Status -eq 'Complete').Count
        $errors = ($Results | Where-Object Status -eq 'Error').Count
        
        $healthyCount = ($Results | Where-Object { $_.HealthScore -ge 80 }).Count
        $warningCount = ($Results | Where-Object { $_.HealthScore -ge 50 -and $_.HealthScore -lt 80 }).Count
        $criticalCount = ($Results | Where-Object { $_.HealthScore -lt 50 }).Count
        
        $totalCriticalAlerts = ($Results | Measure-Object -Property CriticalAlerts -Sum).Sum
        
        $avgHealthScore = [Math]::Round(($Results | Where-Object HealthScore | Measure-Object -Property HealthScore -Average).Average, 1)
        
        $report = [PSCustomObject]@{
            GeneratedAt         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            TotalScanned        = $totalScanned
            Completed           = $completed
            Errors              = $errors
            HealthyEndpoints    = $healthyCount
            WarningEndpoints    = $warningCount
            CriticalEndpoints   = $criticalCount
            TotalCriticalAlerts = $totalCriticalAlerts
            AverageHealthScore  = $avgHealthScore
            ComplianceRate      = [Math]::Round(($healthyCount / $totalScanned) * 100, 1)
        }
        
        Write-EMSLog -Message "Compliance report generated: $($report.ComplianceRate)% compliant, Avg Health: $avgHealthScore" `
            -Severity 'Info' -Category 'Reporting'
        
        return $report
        
    }
    catch {
        Write-EMSLog -Message "Failed to generate compliance report: $_" -Severity 'Error' -Category 'Reporting'
        throw
    }
}

Export-ModuleMember -Function Export-ScanResults, New-ComplianceReport
