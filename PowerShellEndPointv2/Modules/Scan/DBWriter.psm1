<#
.SYNOPSIS
    EMS Database Writer Helper
.DESCRIPTION
    Maps collector metrics to PostgreSQL tables.
#>

function Write-MetricsToDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TableName,
        
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Metrics
    )
    
    if (-not $Metrics -or $Metrics.Count -eq 0) { return }
    
    # Identify if it's an upsert table (Registry tables)
    $upsertTables = @('computers')
    $isUpsert = $TableName -in $upsertTables
    
    foreach ($metric in $Metrics) {
        $props = $metric.PSObject.Properties
        $cols = @()
        $vals = @()
        $params = @{}
        
        foreach ($prop in $props) {
            $cols += $prop.Name
            $vals += "@$($prop.Name)"
            $params[$prop.Name] = $prop.Value
        }
        
        $colStr = $cols -join ', '
        $valStr = $vals -join ', '
        
        $query = ""
        if ($isUpsert) {
            $updateSet = @()
            foreach ($col in $cols) {
                if ($col -ne 'computer_name') {
                    $updateSet += "$col = EXCLUDED.$col"
                }
            }
            $updateStr = $updateSet -join ', '
            
            $query = @"
INSERT INTO $TableName ($colStr) 
VALUES ($valStr) 
ON CONFLICT (computer_name) 
DO UPDATE SET $updateStr, updated_at = NOW()
"@
        }
        else {
            $query = "INSERT INTO $TableName ($colStr) VALUES ($valStr)"
        }
        
        try {
            Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
        }
        catch {
            Write-EMSLog -Message "Failed to write metric to $TableName: $($_.Exception.Message)" -Severity 'Error' -Category 'DBWriter'
        }
    }
    
    Write-EMSLog -Message "Written $($Metrics.Count) rows to $TableName" -Severity 'Info' -Category 'DBWriter'
}

Export-ModuleMember -Function Write-MetricsToDatabase
