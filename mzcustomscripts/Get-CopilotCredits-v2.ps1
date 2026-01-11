<#
.SYNOPSIS
    Get Copilot Studio credits (billed and non-billed) for all agents across all environments
.DESCRIPTION
    Uses the hidden licensing API endpoint discovered via browser dev tools to retrieve
    actual consumption data including both billed and non-billed credits per agent.
    
    Endpoint: https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/{tenant}/entitlements/MCSMessages/environments/{env}/resources
    
    Date Range Notes:
    - Dates are MANDATORY for the API (returns empty without them)
    - Default 365 days captures complete historical data (13x more than 30 days)
    - 365-day range typically returns ~1495 MB of data vs ~112 MB for 30 days
    
.PARAMETER TenantId
    Azure AD Tenant ID (default: b22f8675-8375-455b-941a-67bee4cf7747)
    
.PARAMETER LookbackDays
    Number of days to look back for credits data (default: 365)
    Tested ranges: 7 (too recent), 30/60/90 (limited), 365 (complete historical data)
    
.EXAMPLE
    .\Get-CopilotCredits-v2.ps1
    Uses default 365-day lookback for complete data
    
.EXAMPLE
    .\Get-CopilotCredits-v2.ps1 -LookbackDays 90
    Uses 90-day lookback for recent data only
#>

param(
    [string]$TenantId = "b22f8675-8375-455b-941a-67bee4cf7747",
    [int]$LookbackDays = 365  # Default to 365 days for complete historical data
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   GET: Copilot Studio Credits (Billed + Non-Billed)                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Authentication function
function Get-AuthToken {
    param([string]$Resource)
    
    Write-Host "🔐 Authenticating for $Resource..." -ForegroundColor Yellow
    
    $publicClientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    
    $body = @{
        client_id = $publicClientId
        scope     = "$Resource/.default offline_access"
    }
    
    $deviceCode = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" -Method POST -Body $body
    
    Write-Host "`n  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "  ║  Open: https://microsoft.com/devicelogin" -ForegroundColor Yellow
    Write-Host "  ║  Code: $($deviceCode.user_code)" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    Start-Process "https://microsoft.com/devicelogin"
    Read-Host "`n  Press ENTER after completing login"
    
    $tokenBody = @{
        grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
        client_id   = $publicClientId
        device_code = $deviceCode.device_code
    }
    
    $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $tokenBody
    Write-Host "   ✓ Authenticated`n" -ForegroundColor Green
    
    return $response.access_token
}

# Get credits for a single environment
function Get-EnvironmentCredits {
    param(
        [string]$Token,
        [string]$EnvironmentId,
        [string]$EnvironmentName,
        [datetime]$FromDate,
        [datetime]$ToDate
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept"        = "application/json"
    }
    
    $fromStr = $FromDate.ToString("MM-dd-yyyy")
    $toStr = $ToDate.ToString("MM-dd-yyyy")
    
    $url = "https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/$TenantId/entitlements/MCSMessages/environments/$EnvironmentId/resources?fromDate=$fromStr&toDate=$toStr"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        return $response.value[0].resources
    }
    catch {
        Write-Host "   ⚠ No data for environment: $EnvironmentName" -ForegroundColor Yellow
        return @()
    }
}

