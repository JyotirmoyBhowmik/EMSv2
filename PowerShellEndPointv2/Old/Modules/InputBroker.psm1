<#
.SYNOPSIS
    Input routing and broker module

.DESCRIPTION
    Routes different input types (hostname, IP, user ID, or file) to appropriate handlers
#>

function Invoke-InputRouter {
    <#
    .SYNOPSIS
        Main entry point for input routing
    
    .PARAMETER Input
        User input (hostname, IP, UserID, or file path)
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Array of topology-enriched target objects
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Input,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    Write-EMSLog -Message "Processing input: $Input" -Severity 'Info' -Category 'InputBroker'
    
    # Determine input type
    if (Test-Path $Input -ErrorAction SilentlyContinue) {
        # File path
        Write-EMSLog -Message "Input identified as file path" -Severity 'Info' -Category 'InputBroker'
        return Import-TargetList -FilePath $Input -Config $Config
        
    }
    elseif ($Input -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        # IP Address
        Write-EMSLog -Message "Input identified as IP address" -Severity 'Info' -Category 'InputBroker'
        $topology = Get-TargetTopology -Target $Input -Config $Config.Topology
        return @($topology)
        
    }
    elseif ($Input -match '^[a-zA-Z0-9\-]+$') {
        # Could be hostname or username
        # Try as hostname first
        try {
            $dnsResult = Resolve-DnsName -Name $Input -Type A -ErrorAction Stop
            Write-EMSLog -Message "Input identified as hostname" -Severity 'Info' -Category 'InputBroker'
            $topology = Get-TargetTopology -Target $Input -Config $Config.Topology
            return @($topology)
        }
        catch {
            # Not a valid hostname, treat as User ID
            Write-EMSLog -Message "Input identified as User ID" -Severity 'Info' -Category 'InputBroker'
            return Resolve-UserToEndpoint -UserID $Input -Config $Config
        }
        
    }
    else {
        # Possibly User ID with domain (domain\user or user@domain)
        Write-EMSLog -Message "Input identified as qualified User ID" -Severity 'Info' -Category 'InputBroker'
        return Resolve-UserToEndpoint -UserID $Input -Config $Config
    }
}

function Import-TargetList {
    <#
    .SYNOPSIS
        Imports and validates targets from CSV file
    
    .PARAMETER FilePath
        Path to CSV file
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Array of validated and topology-enriched targets
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        Write-EMSLog -Message "Importing target list from: $FilePath" -Severity 'Info' -Category 'BulkImport'
        
        # Import CSV
        $rawData = Import-Csv -Path $FilePath -ErrorAction Stop
        
        # Detect column name (flexible: Hostname, ComputerName, Target, IP, etc.)
        $targetColumn = $null
        $possibleColumns = @('Hostname', 'ComputerName', 'Target', 'IP', 'Computer', 'Name')
        
        foreach ($col in $possibleColumns) {
            if ($rawData[0].PSObject.Properties.Name -contains $col) {
                $targetColumn = $col
                break
            }
        }
        
        if (-not $targetColumn) {
            # Use first column
            $targetColumn = $rawData[0].PSObject.Properties.Name[0]
            Write-Warning "No standard column found. Using first column: $targetColumn"
        }
        
        Write-EMSLog -Message "Using column '$targetColumn' for target names" -Severity 'Info' -Category 'BulkImport'
        
        # Extract and sanitize targets
        $targets = @()
        $lineNumber = 2 # Start at 2 (header is line 1)
        
        foreach ($row in $rawData) {
            $targetValue = $row.$targetColumn
            
            # Sanitize
            $targetValue = $targetValue.Trim()
            
            if ([string]::IsNullOrWhiteSpace($targetValue)) {
                Write-Warning "Line $lineNumber : Empty target value, skipping"
                $lineNumber++
                continue
            }
            
            # Validate format (basic DNS/IP validation)
            if ($targetValue -match '^[a-zA-Z0-9\-\.]+$') {
                $targets += $targetValue
            }
            else {
                Write-Warning "Line $lineNumber : Invalid target format '$targetValue', skipping"
            }
            
            $lineNumber++
        }
        
        Write-EMSLog -Message "Imported $($targets.Count) valid targets from CSV" -Severity 'Success' -Category 'BulkImport'
        
        # Pre-flight AD validation
        if ($Config.BulkProcessing.EnableBulkImport) {
            $validatedTargets = Test-TargetsAgainstAD -Targets $targets
        }
        else {
            $validatedTargets = $targets
        }
        
        # Enrich with topology data
        $enrichedTargets = @()
        foreach ($target in $validatedTargets) {
            $topology = Get-TargetTopology -Target $target -Config $Config.Topology
            
            if ($topology) {
                $enrichedTargets += $topology
            }
        }
        
        Write-EMSLog -Message "Topology detection complete: $($enrichedTargets.Count) targets enriched" -Severity 'Success' -Category 'BulkImport'
        
        return $enrichedTargets
        
    }
    catch {
        Write-EMSLog -Message "Failed to import target list: $_" -Severity 'Error' -Category 'BulkImport'
        throw
    }
}

