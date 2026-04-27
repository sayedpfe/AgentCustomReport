<#
.SYNOPSIS
    Complete Copilot Studio Agent Report - v1.3 with Solution ID Support
    
.DESCRIPTION
    Enhanced authentication with refresh token caching for automation scenarios.
    Now includes proper Dataverse integration to retrieve Solution ID for each agent.
    
    Supports TWO execution modes:
    1. LOCAL: Uses authorization code flow with local browser → caches refresh token
    2. AZURE AUTOMATION: Reads refresh token from Automation Variable
    
    After initial authentication, subsequent runs use cached refresh token (no user interaction).
    Refresh tokens are valid for 90 days and automatically renewed.
    
.PARAMETER Mode
    Execution mode: 'Local' (default) or 'AzureAutomation'
    
.PARAMETER TenantId
    Azure AD Tenant ID
    Default: b22f8675-8375-455b-941a-67bee4cf7747
    
.PARAMETER LookbackDays
    Number of days for credits historical data
    Default: 365
    
.PARAMETER IncludeDataverse
    Include Solution ID and Description from Dataverse (experimental)
    
.PARAMETER ForceReauth
    Force re-authentication even if cached token exists
    
.EXAMPLE
    # First run - opens browser for user sign-in
    .\Get-CompleteCopilotReport-v1.2.ps1
    
.EXAMPLE
    # Subsequent runs - uses cached refresh token (no interaction)
    .\Get-CompleteCopilotReport-v1.2.ps1
    
.EXAMPLE
    # Force re-authentication
    .\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth
    
.EXAMPLE
    # Azure Automation mode
    .\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation
    
.NOTES
    Version: 1.3
    Author: Agent Custom Report Solution
    Last Updated: 2026-02-23
    
    Changes in v1.3:
    - Fixed Dataverse URL construction using Power Platform Admin API
    - Solution ID retrieval now works correctly with proper environment URLs
    
    Authentication: Authorization Code Flow with Refresh Token
    - First run: Opens browser for user to sign in
    - Token cached locally or in Azure Automation Variable
    - Subsequent runs: Uses cached refresh token (no user interaction)
    - Refresh tokens valid for 90 days (renewable)
    
    Azure Automation Setup:
    1. Create Automation Account
    2. Import this script as Runbook
    3. Run once interactively to get refresh token
    4. Store refresh token in Automation Variable (encrypted)
    5. Schedule runbook execution
    
    Output: CopilotAgents_CompleteReport_TIMESTAMP.csv
#>

param(
    [ValidateSet('Local', 'AzureAutomation')]
    [string]$Mode = 'Local',
    [string]$TenantId = "b22f8675-8375-455b-941a-67bee4cf7747",
    [int]$LookbackDays = 365,
    [switch]$IncludeDataverse = $false,
    [switch]$ForceReauth = $false
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Continue"

# Token cache location
$tokenCacheFile = Join-Path $env:USERPROFILE ".copilot-report-tokens.json"

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   COMPLETE COPILOT STUDIO AGENT REPORT v1.3                         ║
║   Refresh Token Authentication + Dataverse Solution ID              ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "🔐 Authentication Mode: $Mode" -ForegroundColor Green
Write-Host "   Refresh Token: Enabled (90-day validity)" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# AUTHENTICATION FUNCTIONS
# ============================================================================

function Start-LocalBrowserAuth {
    param(
        [string]$Resource,
        [string]$TenantId
    )
    
    Write-Host "`n🌐 Opening browser for sign-in..." -ForegroundColor Yellow
    
    # Use a redirect URI that works for public clients
    $clientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    $redirectUri = "http://localhost:8400"
    $scope = "$Resource/.default offline_access"
    
    # Start local HTTP listener
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("$redirectUri/")
    $listener.Start()
    
    try {
        # Generate PKCE code verifier and challenge
        $codeVerifier = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)) -replace '\+', '-' -replace '/', '_' -replace '='
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $codeChallenge = [Convert]::ToBase64String($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($codeVerifier))) -replace '\+', '-' -replace '/', '_' -replace '='
        
        # Build authorization URL
        $state = [Guid]::NewGuid().ToString()
        $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?" +
                   "client_id=$clientId" +
                   "&response_type=code" +
                   "&redirect_uri=$([Uri]::EscapeDataString($redirectUri))" +
                   "&response_mode=query" +
                   "&scope=$([Uri]::EscapeDataString($scope))" +
                   "&state=$state" +
                   "&code_challenge=$codeChallenge" +
                   "&code_challenge_method=S256"
        
        # Open browser
        Start-Process $authUrl
        Write-Host "   ✓ Browser opened for sign-in" -ForegroundColor Green
        Write-Host "   ⏳ Waiting for authorization..." -ForegroundColor Yellow
        
        # Wait for callback
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        # Send success page
        $successHtml = @"
