<#
.SYNOPSIS
    OSInfo Collector
.DESCRIPTION
    Collects core system and OS information to populate the computers table.
#>

function Invoke-OSInfoCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 15
    )
    
    $results = @{
        ScanId   = $ScanId
        Success  = $false
        Metrics  = @()
        Errors   = @()
        Duration = 0
    }
    
    $sw = [Diagnostics.Stopwatch]::StartNew()
    
    try {
        $cim = if ($Session.Protocol -eq 'CIM') { $Session.Session } else { $null }
        
        # 1. Get Operating System Info
        $os = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_OperatingSystem -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
        }
        
        # 2. Get Computer System Info
        $cs = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_ComputerSystem -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        }
        
        # 3. Get BIOS Info (for Serial Number)
        $bios = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_BIOS -ErrorAction SilentlyContinue
        } else {
            Get-WmiObject -Class Win32_BIOS -ComputerName $ComputerName -ErrorAction SilentlyContinue
        }
        
        # 4. Get Network Info (for IP/MAC)
        $net = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
        } else {
            Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $ComputerName -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
        }
        
        $primaryNet = $net | Sort-Object IPConnectionMetric | Select-Object -First 1
        
        # Determine Computer Type (Heuristic)
        $type = 'Desktop'
        if ($cs.Model -match 'ProLiant|PowerEdge|UCS') { $type = 'Server' }
        elseif ($cs.Model -match 'Laptop|Notebook|ThinkPad|Latitude') { $type = 'Laptop' }
        
        $results.Metrics += [PSCustomObject]@{
            computer_name    = $ComputerName
            ip_address       = $primaryNet.IPAddress[0]
            mac_address      = $primaryNet.MACAddress
            operating_system = $os.Caption
            os_version       = $os.Version
            os_build         = $os.BuildNumber
            domain           = $cs.Domain
            is_domain_joined = $cs.PartOfDomain
            computer_type    = $type
            manufacturer     = $cs.Manufacturer
            model            = $cs.Model
            serial_number    = if ($bios) { $bios.SerialNumber } else { 'Unknown' }
        }

        # Also populate V3 scan_inventory_results for backward compatibility
        try {
            $invParams = @{
                id = $ScanId
                cn = $ComputerName
                mf = $cs.Manufacturer
                md = $cs.Model
                os = $os.Caption
                ov = $os.Version
                ob = $os.BuildNumber
            }
            Invoke-PGQuery -NonQuery -Query @"
                INSERT INTO scan_inventory_results (scan_id, computer_name, manufacturer, model, os_edition, os_version, os_build, lastchecked)
                VALUES (@id, @cn, @mf, @md, @os, @ov, @ob, NOW())
                ON CONFLICT (scan_id) DO UPDATE SET 
                    computer_name = EXCLUDED.computer_name,
                    manufacturer = EXCLUDED.manufacturer,
                    model = EXCLUDED.model,
                    os_edition = EXCLUDED.os_edition,
                    os_version = EXCLUDED.os_version,
                    os_build = EXCLUDED.os_build,
                    lastchecked = NOW();
"@ -Parameters $invParams
        } catch {
            Write-EMSLog -Message "Failed to update scan_inventory_results: $($_.Exception.Message)" -Severity 'Warning' -Category 'OSInfo'
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[OSInfo] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-OSInfoCollection
