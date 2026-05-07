<#
  Logging.psm1
  Centralized logging for EMS
#>

$script:LogRoot = Join-Path $PSScriptRoot "..\Logs"

# -------------------------
# Core Logger
# -------------------------
function Write-EMSLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Severity = 'Info',

        [string]$Category = 'General',
        [string]$Target   = '',
        [Guid]  $CorrelationId
    )

    $timestamp = Get-Date
    $user      = if ($Global:CurrentUser) { $Global:CurrentUser } else { $env:USERNAME }

    $entry = [pscustomobject]@{
        Timestamp       = $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
        Severity        = $Severity
        Category        = $Category
        User            = $user
        Target          = $Target
        CorrelationId   = if ($CorrelationId) { $CorrelationId } else { "" }
        Message         = $Message
    }

    $color = @{
        Error   = 'Red'
        Warning = 'Yellow'
        Success = 'Green'
        Info    = 'White'
    }[$Severity]

    Write-Host "[$($entry.Timestamp)] [$Severity] $Message" -ForegroundColor $color

    try {
        if (-not (Test-Path $script:LogRoot)) {
            New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
        }

        $logFile = Join-Path $script:LogRoot ("EMS_{0}.csv" -f (Get-Date -Format 'yyyyMMdd'))

        $entry |
            Export-Csv -Path $logFile -Append -NoTypeInformation
    }
    catch {
        Write-Warning "EMS logging failure: $($_.Exception.Message)"
    }
}

# -------------------------
# Audit Export
# -------------------------
function Export-AuditTrail {
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-7),
        [datetime]$EndDate   = (Get-Date),
        [string]$OutputPath
    )

    if (-not (Test-Path $script:LogRoot)) {
        Write-Warning "No logs present"
        return
    }

    $logs = Get-ChildItem $script:LogRoot -Filter "EMS_*.csv" |
        ForEach-Object {
            try {
                $date = [datetime]::ParseExact(
                    $_.BaseName.Replace('EMS_', ''),
                    'yyyyMMdd',
                    $null
                )
                if ($date -ge $StartDate -and $date -le $EndDate) {
                    Import-Csv $_.FullName
                }
            } catch {}
        }

    if (-not $logs) {
        Write-Warning "No matching logs"
        return
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path $script:LogRoot (
            "AuditTrail_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        )
    }

    $logs | Export-Csv $OutputPath -NoTypeInformation
    Write-Host "Audit exported: $OutputPath" -ForegroundColor Green
}

Export-ModuleMember -Function Write-EMSLog, Export-AuditTrail