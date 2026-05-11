<#
.SYNOPSIS
    Interactive remediation framework

.DESCRIPTION
    Provides context-aware automated fixes with RBAC and audit logging
#>

function Invoke-ServiceRemediation {
    <#
    .SYNOPSIS
        Restarts or starts a Windows service
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter(Mandatory)]
        [string]$ServiceName,
        
        [ValidateSet('Start', 'Restart', 'Stop')]
        [string]$Action = 'Start'
    )
    
    # Check authorization
    if (-not (Test-RemediationAuthorization)) {
        Write-EMSLog -Message "Remediation blocked: User not authorized" -Severity 'Error' -Category 'Remediation'
        return $false
    }
    
    try {
        Write-EMSLog -Message "Executing $Action on service '$ServiceName' at $ComputerName" -Severity 'Info' -Category 'Remediation' -Target $ComputerName
        
        $scriptBlock = switch ($Action) {
            'Start' { { param($svc) Start-Service -Name $svc -ErrorAction Stop } }
            'Restart' { { param($svc) Restart-Service -Name $svc -Force -ErrorAction Stop } }
            'Stop' { { param($svc) Stop-Service -Name $svc -Force -ErrorAction Stop } }
        }
        
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $ServiceName -ErrorAction Stop
        
        Write-EMSLog -Message "Service $Action successful: $ServiceName on $ComputerName" -Severity 'Success' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action "Service$Action" -Target $ComputerName -Details "Service: $ServiceName" -Result 'Success'
        
        return $true
        
    }
    catch {
        Write-EMSLog -Message "Service $Action failed: $_" -Severity 'Error' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action "Service$Action" -Target $ComputerName -Details "Service: $ServiceName, Error: $_" -Result 'Failed'
        
        return $false
    }
}

function Invoke-ProcessRemediation {
    <#
    .SYNOPSIS
        Terminates a process
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter(Mandatory)]
        [int]$ProcessId,
        
        [string]$Reason = 'High resource usage'
    )
    
    # Check authorization
    if (-not (Test-RemediationAuthorization)) {
        Write-EMSLog -Message "Remediation blocked: User not authorized" -Severity 'Error' -Category 'Remediation'
        return $false
    }
    
    try {
        Write-EMSLog -Message "Terminating process ID $ProcessId on $ComputerName (Reason: $Reason)" `
            -Severity 'Info' -Category 'Remediation' -Target $ComputerName
        
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($processId)
            Stop-Process -Id $processId -Force -ErrorAction Stop
        } -ArgumentList $ProcessId -ErrorAction Stop
        
        Write-EMSLog -Message "Process termination successful: PID $ProcessId on $ComputerName" `
            -Severity 'Success' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action 'KillProcess' -Target $ComputerName -Details "PID: $ProcessId, Reason: $Reason" -Result 'Success'
        
        return $true
        
    }
    catch {
        Write-EMSLog -Message "Process termination failed: $_" -Severity 'Error' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action 'KillProcess' -Target $ComputerName -Details "PID: $ProcessId, Error: $_" -Result 'Failed'
        
        return $false
    }
}

