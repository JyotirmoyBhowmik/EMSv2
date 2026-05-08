<#
.SYNOPSIS
    EMS Health Scoring Engine
.DESCRIPTION
    Calculates a weighted health score (0-100) based on collector metrics.
#>

function Compute-EMSHealthScore {
    param(
        [Parameter(Mandatory)]
        [hashtable]$CollectorResults
    )
    
    $score = 100
    
    # 1. CPU Weight (20%)
    if ($CollectorResults['CPU'] -and $CollectorResults['CPU'].Success) {
        $maxLoad = ($CollectorResults['CPU'].Metrics | Measure-Object -Property usage_percent -Maximum).Maximum
        if ($maxLoad -gt 95) { $score -= 20 }
        elseif ($maxLoad -gt 85) { $score -= 10 }
        elseif ($maxLoad -gt 75) { $score -= 5 }
    }
    
    # 2. Memory Weight (20%)
    if ($CollectorResults['Memory'] -and $CollectorResults['Memory'].Success) {
        $usage = $CollectorResults['Memory'].Metrics[0].usage_percent
        if ($usage -gt 95) { $score -= 20 }
        elseif ($usage -gt 85) { $score -= 10 }
        elseif ($usage -gt 75) { $score -= 5 }
    }
    
    # 3. Disk Weight (20%)
    if ($CollectorResults['Disk'] -and $CollectorResults['Disk'].Success) {
        $minFree = ($CollectorResults['Disk'].Metrics | Measure-Object -Property usage_percent -Maximum).Maximum # Usage is inverse of free
        if ($minFree -gt 95) { $score -= 20 }
        elseif ($minFree -gt 90) { $score -= 10 }
        elseif ($minFree -gt 80) { $score -= 5 }
    }
    
    # 4. Critical Services Weight (15%) - Placeholder for now
    # 5. Security Weight (15%) - Placeholder for now
    # 6. Updates Weight (10%) - Placeholder for now
    
    if ($score -lt 0) { $score = 0 }
    
    return [int]$score
}

Export-ModuleMember -Function Compute-EMSHealthScore
