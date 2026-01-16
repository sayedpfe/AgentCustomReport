<#
.SYNOPSIS
    Complete Copilot Studio Agent Report - Single Script Solution (v1.1)
    
.DESCRIPTION
    Retrieves comprehensive agent data from multiple sources:
    - Azure Resource Graph: Agent metadata (name, environment, owner, timestamps) using direct KQL
    - Licensing API: Credits consumption (billed and non-billed) with 365-day lookback
    - Dataverse (Optional): Solution ID, Agent Description (per environment)
    
    Returns 8 of 12 requested fields in a single CSV report with automatic authentication handling.
    
    Uses Azure Resource Graph API with direct KQL queries (official Microsoft API) instead of
    the Power Platform Inventory API which has recent issues with KQLOM JSON format.
    
    Supports two authentication methods:
    - Certificate-based (recommended for enterprise/automation)
    - Device Code Flow (interactive, backward compatible)
    
.PARAMETER TenantId
    Azure AD Tenant ID (required for certificate authentication)
    Default: b22f8675-8375-455b-941a-67bee4cf7747
    
.PARAMETER LookbackDays
    Number of days to look back for credits consumption data
    Default: 365 days (recommended for complete historical data)
    
.PARAMETER IncludeDataverse
    Switch to include Solution ID and Description from Dataverse (experimental)
    Requires per-environment authentication and correct region URLs
    
.PARAMETER UseCertificateAuth
    Switch to use certificate-based authentication instead of Device Code Flow
    Requires AppId and CertificateThumbprint parameters
    
.PARAMETER AppId
    Azure AD Application (Client) ID for certificate authentication
    Required when using -UseCertificateAuth
    
.PARAMETER CertificateThumbprint
    Certificate thumbprint for authentication
    Certificate must be installed in CurrentUser\My or LocalMachine\My store
    Required when using -UseCertificateAuth
    
.EXAMPLE
    .\Get-CompleteCopilotReport.ps1
    Interactive authentication with Device Code Flow (default)
    
.EXAMPLE
    .\Get-CompleteCopilotReport.ps1 -LookbackDays 90
    Report with 90-day credits lookback (Device Code Flow)
    
.EXAMPLE
    .\Get-CompleteCopilotReport.ps1 -IncludeDataverse
    Include Dataverse fields (10 fields total)
    
.EXAMPLE
    .\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId "12345678-1234-1234-1234-123456789abc" -CertificateThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12"
    Certificate-based authentication (non-interactive, recommended for automation)
    
.EXAMPLE
    .\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId "12345678-1234-1234-1234-123456789abc" -CertificateThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12" -TenantId "your-tenant-id" -LookbackDays 90
    Certificate authentication with custom parameters
    
.NOTES
    Version: 1.1
    Author: Agent Custom Report Solution
    Last Updated: 2026-01-16
    
    Authentication Methods:
    1. Certificate-based (recommended for enterprise/automation):
       - OAuth 2.0 with certificate credentials
       - Non-interactive, suitable for scheduled tasks
       - Requires App Registration with certificate uploaded
       - API Permissions: https://management.azure.com/.default, https://licensing.powerplatform.microsoft.com/.default
       
    2. Device Code Flow (backward compatible):
       - Interactive OAuth 2.0
       - Requires user browser interaction
       - No App Registration needed
    
    Output: CopilotAgents_CompleteReport_TIMESTAMP.csv
    
    Setup Guide: See APP_REGISTRATION_SETUP.md for certificate configuration
#>