try {
    # Load environments from existing Inventory API export
    $inventoryFile = Join-Path (Split-Path $scriptDir -Parent) "CopilotAgents_InventoryAPI.csv"
    
    if (-not (Test-Path $inventoryFile)) {
        Write-Host "❌ Cannot find $inventoryFile" -ForegroundColor Red
        Write-Host "   Please run Get-AllAgents-InventoryAPI-v2.ps1 first to generate environment list" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "📂 Loading environment list from: CopilotAgents_InventoryAPI.csv" -ForegroundColor Cyan
    $agentData = Import-Csv $inventoryFile
    $environments = $agentData | Select-Object -Property @{Name="Id";Expression={$_."Environment ID"}}, @{Name="Name";Expression={$_.Environment}} -Unique | Where-Object { $_.Id -and $_.Name }
    Write-Host "   ✓ Found $($environments.Count) unique environments`n" -ForegroundColor Green
    
    # Authenticate for licensing API
    $token = Get-AuthToken -Resource "https://licensing.powerplatform.microsoft.com"
    
    # Calculate date range
    $toDate = Get-Date
    $fromDate = $toDate.AddDays(-$LookbackDays)
    
    Write-Host "📅 Date Range: $($fromDate.ToString('yyyy-MM-dd')) to $($toDate.ToString('yyyy-MM-dd')) ($LookbackDays days)" -ForegroundColor White
    Write-Host "   💡 Note: 365-day range recommended for complete historical data" -ForegroundColor Gray
    Write-Host ""
    
    # Collect credits from all environments
    Write-Host "📊 Collecting credits data from all environments..." -ForegroundColor Cyan
    Write-Host ""
    
    $allCredits = @()
    $envCount = 0
    
    foreach ($env in $environments) {
        $envCount++
        $envName = $env.Name
        $envId = $env.Id
        
        Write-Host "[$envCount/$($environments.Count)] $envName" -ForegroundColor Gray
        
        $credits = Get-EnvironmentCredits -Token $token -EnvironmentId $envId -EnvironmentName $envName -FromDate $fromDate -ToDate $toDate
        
        if ($credits.Count -gt 0) {
            Write-Host "   ✓ Found $($credits.Count) resource entries" -ForegroundColor Green
            
            foreach ($credit in $credits) {
                $allCredits += [PSCustomObject]@{
                    EnvironmentId      = $envId
                    EnvironmentName    = $envName
                    ResourceId         = $credit.resourceId
                    ResourceName       = $credit.metadata.ResourceName
                    ProductName        = $credit.metadata.ProductName
                    FeatureName        = $credit.metadata.FeatureName
                    ChannelId          = $credit.metadata.ChannelId
                    BilledCredits      = $credit.consumed
                    NonBilledCredits   = $credit.metadata.NonBillableQuantity
                    Unit               = $credit.unit
                    LastRefreshed      = $credit.lastRefreshedDate
                }
            }
        }
    }
    
    Write-Host ""
    
    if ($allCredits.Count -eq 0) {
        Write-Host "⚠ No credits data found for any environment in the specified date range" -ForegroundColor Yellow
        Write-Host "   Try increasing LookbackDays parameter (current: $LookbackDays)" -ForegroundColor Yellow
        exit 0
    }
    
    # Aggregate by agent (resourceId)
    Write-Host "📈 Aggregating credits by agent..." -ForegroundColor Cyan
    
    $agentCredits = $allCredits | Group-Object ResourceId | ForEach-Object {
        $group = $_.Group
        $resourceName = ($group | Select-Object -First 1).ResourceName
        $environmentNames = ($group | Select-Object -ExpandProperty EnvironmentName -Unique) -join ', '
        
        $totalBilled = ($group | Measure-Object BilledCredits -Sum).Sum
        $totalNonBilled = ($group | Measure-Object NonBilledCredits -Sum).Sum
        
        [PSCustomObject]@{
            ResourceId           = $_.Name
            ResourceName         = $resourceName
            Environments         = $environmentNames
            TotalBilledCredits   = [math]::Round($totalBilled, 2)
            TotalNonBilledCredits = [math]::Round($totalNonBilled, 2)
            TotalCredits         = [math]::Round($totalBilled + $totalNonBilled, 2)
            RecordCount          = $group.Count
        }
    } | Sort-Object TotalCredits -Descending
    
    Write-Host ""
    
    # Display summary
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   CREDITS SUMMARY                                                    ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
    
    Write-Host "📊 Total Agents with Usage: $($agentCredits.Count)" -ForegroundColor White
    Write-Host ""
    
    $agentCredits | Format-Table -AutoSize -Property @(
        @{Label="Agent Name"; Expression={$_.ResourceName}; Width=40}
        @{Label="Resource ID"; Expression={$_.ResourceId.Substring(0, 8) + "..."}; Width=12}
        @{Label="Billed (MB)"; Expression={$_.TotalBilledCredits}; Width=12}
        @{Label="Non-Billed (MB)"; Expression={$_.TotalNonBilledCredits}; Width=15}
        @{Label="Total (MB)"; Expression={$_.TotalCredits}; Width=12}
    )
    
    # Export to CSV
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # Detailed export (all records)
    $detailFile = Join-Path $scriptDir "CopilotCredits_Detailed_${timestamp}.csv"
    $allCredits | Export-Csv -Path $detailFile -NoTypeInformation -Encoding UTF8
    Write-Host "💾 Detailed data saved: $detailFile" -ForegroundColor Cyan
    
    # Aggregated export (by agent)
    $summaryFile = Join-Path $scriptDir "CopilotCredits_Summary_${timestamp}.csv"
    $agentCredits | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
    Write-Host "💾 Summary data saved: $summaryFile" -ForegroundColor Cyan
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ Credits collection completed successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
    
    # Show total credits
    $totalBilled = ($agentCredits | Measure-Object TotalBilledCredits -Sum).Sum
    $totalNonBilled = ($agentCredits | Measure-Object TotalNonBilledCredits -Sum).Sum
    
    Write-Host "🎯 TENANT TOTALS:" -ForegroundColor Yellow
    Write-Host "   Billed Credits: $([math]::Round($totalBilled, 2)) MB" -ForegroundColor White
    Write-Host "   Non-Billed Credits: $([math]::Round($totalNonBilled, 2)) MB" -ForegroundColor White
    Write-Host "   Total Usage: $([math]::Round($totalBilled + $totalNonBilled, 2)) MB" -ForegroundColor White
    Write-Host "   Date Range: $LookbackDays days`n" -ForegroundColor White
}
catch {
    Write-Host "`n❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
