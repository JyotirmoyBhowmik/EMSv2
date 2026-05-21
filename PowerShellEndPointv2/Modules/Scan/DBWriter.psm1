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
    
    # Base column info on the first metric
    $firstMetric = $Metrics[0]
    $props = $firstMetric.PSObject.Properties
    $cols = @()
    foreach ($prop in $props) {
        $cols += $prop.Name
    }

    $colStr = $cols -join ', '

    $updateStr = ""
    if ($isUpsert) {
        $updateSet = @()
        foreach ($col in $cols) {
            if ($col -ne 'computer_name') {
                $updateSet += "$col = EXCLUDED.$col"
            }
        }
        $updateStr = $updateSet -join ', '
    }

    # PostgreSQL limits query parameters to 65535.
    # Calculate batch size dynamically, up to a reasonable max limit like 1000.
    $maxParams = 65000
    $columnsCount = $cols.Count
    $batchSize = [Math]::Floor($maxParams / $columnsCount)
    if ($batchSize -gt 1000) {
        $batchSize = 1000
    }
    if ($batchSize -le 0) { $batchSize = 1 }

    for ($i = 0; $i -lt $Metrics.Count; $i += $batchSize) {
        $endIdx = [Math]::Min($i + $batchSize - 1, $Metrics.Count - 1)
        
        # Handle single element array slicing carefully
        if ($i -eq $endIdx) {
            $batch = @($Metrics[$i])
        } else {
            $batch = $Metrics[$i..$endIdx]
        }
        
        $valStrings = @()
        $params = @{}
        $rowIndex = 0
        
        foreach ($metric in $batch) {
            $rowVals = @()
            foreach ($col in $cols) {
                $paramName = "${col}_${rowIndex}"
                $rowVals += "@$paramName"

                # Fetch value
                $val = $null
                if ($metric.PSObject.Properties.Match($col).Count -gt 0) {
                    $val = $metric.$col
                }
                $params[$paramName] = $val
            }
            $valStrings += "($($rowVals -join ', '))"
            $rowIndex++
        }

        $allValsStr = $valStrings -join ', '

        $query = ""
        if ($isUpsert) {
            $query = "INSERT INTO $TableName ($colStr) VALUES $allValsStr ON CONFLICT (computer_name) DO UPDATE SET $updateStr, updated_at = NOW()"
        }
        else {
            $query = "INSERT INTO $TableName ($colStr) VALUES $allValsStr"
        }
        
        try {
            Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
        }
        catch {
            Write-EMSLog -Message "Failed to write metric batch to $($TableName): $($_.Exception.Message)" -Severity 'Error' -Category 'DBWriter'
        }
    }
    
    Write-EMSLog -Message "Written $($Metrics.Count) rows to $TableName" -Severity 'Info' -Category 'DBWriter'
}

Export-ModuleMember -Function Write-MetricsToDatabase