param(
    [string]$TenantId = "b22f8675-8375-455b-941a-67bee4cf7747",
    [int]$LookbackDays = 365,
    [switch]$IncludeDataverse = $false,
    [switch]$UseCertificateAuth = $false,
    [string]$AppId = "",
    [string]$CertificateThumbprint = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Continue"

# Validate certificate authentication parameters
if ($UseCertificateAuth) {
    if ([string]::IsNullOrWhiteSpace($AppId)) {
        Write-Host "❌ ERROR: -AppId is required when using certificate authentication" -ForegroundColor Red
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        Write-Host "❌ ERROR: -CertificateThumbprint is required when using certificate authentication" -ForegroundColor Red
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        Write-Host "❌ ERROR: -TenantId is required when using certificate authentication" -ForegroundColor Red
        exit 1
    }
}

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   COMPLETE COPILOT STUDIO AGENT REPORT v1.1                         ║
║   Certificate-Based & Device Code Authentication                    ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

if ($UseCertificateAuth) {
    Write-Host "🔒 Authentication Mode: Certificate-based (Non-interactive)" -ForegroundColor Green
    Write-Host "   App ID: $AppId" -ForegroundColor Gray
    Write-Host "   Certificate: $CertificateThumbprint" -ForegroundColor Gray
} else {
    Write-Host "🔓 Authentication Mode: Device Code Flow (Interactive)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# AUTHENTICATION FUNCTIONS
# ============================================================================

function Get-CertificateToken {
    param(
        [string]$Resource,
        [string]$DisplayName,
        [string]$AppId,
        [string]$CertificateThumbprint,
        [string]$TenantId
    )
    
    Write-Host "`n🔐 Authenticating to $DisplayName (Certificate)..." -ForegroundColor Yellow
    
    try {
        # Find certificate in CurrentUser\My store first, then LocalMachine\My
        $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
        if (-not $cert) {
            $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
        }
        
        if (-not $cert) {
            throw "Certificate with thumbprint '$CertificateThumbprint' not found in CurrentUser\My or LocalMachine\My store"
        }
        
        Write-Host "   ✓ Certificate found: $($cert.Subject)" -ForegroundColor Green
        
        # Create JWT assertion
        $now = [DateTime]::UtcNow
        $exp = $now.AddMinutes(10)
        
        $header = @{
            alg = "RS256"
            typ = "JWT"
            x5t = [Convert]::ToBase64String($cert.GetCertHash()) -replace '\+', '-' -replace '/', '_' -replace '='
        } | ConvertTo-Json -Compress
        
        $payload = @{
            aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
            exp = [Math]::Floor([decimal](Get-Date($exp).ToUniversalTime() - (Get-Date "1970-01-01")).TotalSeconds)
            iss = $AppId
            jti = [Guid]::NewGuid().ToString()
            nbf = [Math]::Floor([decimal](Get-Date($now).ToUniversalTime() - (Get-Date "1970-01-01")).TotalSeconds)
            sub = $AppId
        } | ConvertTo-Json -Compress
        
        $headerBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header)) -replace '\+', '-' -replace '/', '_' -replace '='
        $payloadBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)) -replace '\+', '-' -replace '/', '_' -replace '='
        
        $toSign = "$headerBase64.$payloadBase64"
        $toSignBytes = [System.Text.Encoding]::UTF8.GetBytes($toSign)
        
        # Sign with certificate private key
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        $signature = $rsa.SignData($toSignBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $signatureBase64 = [Convert]::ToBase64String($signature) -replace '\+', '-' -replace '/', '_' -replace '='
        
        $jwt = "$headerBase64.$payloadBase64.$signatureBase64"
        
        # Request token
        $body = @{
            client_id             = $AppId
            client_assertion      = $jwt
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            scope                 = "$Resource/.default"
            grant_type            = "client_credentials"
        }
        
        $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
        
        Write-Host "   ✓ Authenticated to $DisplayName`n" -ForegroundColor Green
        
        return $response.access_token
    }
    catch {
        Write-Host "   ❌ Certificate authentication failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Get-DeviceCodeToken {
    param(
        [string]$Resource,
        [string]$DisplayName
    )
function Get-DeviceCodeToken {
    param(
        [string]$Resource,
        [string]$DisplayName
    )
    
    Write-Host "`n🔐 Authenticating to $DisplayName..." -ForegroundColor Yellow
    
    $clientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    
    # Use tenant ID if available, otherwise use "organizations"
    $authEndpoint = if ($script:TenantId) { $script:TenantId } else { "organizations" }
    
    $body = @{
        client_id = $clientId
        scope     = "$Resource/.default offline_access"
    }
    
    try {
        $deviceCode = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$authEndpoint/oauth2/v2.0/devicecode" -Method POST -Body $body
        
        Write-Host "`n  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║  Open: https://microsoft.com/devicelogin" -ForegroundColor Yellow
        Write-Host "  ║  Code: $($deviceCode.user_code)" -ForegroundColor Green
        Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        
        Start-Process "https://microsoft.com/devicelogin"
        Read-Host "`n  Press ENTER after completing login"
        
        $tokenBody = @{
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            client_id   = $clientId
            device_code = $deviceCode.device_code
        }
        
        $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$authEndpoint/oauth2/v2.0/token" -Method POST -Body $tokenBody
        Write-Host "   ✓ Authenticated to $DisplayName`n" -ForegroundColor Green
        
        # Auto-detect tenant if not provided (for first authentication)
        if (-not $script:TenantId -and $response.id_token) {
            try {
                $tokenParts = $response.id_token.Split('.')
                $payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenParts[1] + "=="))
                $claims = $payload | ConvertFrom-Json
                $script:TenantId = $claims.tid
                Write-Host "   ℹ Auto-detected Tenant ID: $($script:TenantId)" -ForegroundColor Gray
            }
            catch {
                Write-Host "   ⚠ Could not auto-detect tenant ID" -ForegroundColor Yellow
            }
        }
        
        return $response.access_token
    }
    catch {
        Write-Host "   ❌ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Get-AuthToken {
    param(
        [string]$Resource,
        [string]$DisplayName
    )
    
    if ($script:UseCertificateAuth) {
        return Get-CertificateToken -Resource $Resource -DisplayName $DisplayName `
                                    -AppId $script:AppId -CertificateThumbprint $script:CertificateThumbprint `
                                    -TenantId $script:TenantId
    } else {
        return Get-DeviceCodeToken -Resource $Resource -DisplayName $DisplayName
    }
}