function Test-TargetsAgainstAD {
    <#
    .SYNOPSIS
        Validates targets against Active Directory
    
    .PARAMETER Targets
        Array of target hostnames
    
    .RETURNS
        Array of valid targets (exist in AD and are enabled)
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Targets
    )
    
    try {
        Write-EMSLog -Message "Performing AD validation for $($Targets.Count) targets" -Severity 'Info' -Category 'Validation'
        
        # Build AD cache (much faster than individual queries)
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        
        if (-not (Get-Module ActiveDirectory)) {
            Write-Warning "ActiveDirectory module not available. Skipping AD validation."
            return $Targets
        }
        
        Write-EMSLog -Message "Caching AD computer objects..." -Severity 'Info' -Category 'Validation'
        
        $adCache = @{}
        Get-ADComputer -Filter { Enabled -eq $true } -Properties Name, DNSHostName | ForEach-Object {
            $adCache[$_.Name.ToLower()] = $true
            if ($_.DNSHostName) {
                $adCache[$_.DNSHostName.ToLower()] = $true
            }
        }
        
        Write-EMSLog -Message "AD cache built with $($adCache.Count) entries" -Severity 'Success' -Category 'Validation'
        
        # Validate each target
        $validTargets = @()
        $invalidTargets = @()
        
        foreach ($target in $Targets) {
            $key = $target.ToLower().Split('.')[0] # Remove domain suffix for matching
            
            if ($adCache.ContainsKey($key)) {
                $validTargets += $target
            }
            else {
                $invalidTargets += $target
                Write-Warning "Target not found or disabled in AD: $target"
            }
        }
        
        Write-EMSLog -Message "Validation complete: $($validTargets.Count) valid, $($invalidTargets.Count) invalid" -Severity 'Info' -Category 'Validation'
        
        if ($invalidTargets.Count -gt 0) {
            Write-EMSLog -Message "Invalid targets: $($invalidTargets -join ', ')" -Severity 'Warning' -Category 'Validation'
        }
        
        return $validTargets
        
    }
    catch {
        Write-EMSLog -Message "AD validation error: $_" -Severity 'Error' -Category 'Validation'
        return $Targets # Return original list if validation fails
    }
}

function Split-TargetsByTopology {
    <#
    .SYNOPSIS
        Splits targets into HO and Remote queues
    
    .PARAMETER Targets
        Array of topology-enriched target objects
    
    .RETURNS
        Hashtable with HOQueue and RemoteQueue
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Targets
    )
    
    $queues = @{
        HOQueue      = @($Targets | Where-Object Topology -eq 'HO')
        RemoteQueue  = @($Targets | Where-Object Topology -eq 'Remote')
        UnknownQueue = @($Targets | Where-Object Topology -eq 'Unknown')
    }
    
    Write-EMSLog -Message "Queue distribution: HO=$($queues.HOQueue.Count), Remote=$($queues.RemoteQueue.Count), Unknown=$($queues.UnknownQueue.Count)" `
        -Severity 'Info' -Category 'Orchestration'
    
    return $queues
}

Export-ModuleMember -Function Invoke-InputRouter, Import-TargetList, Test-TargetsAgainstAD, Split-TargetsByTopology