<html>
<head><title>Authentication Successful</title></head>
<body style='font-family:Arial;text-align:center;padding:50px'>
    <h1 style='color:green'>✓ Authentication Successful</h1>
    <p>You can close this window and return to PowerShell.</p>
</body>
</html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($successHtml)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
        
        # Extract authorization code
        $queryParams = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $authCode = $queryParams["code"]
        
        if (-not $authCode) {
            $listener.Stop()
            $listener.Close()
            throw "Authorization code not received. Please complete the sign-in in your browser."
        }
        
        Write-Host "   ✓ Authorization code received" -ForegroundColor Green
        
        # Exchange code for tokens
        $tokenBody = @{
            client_id     = $clientId
            scope         = $scope
            code          = $authCode
            redirect_uri  = $redirectUri
            grant_type    = "authorization_code"
            code_verifier = $codeVerifier
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        Write-Host "   ✓ Tokens acquired successfully" -ForegroundColor Green
        
        return @{
            AccessToken  = $tokenResponse.access_token
            RefreshToken = $tokenResponse.refresh_token
            ExpiresIn    = $tokenResponse.expires_in
            Resource     = $Resource
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}

function Get-RefreshTokenAuth {
    param(
        [string]$RefreshToken,
        [string]$Resource,
        [string]$TenantId
    )
    
    Write-Host "`n🔄 Using cached refresh token..." -ForegroundColor Yellow
    
    $clientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    
    $body = @{
        client_id     = $clientId
        scope         = "$Resource/.default offline_access"
        refresh_token = $RefreshToken
        grant_type    = "refresh_token"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
        
        Write-Host "   ✓ Token refreshed successfully" -ForegroundColor Green
        
        return @{
            AccessToken  = $response.access_token
            RefreshToken = $response.refresh_token
            ExpiresIn    = $response.expires_in
            Resource     = $Resource
        }
    }
    catch {
        Write-Host "   ❌ Refresh token expired or invalid" -ForegroundColor Red
        Write-Host "   Re-authentication required" -ForegroundColor Yellow
        return $null
    }
}

function Get-CachedToken {
    param([string]$Resource)
    
    if ($Mode -eq 'AzureAutomation') {
        # Read from Automation Variable
        Write-Host "📦 Reading token from Azure Automation Variable..." -ForegroundColor Yellow
        $refreshToken = Get-AutomationVariable -Name "CopilotReportRefreshToken_$($Resource.Replace('https://', '').Replace('.', '_'))"
        
        if ($refreshToken) {
            Write-Host "   ✓ Refresh token found" -ForegroundColor Green
            return $refreshToken
        }
        else {
            Write-Host "   ❌ No refresh token found in Automation Variables" -ForegroundColor Red
            Write-Host "   Please run this script interactively first to acquire token" -ForegroundColor Yellow
            throw "Refresh token not found in Azure Automation"
        }
    }
    else {
        # Read from local cache file
        if (Test-Path $tokenCacheFile) {
            $cache = Get-Content $tokenCacheFile | ConvertFrom-Json
            $resourceKey = $Resource.Replace('https://', '').Replace('.', '_')
            
            if ($cache.$resourceKey) {
                Write-Host "   ✓ Cached refresh token found" -ForegroundColor Green
                return $cache.$resourceKey.RefreshToken
            }
        }
        
        Write-Host "   ℹ No cached token found" -ForegroundColor Gray
        return $null
    }
}

function Save-TokenCache {
    param(
        [string]$Resource,
        [hashtable]$TokenData
    )
    
    if ($Mode -eq 'AzureAutomation') {
        # Save to Automation Variable
        Write-Host "📦 Saving refresh token to Azure Automation Variable..." -ForegroundColor Yellow
        $varName = "CopilotReportRefreshToken_$($Resource.Replace('https://', '').Replace('.', '_'))"
        
        Set-AutomationVariable -Name $varName -Value $TokenData.RefreshToken
        Write-Host "   ✓ Token saved to Automation Variable: $varName" -ForegroundColor Green
    }
    else {
        # Save to local cache file
        $cache = @{}
        if (Test-Path $tokenCacheFile) {
            $cache = Get-Content $tokenCacheFile | ConvertFrom-Json -AsHashtable
        }
        
        $resourceKey = $Resource.Replace('https://', '').Replace('.', '_')
        $cache[$resourceKey] = @{
            RefreshToken = $TokenData.RefreshToken
            CachedAt     = (Get-Date).ToString("o")
            ExpiresIn    = $TokenData.ExpiresIn
        }
        
        $cache | ConvertTo-Json | Set-Content $tokenCacheFile
        Write-Host "   ✓ Token cached locally: $tokenCacheFile" -ForegroundColor Green
    }
}

function Get-AuthToken {
    param(
        [string]$Resource,
        [string]$DisplayName
    )
    
    Write-Host "`n🔐 Authenticating to $DisplayName..." -ForegroundColor Cyan
    
    # Try cached refresh token first (unless ForceReauth)
    if (-not $ForceReauth) {
        $cachedRefreshToken = Get-CachedToken -Resource $Resource
        
        if ($cachedRefreshToken) {
            $tokenData = Get-RefreshTokenAuth -RefreshToken $cachedRefreshToken -Resource $Resource -TenantId $script:TenantId
            
            if ($tokenData) {
                # Update cache with new refresh token
                Save-TokenCache -Resource $Resource -TokenData $tokenData
                return $tokenData.AccessToken
            }
        }
    }
    
    # No cached token or refresh failed - do full auth
    Write-Host "   ℹ Full authentication required" -ForegroundColor Yellow
    
    $tokenData = Start-LocalBrowserAuth -Resource $Resource -TenantId $script:TenantId
    
    # Cache the refresh token
    Save-TokenCache -Resource $Resource -TokenData $tokenData
    
    return $tokenData.AccessToken
}

# ============================================================================
# STEP 1: AZURE RESOURCE GRAPH - GET ALL AGENTS
# ============================================================================

function Get-AllAgents {
    param([string]$Token)
    
    Write-Host "`n📦 STEP 1: Retrieving agents from Azure Resource Graph..." -ForegroundColor Cyan
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }
    
    $url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"
    
    # Direct KQL query
    $query = @{
        query = @"
PowerPlatformResources
| where type == 'microsoft.copilotstudio/agents'
| take 1000
"@
    }
    
    try {
        # Execute query
        $response = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body ($query | ConvertTo-Json)
        $agentData = $response.data
        
        # Process agents
        $agents = $agentData | ForEach-Object {
            $props = $_.properties
            
            [PSCustomObject]@{
                AgentId           = $_.name
                AgentName         = $props.displayName
                EnvironmentId     = $props.environmentId
                EnvironmentName   = $props.environmentId
                EnvironmentType   = "Unknown"
                EnvironmentRegion = $_.location
                CreatedOn         = if ($props.createdAt) { (Get-Date $props.createdAt).ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                ModifiedOn        = $null
                PublishedOn       = if ($props.lastPublishedAt) { (Get-Date $props.lastPublishedAt).ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                Owner             = $props.ownerId
                CreatedIn         = if ($props.createdIn) { $props.createdIn } else { "Copilot Studio" }
                SolutionId        = $null
                Description       = $null
            }
        }
        
        Write-Host "   ✓ Retrieved $($agents.Count) agents`n" -ForegroundColor Green
        return $agents
    }
    catch {
        Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
        throw
    }
}

# ============================================================================
# STEP 2: LICENSING API - GET CREDITS
# ============================================================================

function Get-CreditsData {
    param(
        [string]$Token,
        [array]$Agents,
        [datetime]$FromDate,
        [datetime]$ToDate
    )
    
    Write-Host "💰 STEP 2: Retrieving credits consumption..." -ForegroundColor Cyan
    Write-Host "   Date Range: $($FromDate.ToString('yyyy-MM-dd')) to $($ToDate.ToString('yyyy-MM-dd')) ($LookbackDays days)" -ForegroundColor Gray
    Write-Host ""
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept"        = "application/json"
    }
    
    $fromStr = $FromDate.ToString("MM-dd-yyyy")
    $toStr = $ToDate.ToString("MM-dd-yyyy")
    
    # Get unique environments
    $environments = $Agents | Select-Object EnvironmentId, EnvironmentName -Unique
    
    $creditsLookup = @{}
    $envCount = 0
    
    foreach ($env in $environments) {
        $envCount++
        Write-Host "   [$envCount/$($environments.Count)] $($env.EnvironmentName)" -ForegroundColor Gray
        
        $url = "https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/$TenantId/entitlements/MCSMessages/environments/$($env.EnvironmentId)/resources?fromDate=$fromStr&toDate=$toStr"
        
        try {
            $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
            
            if ($response.value -and $response.value[0].resources) {
                $resources = $response.value[0].resources
                Write-Host "      ✓ Found $($resources.Count) resource entries" -ForegroundColor Green
                
                foreach ($resource in $resources) {
                    $agentId = $resource.resourceId
                    
                    if (-not $creditsLookup.ContainsKey($agentId)) {
                        $creditsLookup[$agentId] = @{
                            BilledCredits = 0
                            NonBilledCredits = 0
                        }
                    }
                    
                    $creditsLookup[$agentId].BilledCredits += $resource.consumed
                    $creditsLookup[$agentId].NonBilledCredits += $resource.metadata.NonBillableQuantity
                }
            }
        }
        catch {
            Write-Host "      ⚠ No data available" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n   ✓ Credits data collected for $($creditsLookup.Count) agents`n" -ForegroundColor Green
    return $creditsLookup
}

# ============================================================================
# STEP 3: DATAVERSE - GET SOLUTION ID & DESCRIPTION (OPTIONAL)
# ============================================================================

function Get-DataverseData {
    param(
        [string]$DataverseToken,
        [string]$PowerPlatformToken,
        [array]$Agents
    )
    
    if (-not $IncludeDataverse) {
        Write-Host "⏭️  STEP 3: Skipping Dataverse queries (use -IncludeDataverse to enable)`n" -ForegroundColor Yellow
        return @{}
    }
    
    Write-Host "🗄️  STEP 3: Retrieving Solution ID from Dataverse..." -ForegroundColor Cyan
    Write-Host "   ⚠️ This may take several minutes (querying environment details)" -ForegroundColor Yellow
    Write-Host ""
    
    # Get unique environments
    $environments = $Agents | Select-Object EnvironmentId, EnvironmentName -Unique
    $envCount = 0
    $dataverseLookup = @{}
    
    # Headers for Power Platform API
    $ppHeaders = @{
        "Authorization" = "Bearer $PowerPlatformToken"
        "Accept"        = "application/json"
    }
    
    # Headers for Dataverse API
    $dvHeaders = @{
        "Authorization" = "Bearer $DataverseToken"
        "Accept"        = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }
    
    foreach ($env in $environments) {
        $envCount++
        Write-Host "   [$envCount/$($environments.Count)] $($env.EnvironmentName)" -ForegroundColor Gray
        
        try {
            # Get environment details from Power Platform API (non-admin endpoint)
            $envDetailsUrl = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$($env.EnvironmentId)?api-version=2020-10-01"
            $envDetails = Invoke-RestMethod -Uri $envDetailsUrl -Method GET -Headers $ppHeaders
            
            # Extract Dataverse instance URL
            if ($envDetails.properties.linkedEnvironmentMetadata.instanceUrl) {
                $dataverseBaseUrl = $envDetails.properties.linkedEnvironmentMetadata.instanceUrl
                $dataverseUrl = "$dataverseBaseUrl/api/data/v9.2/bots?`$select=botid,name,solutionid,description,schemaname"
                
                # Query Dataverse for bot records
                $response = Invoke-RestMethod -Uri $dataverseUrl -Method GET -Headers $dvHeaders
                
                if ($response.value) {
                    Write-Host "      ✓ Retrieved $($response.value.Count) bot records from Dataverse" -ForegroundColor Green
                    
                    foreach ($bot in $response.value) {
                        $dataverseLookup[$bot.botid] = @{
                            SolutionId = $bot.solutionid
                            Description = $bot.description
                            SchemaName = $bot.schemaname
                        }
                    }
                }
                else {
                    Write-Host "      ℹ No bot records found" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "      ⚠ No Dataverse instance linked to this environment" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "      ⚠ Failed to query: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n   ✓ Dataverse data collected for $($dataverseLookup.Count) agents`n" -ForegroundColor Green
    return $dataverseLookup
}

# ============================================================================
# STEP 4: MERGE ALL DATA
# ============================================================================

function Merge-AllData {
    param(
        [array]$Agents,
        [hashtable]$CreditsLookup,
        [hashtable]$DataverseLookup
    )
    
    Write-Host "🔗 STEP 4: Merging all data sources..." -ForegroundColor Cyan
    
    $completeReport = foreach ($agent in $Agents) {
        $agentId = $agent.AgentId
        
        # Get credits
        $credits = $CreditsLookup[$agentId]
        $billedCredits = if ($credits) { [math]::Round($credits.BilledCredits, 2) } else { 0 }
        $nonBilledCredits = if ($credits) { [math]::Round($credits.NonBilledCredits, 2) } else { 0 }
        
        # Get Dataverse data
        $dataverse = $DataverseLookup[$agentId]
        $solutionId = if ($dataverse) { $dataverse.SolutionId } else { $null }
        $description = if ($dataverse) { $dataverse.Description } else { $null }
        
        [PSCustomObject]@{
            "Agent ID"              = $agentId
            "Agent Name"            = $agent.AgentName
            "Agent Description"     = $description
            "Environment ID"        = $agent.EnvironmentId
            "Environment Name"      = $agent.EnvironmentName
            "Environment Type"      = $agent.EnvironmentType
            "Environment Region"    = $agent.EnvironmentRegion
            "Solution ID"           = $solutionId
            "Owner"                 = $agent.Owner
            "Created On"            = $agent.CreatedOn
            "Modified On"           = $agent.ModifiedOn
            "Published On"          = $agent.PublishedOn
            "Created In"            = $agent.CreatedIn
            "Billed Credits (MB)"   = $billedCredits
            "Non-Billed Credits (MB)" = $nonBilledCredits
            "Total Credits (MB)"    = [math]::Round($billedCredits + $nonBilledCredits, 2)
            "Has Usage"             = if ($billedCredits -gt 0 -or $nonBilledCredits -gt 0) { "Yes" } else { "No" }
        }
    }
    
    Write-Host "   ✓ Merged $($completeReport.Count) agent records`n" -ForegroundColor Green
    return $completeReport
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    $startTime = Get-Date
    
    Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   COPILOT STUDIO AGENT REPORT - v1.3                                 ║
║   Authorization Code Flow + Refresh Token Caching                    ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
    
    Write-Host "Mode: $Mode" -ForegroundColor White
    Write-Host "Tenant: $TenantId" -ForegroundColor Gray
    Write-Host "Lookback: $LookbackDays days" -ForegroundColor Gray
    
    # Step 1: Authenticate to Azure Resource Graph and get agents
    $azureToken = Get-AuthToken -Resource "https://management.azure.com" -DisplayName "Azure Resource Graph"
    $agents = Get-AllAgents -Token $azureToken
    
    if ($agents.Count -eq 0) {
        throw "No agents found in Azure Resource Graph"
    }
    
    # Step 2: Get credits
    $licensingToken = Get-AuthToken -Resource "https://licensing.powerplatform.microsoft.com" -DisplayName "Licensing API"
    $toDate = Get-Date
    $fromDate = $toDate.AddDays(-$LookbackDays)
    $creditsLookup = Get-CreditsData -Token $licensingToken -Agents $agents -FromDate $fromDate -ToDate $toDate
    
    # Step 3: Get Dataverse data (optional)
    $dataverseLookup = @{}
    if ($IncludeDataverse) {
        $dataverseToken = Get-AuthToken -Resource "https://api.crm.dynamics.com" -DisplayName "Dataverse"
        $ppAdminToken = Get-AuthToken -Resource "https://api.bap.microsoft.com" -DisplayName "Power Platform Admin API"
        $dataverseLookup = Get-DataverseData -DataverseToken $dataverseToken -PowerPlatformToken $ppAdminToken -Agents $agents
    }
    
    # Step 4: Merge everything
    $completeReport = Merge-AllData -Agents $agents -CreditsLookup $creditsLookup -DataverseLookup $dataverseLookup
    
    # Export to CSV
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputFile = Join-Path $scriptDir "CopilotAgents_CompleteReport_${timestamp}.csv"
    $completeReport | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    
    # Summary
    $duration = (Get-Date) - $startTime
    
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   REPORT COMPLETE                                                    ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green
    
    $withUsage = ($completeReport | Where-Object { $_."Has Usage" -eq "Yes" }).Count
    $withSolutionId = ($completeReport | Where-Object { $_."Solution ID" -ne $null }).Count
    $withDescription = ($completeReport | Where-Object { $_."Agent Description" -ne $null }).Count
    
    $totalBilled = ($completeReport | Measure-Object "Billed Credits (MB)" -Sum).Sum
    $totalNonBilled = ($completeReport | Measure-Object "Non-Billed Credits (MB)" -Sum).Sum
    
    Write-Host "📊 Summary:" -ForegroundColor Cyan
    Write-Host "   Total Agents: $($completeReport.Count)" -ForegroundColor White
    Write-Host "   Agents with Usage: $withUsage" -ForegroundColor White
    if ($IncludeDataverse) {
        Write-Host "   Agents with Solution ID: $withSolutionId" -ForegroundColor White
        Write-Host "   Agents with Description: $withDescription" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "💰 Credits:" -ForegroundColor Cyan
    Write-Host "   Billed: $([math]::Round($totalBilled, 2)) MB" -ForegroundColor White
    Write-Host "   Non-Billed: $([math]::Round($totalNonBilled, 2)) MB" -ForegroundColor White
    Write-Host "   Total: $([math]::Round($totalBilled + $totalNonBilled, 2)) MB" -ForegroundColor White
    Write-Host ""
    Write-Host "💾 Report saved: $(Split-Path $outputFile -Leaf)" -ForegroundColor Cyan
    Write-Host "   Location: $scriptDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "⏱️  Execution time: $([math]::Round($duration.TotalMinutes, 1)) minutes`n" -ForegroundColor Gray
    
    Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ Report generation completed successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
