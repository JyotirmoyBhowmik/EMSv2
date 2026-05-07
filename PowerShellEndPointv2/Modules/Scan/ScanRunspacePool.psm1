<#
.SYNOPSIS
 EMS Scan Runspace Pool
.DESCRIPTION
 Centralized runspace pool to control concurrent scan execution
#>

# -------------------------
# Configuration
# -------------------------
$script:MaxRunspaces = 5   # adjust as per server capacity
$script:MinRunspaces = 1

# -------------------------
# Initialize Runspace Pool
# -------------------------
function Start-ScanRunspacePool {
    if ($script:RunspacePool) {
        return
    }

    Write-EMSLog -Message "Initializing scan runspace pool (Max=$script:MaxRunspaces)" -Category Scan

    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        $script:MinRunspaces,
        $script:MaxRunspaces
    )

    $pool.Open()
    $script:RunspacePool = $pool
}

# -------------------------
# Get Runspace Pool
# -------------------------
function Get-ScanRunspacePool {
    if (-not $script:RunspacePool) {
        Start-ScanRunspacePool
    }
    return $script:RunspacePool
}

# -------------------------
# Shutdown (Graceful)
# -------------------------
function Shutdown-ScanRunspacePool {
    if ($script:RunspacePool) {
        Write-EMSLog -Message "Shutting down scan runspace pool" -Category Scan
        $script:RunspacePool.Close()
        $script:RunspacePool.Dispose()
        $script:RunspacePool = $null
    }
}

Export-ModuleMember -Function @(
    'Start-ScanRunspacePool',
    'Get-ScanRunspacePool',
    'Shutdown-ScanRunspacePool'
)