# ============================================================================
# STEP 1: AZURE RESOURCE GRAPH - GET ALL AGENTS
# ============================================================================

function Get-AllAgents {
    param([string]$Token)
    
    Write-Host "📦 STEP 1: Retrieving agents from Azure Resource Graph..." -ForegroundColor Cyan
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }
    
    $url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"
    
    # Direct KQL query (the working method!)
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
                EnvironmentName   = $props.environmentId  # Will get environment details separately if needed
                EnvironmentType   = "Unknown"  # Azure Resource Graph doesn't join automatically
                EnvironmentRegion = $_.location
                CreatedOn         = if ($props.createdAt) { (Get-Date $props.createdAt).ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                ModifiedOn        = $null  # Not available in Resource Graph
                PublishedOn       = if ($props.lastPublishedAt) { (Get-Date $props.lastPublishedAt).ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                Owner             = $props.ownerId
                CreatedIn         = if ($props.createdIn) { $props.createdIn } else { "Copilot Studio" }
                SolutionId        = $null  # To be filled from Dataverse
                Description       = $null  # To be filled from Dataverse
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
        [string]$Token,
        [array]$Agents
    )
    
    if (-not $IncludeDataverse) {
        Write-Host "⏭️  STEP 3: Skipping Dataverse queries (use -IncludeDataverse to enable)`n" -ForegroundColor Yellow
        return @{}
    }
    
    Write-Host "🗄️  STEP 3: Retrieving Solution ID from Dataverse..." -ForegroundColor Cyan
    Write-Host "   ⚠️ This may take several minutes (per-environment authentication required)" -ForegroundColor Yellow
    Write-Host ""
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Accept"        = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }
    
    $dataverseLookup = @{}
    $environments = $Agents | Select-Object EnvironmentId, EnvironmentName -Unique
    $envCount = 0
    
    foreach ($env in $environments) {
        $envCount++
        Write-Host "   [$envCount/$($environments.Count)] $($env.EnvironmentName)" -ForegroundColor Gray
        
        # Construct Dataverse URL for the environment
        $dataverseUrl = "https://$($env.EnvironmentId).crm.dynamics.com/api/data/v9.2/bots?`$select=botid,name,solutionid,description,schemaname"
        
        try {
            $response = Invoke-RestMethod -Uri $dataverseUrl -Method GET -Headers $headers
            
            if ($response.value) {
                Write-Host "      ✓ Retrieved $($response.value.Count) bot records" -ForegroundColor Green
                
                foreach ($bot in $response.value) {
                    $dataverseLookup[$bot.botid] = @{
                        SolutionId = $bot.solutionid
                        Description = $bot.description
                        SchemaName = $bot.schemaname
                    }
                }
            }
        }
        catch {
            Write-Host "      ⚠ Access denied or environment unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
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
        $dataverseLookup = Get-DataverseData -Token $dataverseToken -Agents $agents
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
    Write-Host "📝 Fields Retrieved:" -ForegroundColor Cyan
    if ($IncludeDataverse -and $withSolutionId -gt 0) {
        Write-Host "   ✅ 10 of 12 fields (Agent Description & Solution ID from Dataverse)" -ForegroundColor Green
        Write-Host "   ❌ Active Users (not available in any API)" -ForegroundColor Yellow
        Write-Host "   ❌ Schema Name (optional field)" -ForegroundColor Yellow
    }
    else {
        Write-Host "   ✅ 8 of 12 fields (Inventory + Licensing APIs)" -ForegroundColor Green
        Write-Host "   ⏭️  2 fields skipped (use -IncludeDataverse for Solution ID & Description)" -ForegroundColor Yellow
        Write-Host "   ❌ Active Users (not available in any API)" -ForegroundColor Yellow
        Write-Host "   ❌ Schema Name (optional field)" -ForegroundColor Yellow
    }
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