function Invoke-DiskRemediation {
    <#
    .SYNOPSIS
        Performs disk cleanup operations
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [ValidateSet('ClearTemp', 'CleanMgr', 'ClearRecycleBin')]
        [string]$Action = 'ClearTemp'
    )
    
    # Check authorization
    if (-not (Test-RemediationAuthorization)) {
        Write-EMSLog -Message "Remediation blocked: User not authorized" -Severity 'Error' -Category 'Remediation'
        return $false
    }
    
    try {
        Write-EMSLog -Message "Executing disk cleanup '$Action' on $ComputerName" -Severity 'Info' -Category 'Remediation' -Target $ComputerName
        
        $scriptBlock = switch ($Action) {
            'ClearTemp' {
                {
                    $tempPaths = @($env:TEMP, 'C:\Windows\Temp', 'C:\Windows\SoftwareDistribution\Download')
                    $freedSpace = 0
                    
                    foreach ($path in $tempPaths) {
                        if (Test-Path $path) {
                            $before = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                            Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                            $after = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                            $freedSpace += ($before - $after)
                        }
                    }
                    
                    return [Math]::Round($freedSpace / 1GB, 2)
                }
            }
            'CleanMgr' {
                {
                    Start-Process cleanmgr.exe -ArgumentList '/sagerun:1' -Wait -NoNewWindow
                    return 'Completed'
                }
            }
            'ClearRecycleBin' {
                {
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    return 'Completed'
                }
            }
        }
        
        $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ErrorAction Stop
        
        Write-EMSLog -Message "Disk cleanup successful: $Action on $ComputerName (Freed: $result GB)" `
            -Severity 'Success' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action "DiskCleanup_$Action" -Target $ComputerName -Details "Result: $result" -Result 'Success'
        
        return $true
        
    }
    catch {
        Write-EMSLog -Message "Disk cleanup failed: $_" -Severity 'Error' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action "DiskCleanup_$Action" -Target $ComputerName -Details "Error: $_" -Result 'Failed'
        
        return $false
    }
}

function Invoke-GPORemediation {
    <#
    .SYNOPSIS
        Forces Group Policy update
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName
    )
    
    # Check authorization
    if (-not (Test-RemediationAuthorization)) {
        Write-EMSLog -Message "Remediation blocked: User not authorized" -Severity 'Error' -Category 'Remediation'
        return $false
    }
    
    try {
        Write-EMSLog -Message "Forcing GPO update on $ComputerName" -Severity 'Info' -Category 'Remediation' -Target $ComputerName
        
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            gpupdate /force | Out-Null
            return 'Success'
        } -ErrorAction Stop
        
        Write-EMSLog -Message "GPO update successful on $ComputerName" -Severity 'Success' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action 'GPOUpdate' -Target $ComputerName -Details 'gpupdate /force' -Result 'Success'
        
        return $true
        
    }
    catch {
        Write-EMSLog -Message "GPO update failed: $_" -Severity 'Error' -Category 'Remediation' -Target $ComputerName
        Write-RemediationAudit -Action 'GPOUpdate' -Target $ComputerName -Details "Error: $_" -Result 'Failed'
        
        return $false
    }
}

function Test-RemediationAuthorization {
    <#
    .SYNOPSIS
        Checks if current user is authorized for remediation actions
    #>
    if (-not $Global:Config) {
        return $false
    }
    
    if (-not $Global:Config.Security.EnableRemediation) {
        return $false
    }
    
    # User must be authenticated and authorized
    return $Global:IsAuthorized
}

function Write-RemediationAudit {
    <#
    .SYNOPSIS
        Writes remediation action to audit log
    #>
    param(
        [string]$Action,
        [string]$Target,
        [string]$Details,
        [string]$Result
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $user = if ($Global:CurrentUser) { $Global:CurrentUser } else { $env:USERNAME }
        
        $auditEntry = [PSCustomObject]@{
            Timestamp = $timestamp
            User      = $user
            Action    = $Action
            Target    = $Target
            Result    = $Result
            Details   = $Details
        }
        
        # Write to remediation audit log
        $logPath = if ($Global:Config.Security.AuditLogPath) {
            Join-Path $Global:Config.Security.AuditLogPath "RemediationAudit_$(Get-Date -Format 'yyyyMM').csv"
        }
        else {
            Join-Path $PSScriptRoot "..\Logs\RemediationAudit_$(Get-Date -Format 'yyyyMM').csv"
        }
        
        $logDir = Split-Path $logPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $auditEntry | Export-Csv -Path $logPath -Append -NoTypeInformation
        
    }
    catch {
        Write-Warning "Failed to write remediation audit: $_"
    }
}

Export-ModuleMember -Function Invoke-ServiceRemediation, Invoke-ProcessRemediation, Invoke-DiskRemediation, Invoke-GPORemediation, Test-RemediationAuthorization
