<#
    Get-ConnectorHealth.psm1
    EMS v3.0 — Connector Health Monitoring Module
    Tests connectivity to all external system dependencies.
#>

function Get-AllConnectorHealth {
    [CmdletBinding()]
    param()

    $results = @()

    # 1. PostgreSQL Database
    $dbHealth = Test-DatabaseConnector
    $results += $dbHealth

    # 2. Active Directory
    $adHealth = Test-ADConnector
    $results += $adHealth

    # 3. SMTP (if configured)
    if ($Global:EMSConfig.SMTP -and $Global:EMSConfig.SMTP.Server) {
        $smtpHealth = Test-SMTPConnector
        $results += $smtpHealth
    } else {
        $results += [pscustomobject]@{
            Connector  = 'SMTP'
            Status     = 'Not Configured'
            Latency    = $null
            Message    = 'SMTP not configured in EMSConfig.json'
            LastCheck  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    # 4. WinRM
    $winrmHealth = Test-WinRMConnector
    $results += $winrmHealth

    return $results
}

function Test-DatabaseConnector {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-PGQuery -Query "SELECT 1 AS test;"
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'PostgreSQL'
            Status    = 'Healthy'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = "Connected to $($Global:EMSConfig.Database.DatabaseName)"
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    catch {
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'PostgreSQL'
            Status    = 'Down'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = $_.Exception.Message
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
}

function Test-ADConnector {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $domain = $Global:EMSConfig.Authentication.Providers |
            Where-Object { $_.Name -eq 'ActiveDirectory' -and $_.Enabled } |
            Select-Object -First 1

        if (-not $domain) {
            $sw.Stop()
            return [pscustomobject]@{
                Connector = 'Active Directory'
                Status    = 'Not Configured'
                Latency   = $null
                Message   = 'No AD provider enabled'
                LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
        }

        $dc = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        $sw.Stop()

        return [pscustomobject]@{
            Connector = 'Active Directory'
            Status    = 'Healthy'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = "Domain: $($dc.Name), DC: $($dc.PdcRoleOwner)"
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    catch {
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'Active Directory'
            Status    = 'Down'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = $_.Exception.Message
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
}

function Test-SMTPConnector {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $smtp = $Global:EMSConfig.SMTP
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($smtp.Server, $(if ($smtp.Port) { $smtp.Port } else { 25 }))
        $tcpClient.Close()
        $sw.Stop()

        return [pscustomobject]@{
            Connector = 'SMTP'
            Status    = 'Healthy'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = "Connected to $($smtp.Server):$($smtp.Port)"
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    catch {
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'SMTP'
            Status    = 'Down'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = $_.Exception.Message
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
}

function Test-WinRMConnector {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Test-WSMan -ComputerName localhost -ErrorAction Stop
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'WinRM'
            Status    = 'Healthy'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = "WS-Management operational on localhost"
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
    catch {
        $sw.Stop()
        return [pscustomobject]@{
            Connector = 'WinRM'
            Status    = 'Down'
            Latency   = "$($sw.ElapsedMilliseconds)ms"
            Message   = $_.Exception.Message
            LastCheck = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
    }
}

Export-ModuleMember -Function Get-AllConnectorHealth, Test-DatabaseConnector, Test-ADConnector, Test-SMTPConnector, Test-WinRMConnector
