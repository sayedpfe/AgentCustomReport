<#
.SYNOPSIS
    Get ALL Copilot Studio Agents using Power Platform Inventory API (v2)
.DESCRIPTION
    Uses the Power Platform Inventory API to query agents and environments,
    then joins the data locally to get complete information.
#>

param(
    [string]$OutputPath = "..\CopilotAgents_InventoryAPI.csv",
    [string]$TenantId = "b22f8675-8375-455b-941a-67bee4cf7747"
)

Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   COPILOT STUDIO AGENTS - INVENTORY API V2                           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$apiEndpoint = "https://api.powerplatform.com"

function Get-AuthToken {
    param([string]$Resource)
    
    Write-Host "📌 Authenticating..." -ForegroundColor Yellow
    
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

function Invoke-InventoryQuery {
    param(
        [string]$Token,
        [string]$ResourceType
    )
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
    
    $query = @{
        Options = @{
            Top  = 1000
            Skip = 0
        }
        TableName = "PowerPlatformResources"
        Clauses = @(
            @{
                '$type' = "where"
                FieldName = "type"
                Operator = "in~"
                Values = @($ResourceType)
            }
        )
    }
    
    $apiUrl = "$apiEndpoint/resourcequery/resources/query?api-version=2024-10-01"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Headers $headers -Body ($query | ConvertTo-Json -Depth 10)
        return $response.data
    }
    catch {
        Write-Host "`n❌ Error querying $ResourceType" -ForegroundColor Red
        Write-Host "   Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        Write-Host "   Message: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

try {
    Write-Host "API Endpoint: $apiEndpoint" -ForegroundColor Gray
    
    # Authenticate once for all queries
    $token = Get-AuthToken -Resource $apiEndpoint
    
    # Get all agents
    Write-Host "📌 Querying Copilot Studio agents..." -ForegroundColor Yellow
    $agents = Invoke-InventoryQuery -Token $token -ResourceType "'microsoft.copilotstudio/agents'"
    Write-Host "   ✓ Found $($agents.Count) agents`n" -ForegroundColor Green
    
    # Get all environments
    Write-Host "📌 Querying Power Platform environments..." -ForegroundColor Yellow
    $environments = Invoke-InventoryQuery -Token $token -ResourceType "'microsoft.powerplatform/environments'"
    Write-Host "   ✓ Found $($environments.Count) environments`n" -ForegroundColor Green
    
    # Create environment lookup table
    $envLookup = @{}
    foreach ($env in $environments) {
        $envId = $env.name.ToLower()
        $envLookup[$envId] = @{
            Name   = $env.properties.displayName
            Type   = $env.properties.environmentType
            Region = $env.location
        }
    }
    
    # Join agents with environments
    Write-Host "📌 Joining agent and environment data..." -ForegroundColor Yellow
    $result = @()
    foreach ($agent in $agents) {
        $props = $agent.properties
        $envId = $props.environmentId.ToLower()
        $env = $envLookup[$envId]
        
        $agentType = if ($props.agentType) { "Copilot Studio ($($props.agentType))" } else { "Copilot Studio (full)" }
        
        $result += [PSCustomObject]@{
            "Item name"          = $props.displayName
            "Created in"         = $agentType
            "Item ID"            = $agent.name
            "Owner"              = if ($props.owner) { $props.owner.displayName } else { $props.ownerId }
            "Created on"         = if ($props.createdAt) { (Get-Date $props.createdAt -Format "MM/dd/yy") } else { "-" }
            "Created by"         = if ($props.createdBy) { $props.createdBy.displayName } else { "-" }
            "Modified on"        = if ($props.modifiedAt) { (Get-Date $props.modifiedAt -Format "MM/dd/yy") } else { "-" }
            "Published on"       = if ($props.publishedOn) { (Get-Date $props.publishedOn -Format "MM/dd/yy") } else { "-" }
            "Environment"        = if ($env) { $env.Name } else { "-" }
            "Environment type"   = if ($env) { $env.Type } else { "-" }
            "Environment ID"     = $props.environmentId
            "Environment region" = if ($env) { $env.Region } else { "-" }
            "Managed environment"= "No"
        }
    }
    
    Write-Host "   ✓ Complete`n" -ForegroundColor Green
    
    # Export to CSV
    $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    
    # Display results
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   SUCCESS!                                                           ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n  Total Agents:         $($result.Count)" -ForegroundColor Cyan
    Write-Host "  Output File:          $OutputPath" -ForegroundColor Cyan
    
    Write-Host "`n  Breakdown by Environment:" -ForegroundColor Yellow
    $result | Group-Object "Environment" | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host ("    {0,-35} {1,3} agents" -f $_.Name, $_.Count) -ForegroundColor White
    }
    
    Write-Host "`n  By Environment Type:" -ForegroundColor Yellow
    $result | Group-Object "Environment type" | Sort-Object Count -Descending | ForEach-Object {
        Write-Host ("    {0,-20} {1,3} agents" -f $_.Name, $_.Count) -ForegroundColor White
    }
    
    # Validation
    if ($result.Count -eq 115) {
        Write-Host "`n  🎉 PERFECT! Found all 115 agents!" -ForegroundColor Green
    }
    elseif ($result.Count -lt 115) {
        Write-Host "`n  ⚠ Found $($result.Count) agents (expected 115)" -ForegroundColor Yellow
    }
    else {
        Write-Host "`n  ✓ Found $($result.Count) agents (more than 115 expected)" -ForegroundColor Green
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "✅ Inventory API is the BEST method - single auth, all environments!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}
catch {
    Write-Host "`n❌ Script failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
