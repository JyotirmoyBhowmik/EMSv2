<#
    EMS.Auth.psm1
    Security and RBAC logic for the Enterprise Monitoring System.
#>

function Get-RequestUserContext {
    param([System.Net.HttpListenerRequest]$Request)

    $username  = $Request.Headers['X-EMS-Username']
    $groupsRaw = $Request.Headers['X-EMS-Groups']
    $role      = $Request.Headers['X-EMS-Role']

    $groups = @()
    if ($groupsRaw) {
        $groups = $groupsRaw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    return [pscustomobject]@{
        Username = $username
        Groups   = $groups
        Role     = $role
    }
}

function Test-GroupMembership {
    param(
        [string[]]$Groups,
        [string]$RequiredGroup
    )

    foreach ($group in @($Groups)) {
        if (-not $group) { continue }

        if ($group -ieq $RequiredGroup) {
            return $true
        }

        $escapedRequired = [regex]::Escape($RequiredGroup)
        if ($group -match ('(?i)(?:^|,)CN=' + $escapedRequired + '(?:,|$)')) {
            return $true
        }
    }

    return $false
}

function Resolve-UserRole {
    param(
        [string[]]$Groups,
        [pscustomobject]$Config
    )

    $adminGroup   = [string]$Config.Security.AdminGroup
    $monitorGroup = [string]$Config.Security.MonitorGroup

    if (Test-GroupMembership -Groups $Groups -RequiredGroup $adminGroup) {
        return 'Admin'
    }

    if (Test-GroupMembership -Groups $Groups -RequiredGroup $monitorGroup) {
        return 'Monitor'
    }

    return $null
}

function Get-UserPermissionsObject {
    param([string]$Role)

    switch ($Role) {
        'Admin' {
            return @{
                canView    = $true
                canScan    = $true
                canArchive = $true
                canAdmin   = $true
            }
        }
        'Monitor' {
            return @{
                canView    = $true
                canScan    = $false
                canArchive = $false
                canAdmin   = $false
            }
        }
        default {
            return @{
                canView    = $false
                canScan    = $false
                canArchive = $false
                canAdmin   = $false
            }
        }
    }
}

function Test-ViewerAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [pscustomobject]$Config
    )

    $ctx = Get-RequestUserContext -Request $Request
    if (-not $ctx.Username) { return $false }

    $role = if ($ctx.Role) { $ctx.Role } else { Resolve-UserRole -Groups $ctx.Groups -Config $Config }
    return $role -in @('Admin', 'Monitor')
}

function Test-AdminAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [pscustomobject]$Config
    )

    $ctx = Get-RequestUserContext -Request $Request
    if (-not $ctx.Username) { return $false }

    $role = if ($ctx.Role) { $ctx.Role } else { Resolve-UserRole -Groups $ctx.Groups -Config $Config }
    return $role -eq 'Admin'
}

function Test-ViewerAccessRequirement {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [pscustomobject]$Config
    )

    if (-not (Test-ViewerAccess -Request $Request -Config $Config)) {
        Write-JsonResponse $Request $Response 403 @{ success = $false; message = 'EMS_Admins or EMS_Monitor membership is required' }
        return $false
    }

    return $true
}

function Test-AdminAccessRequirement {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [pscustomobject]$Config
    )

    if (-not (Test-AdminAccess -Request $Request -Config $Config)) {
        Write-JsonResponse $Request $Response 403 @{ success = $false; message = 'EMS_Admins membership is required for this action' }
        return $false
    }

    return $true
}

Export-ModuleMember -Function Get-RequestUserContext, Test-GroupMembership, Resolve-UserRole, Get-UserPermissionsObject, Test-ViewerAccess, Test-AdminAccess, Test-ViewerAccessRequirement, Test-AdminAccessRequirement
