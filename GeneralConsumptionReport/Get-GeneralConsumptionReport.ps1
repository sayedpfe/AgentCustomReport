<#
.SYNOPSIS
    General Copilot Credits Consumption Report - All Resource Types
    
.DESCRIPTION
    Extends the existing AgentCustomReport project to cover ALL Copilot Credits
    consumption across all Power Platform resource types:
      - Copilot Studio Agents
      - Power Automate Cloud Flows (including Agent Flows)
      - Power Apps (Canvas and Model-Driven)
      - Other AI Builder activity
    
    Data source: msdyn_aievents Dataverse table (per environment).
    This is the universal consumption log used by the PPAC AI Builder Activity page.
    
    TWO MODES:
    1. -DiscoverSchema  : Dumps raw msdyn_eventdata JSON samples per environment
                         so you can confirm the actual undocumented field names.
                         Run this FIRST before running the full report.
    
    2. (default)        : Full multi-resource consumption report, using the field
                         names discovered in DiscoverSchema mode.
    
    IMPORTANT — msdyn_eventdata schema is NOT publicly documented by Microsoft.
    The field names used in this script (see $script:EventDataFields) are discovered
    empirically. If you see empty columns in the output, run with -DiscoverSchema
    and adjust the field map at the top of the script.
    
.PARAMETER TenantId
    Azure AD Tenant ID
    Default: b22f8675-8375-455b-941a-67bee4cf7747
    
.PARAMETER LookbackDays
    Number of days of events to retrieve from msdyn_aievents
    Default: 30 (this table can be very large; start small)
    
.PARAMETER Mode
    Execution mode: 'Local' (default) or 'AzureAutomation'
    
.PARAMETER DiscoverSchema
    Dumps the first 5 raw msdyn_eventdata JSON records per environment to
    .\SchemaDiscovery_TIMESTAMP\ folder for inspection.
    Does NOT produce a consumption report.
    
.PARAMETER MaxEventsPerEnvironment
    Maximum msdyn_aievents records to retrieve per environment.
    Default: 1000. Increase for high-volume tenants.
    
.PARAMETER ForceReauth
    Force re-authentication even if a cached refresh token exists.
    
.EXAMPLE
    # Step 1 — discover the actual msdyn_eventdata JSON field names in your tenant
    .\Get-GeneralConsumptionReport.ps1 -DiscoverSchema
    
.EXAMPLE
    # Step 2 — run the full consumption report once field names are confirmed
    .\Get-GeneralConsumptionReport.ps1 -LookbackDays 30
    
.EXAMPLE
    # Wider window with Azure Automation refresh token
    .\Get-GeneralConsumptionReport.ps1 -LookbackDays 90 -Mode AzureAutomation
    
.NOTES
    Version : 1.1
    Author  : AgentCustomReport Project
    Created : 2026-03-17
    Updated : 2026-03-17 — Added IsAgent + SolutionId enrichment; output routed to output\ subfolder
    
    Authentication reuses the same refresh-token cache as Get-CompleteCopilotReport-v1.3.
    Tokens needed:
      - https://api.bap.microsoft.com   (Power Platform Admin API — environment list)
      - https://api.crm.dynamics.com    (Dataverse — msdyn_aievents queries)
    
    Reference: msdyn_aievents is the table behind the PPAC AI Builder Activity page.
    Community reference: github.com/jbaart37/Copilot-Credits-Dashboard
#>

param(
    [ValidateSet('Local', 'AzureAutomation')]
    [string]$Mode = 'Local',

    [string]$TenantId = "b22f8675-8375-455b-941a-67bee4cf7747",

    [int]$LookbackDays = 30,

    [switch]$DiscoverSchema,

    [int]$MaxEventsPerEnvironment = 1000,

    [switch]$ForceReauth = $false
)

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Continue"
$tokenCacheFile = Join-Path $env:USERPROFILE ".copilot-report-tokens.json"

# ============================================================================
# FIELD MAP — UPDATE THESE IF YOUR TENANT USES DIFFERENT JSON KEYS
# Run with -DiscoverSchema first to confirm the actual field names.
# ============================================================================
# FIELD MAP — confirmed from -DiscoverSchema run on 2026-03-17
# The msdyn_eventdata JSON schema in this tenant uses:
#   messageConsumption.consumption  — credit value (float)
#   messageConsumption.units        — message unit count
#   messageConsumption.featureName  — feature description
#   resourceName                    — display name of the resource
#   botSchemaName                   — schema name of the Copilot Studio bot
#   partnerSource                   — MicrosoftCopilotStudio | AIBuilder | ...
#   consumptionSource               — Api | WebChat | Teams | ...
#   llmModelName                    — LLM model used
# ============================================================================
$script:EventDataFields = @{
    # Top-level fields (flat keys in the JSON object)
    ResourceName  = @("resourceName", "ResourceName", "AppName", "FlowName", "Name")
    SourceType    = @("partnerSource", "PartnerSource", "Source", "AppType", "Type")
    Channel       = @("consumptionSource", "ConsumptionSource", "ChannelId", "Channel")
    LLMModel      = @("llmModelName", "LlmModelName", "ModelName")
    BotSchemaName = @("botSchemaName", "BotSchemaName")
    # NOTE: CreditCount is in the nested messageConsumption object — handled specially
    # in ConvertTo-ConsumptionRecord below
}

# Known partnerSource discriminator values
$script:SourceTypeMap = @{
    "MicrosoftCopilotStudio" = "Copilot Studio Agent"
    "CopilotStudio"         = "Copilot Studio Agent"
    "Agent"                 = "Copilot Studio Agent"
    "Bot"                   = "Copilot Studio Agent"
    "PVA"                   = "Copilot Studio Agent"     # Power Virtual Agents (legacy name)
    "AIBuilder"             = "AI Builder"
    "DynamicCodeInterpreter" = "AI Builder"             # AI Builder code interpreter feature
    "Flow"                  = "Power Automate Flow"
    "CloudFlow"             = "Power Automate Flow"
    "Workflow"              = "Power Automate Flow"
    "CanvasApp"             = "Power Apps (Canvas)"
    "Canvas"                = "Power Apps (Canvas)"
    "ModelDrivenApp"        = "Power Apps (Model-Driven)"
}

# ============================================================================
# BANNER
# ============================================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   GENERAL COPILOT CREDITS CONSUMPTION REPORT v1.0                   ║
║   Source: msdyn_aievents (Dataverse) — All Resource Types           ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Mode         : $Mode" -ForegroundColor White
Write-Host "Tenant       : $TenantId" -ForegroundColor Gray
if ($DiscoverSchema) {
    Write-Host "Action       : Schema Discovery (no report will be generated)" -ForegroundColor Yellow
} else {
    Write-Host "Lookback     : $LookbackDays days" -ForegroundColor Gray
    Write-Host "Max events   : $MaxEventsPerEnvironment per environment" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# AUTHENTICATION (reuses v1.3 refresh-token cache)
# ============================================================================

function Start-LocalBrowserAuth {
    param([string]$Resource, [string]$TenantId)

    Write-Host "   🌐 Opening browser for sign-in..." -ForegroundColor Yellow

    $clientId    = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    $redirectUri = "http://localhost:8400"
    $scope       = "$Resource/.default offline_access"

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("$redirectUri/")
    $listener.Start()

    try {
        $codeVerifier = [Convert]::ToBase64String(
            [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
        ) -replace '\+', '-' -replace '/', '_' -replace '='

        $sha256       = [System.Security.Cryptography.SHA256]::Create()
        $codeChallenge = [Convert]::ToBase64String(
            $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($codeVerifier))
        ) -replace '\+', '-' -replace '/', '_' -replace '='

        $state   = [Guid]::NewGuid().ToString()
        $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?" +
                   "client_id=$clientId" +
                   "&response_type=code" +
                   "&redirect_uri=$([Uri]::EscapeDataString($redirectUri))" +
                   "&response_mode=query" +
                   "&scope=$([Uri]::EscapeDataString($scope))" +
                   "&state=$state" +
                   "&code_challenge=$codeChallenge" +
                   "&code_challenge_method=S256"

        Start-Process $authUrl
        Write-Host "   ✓ Browser opened — please sign in" -ForegroundColor Green
        Write-Host "   ⏳ Waiting for callback..." -ForegroundColor Yellow

        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        $successHtml = @"
<html><head><title>Authentication Successful</title></head>
<body style='font-family:Arial;text-align:center;padding:50px'>
    <h1 style='color:green'>✓ Authentication Successful</h1>
    <p>You can close this window and return to PowerShell.</p>
</body></html>
"@
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($successHtml)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()

        $queryParams = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
        $authCode    = $queryParams["code"]

        if (-not $authCode) {
            throw "Authorization code not received. Please complete the sign-in in your browser."
        }

        Write-Host "   ✓ Authorization code received" -ForegroundColor Green

        $tokenBody = @{
            client_id     = $clientId
            scope         = $scope
            code          = $authCode
            redirect_uri  = $redirectUri
            grant_type    = "authorization_code"
            code_verifier = $codeVerifier
        }

        $tokenResponse = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"

        Write-Host "   ✓ Tokens acquired" -ForegroundColor Green
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
    param([string]$RefreshToken, [string]$Resource, [string]$TenantId)

    Write-Host "   🔄 Refreshing cached token..." -ForegroundColor Yellow

    $clientId = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    $body = @{
        client_id     = $clientId
        scope         = "$Resource/.default offline_access"
        refresh_token = $RefreshToken
        grant_type    = "refresh_token"
    }

    try {
        $response = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"

        Write-Host "   ✓ Token refreshed" -ForegroundColor Green
        return @{
            AccessToken  = $response.access_token
            RefreshToken = $response.refresh_token
            ExpiresIn    = $response.expires_in
            Resource     = $Resource
        }
    }
    catch {
        Write-Host "   ⚠ Refresh token expired or invalid — need full auth" -ForegroundColor Yellow
        return $null
    }
}

function Get-CachedRefreshToken {
    param([string]$Resource)

    if ($Mode -eq 'AzureAutomation') {
        $varName = "CopilotReportRefreshToken_$($Resource.Replace('https://', '').Replace('.', '_'))"
        try {
            $rt = Get-AutomationVariable -Name $varName
            if ($rt) { Write-Host "   ✓ Refresh token from Automation Variable" -ForegroundColor Green; return $rt }
        }
        catch {}
        throw "Refresh token not found in Azure Automation Variable '$varName'. Run once interactively first."
    }

    if (Test-Path $tokenCacheFile) {
        $cache = Get-Content $tokenCacheFile | ConvertFrom-Json
        $key   = $Resource.Replace('https://', '').Replace('.', '_')
        if ($cache.$key) {
            Write-Host "   ✓ Cached token found" -ForegroundColor Green
            return $cache.$key.RefreshToken
        }
    }

    Write-Host "   ℹ No cached token found" -ForegroundColor Gray
    return $null
}

function Save-TokenToCache {
    param([string]$Resource, [hashtable]$TokenData)

    if ($Mode -eq 'AzureAutomation') {
        $varName = "CopilotReportRefreshToken_$($Resource.Replace('https://', '').Replace('.', '_'))"
        Set-AutomationVariable -Name $varName -Value $TokenData.RefreshToken
        Write-Host "   ✓ Token stored in Automation Variable: $varName" -ForegroundColor Green
        return
    }

    $cache = @{}
    if (Test-Path $tokenCacheFile) {
        $cache = Get-Content $tokenCacheFile | ConvertFrom-Json -AsHashtable
    }

    $key         = $Resource.Replace('https://', '').Replace('.', '_')
    $cache[$key] = @{
        RefreshToken = $TokenData.RefreshToken
        CachedAt     = (Get-Date).ToString("o")
        ExpiresIn    = $TokenData.ExpiresIn
    }

    $cache | ConvertTo-Json | Set-Content $tokenCacheFile
    Write-Host "   ✓ Token cached: $tokenCacheFile" -ForegroundColor Green
}

function Get-AuthToken {
    param([string]$Resource, [string]$DisplayName)

    Write-Host "`n🔐 Authenticating to $DisplayName ($Resource)..." -ForegroundColor Cyan

    if (-not $ForceReauth) {
        $cached = Get-CachedRefreshToken -Resource $Resource
        if ($cached) {
            $tokenData = Get-RefreshTokenAuth -RefreshToken $cached -Resource $Resource -TenantId $TenantId
            if ($tokenData) {
                Save-TokenToCache -Resource $Resource -TokenData $tokenData
                return $tokenData.AccessToken
            }
        }
    }

    Write-Host "   ℹ Full sign-in required" -ForegroundColor Yellow
    $tokenData = Start-LocalBrowserAuth -Resource $Resource -TenantId $TenantId
    Save-TokenToCache -Resource $Resource -TokenData $tokenData
    return $tokenData.AccessToken
}

# ============================================================================
# STEP 1: GET ENVIRONMENTS WITH DATAVERSE INSTANCES
# ============================================================================

function Get-DataverseEnvironments {
    param([string]$PPToken)

    Write-Host "`n🌍 STEP 1: Retrieving environments with Dataverse..." -ForegroundColor Cyan

    $headers = @{
        "Authorization" = "Bearer $PPToken"
        "Accept"        = "application/json"
    }

    $url  = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments?api-version=2020-10-01&`$expand=properties/linkedEnvironmentMetadata"
    $envs = @()

    try {
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        $all      = if ($response.value) { $response.value } else { @($response) }

        foreach ($env in $all) {
            $instanceUrl = $env.properties.linkedEnvironmentMetadata.instanceUrl
            if ($instanceUrl) {
                # Normalise — ensure no trailing slash
                $instanceUrl = $instanceUrl.TrimEnd('/')
                $envs += [PSCustomObject]@{
                    EnvironmentId   = $env.name
                    EnvironmentName = $env.properties.displayName
                    Region          = $env.location
                    DataverseUrl    = $instanceUrl
                }
            }
        }

        Write-Host "   ✓ Found $($envs.Count) environments with Dataverse instances`n" -ForegroundColor Green
    }
    catch {
        Write-Host "   ❌ Failed to retrieve environments: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    return $envs
}

# ============================================================================
# HELPER: Safe JSON field extraction (undocumented schema)
# ============================================================================

function Get-EventDataField {
    param([object]$EventData, [string[]]$CandidateKeys)

    if ($null -eq $EventData) { return $null }

    foreach ($key in $CandidateKeys) {
        $val = $EventData.PSObject.Properties[$key]
        if ($null -ne $val -and $null -ne $val.Value -and $val.Value -ne "") {
            return $val.Value
        }
    }
    return $null
}

function ConvertTo-FriendlySourceType {
    param([string]$RawValue)

    if (-not $RawValue) { return "Unknown" }

    foreach ($kv in $script:SourceTypeMap.GetEnumerator()) {
        if ($RawValue -like "*$($kv.Key)*") { return $kv.Value }
    }
    return $RawValue   # Return raw value if not mapped — helps discover new types
}

# ============================================================================
# TOKEN HELPER: Get per-environment Dataverse access token
# Root cause fix: Dataverse validates token audience against the environment's
# OWN URL (e.g. https://orgXXX.crm.dynamics.com), not the generic
# https://api.crm.dynamics.com. The cached refresh token is multi-resource so
# we exchange it for an env-specific access token on each environment call.
# ============================================================================

function Get-DataverseEnvToken {
    param([string]$EnvUrl)

    $clientId    = "51f81489-12ee-4a9e-aaae-a2591f45987d"
    $baseResource = "https://api.crm.dynamics.com"

    $rt = Get-CachedRefreshToken -Resource $baseResource
    if (-not $rt) {
        throw "No Dataverse refresh token found. Re-run with -ForceReauth."
    }

    $body = @{
        client_id     = $clientId
        scope         = "$EnvUrl/.default"
        refresh_token = $rt
        grant_type    = "refresh_token"
    }

    try {
        $response = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"

        # Save the rotated refresh token so subsequent environments use the latest one
        Save-TokenToCache -Resource $baseResource -TokenData @{
            RefreshToken = $response.refresh_token
            ExpiresIn    = $response.expires_in
        }

        return $response.access_token
    }
    catch {
        Write-Host "      ⚠ Token exchange failed for $EnvUrl : $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# ============================================================================
# STEP 2: SCHEMA DISCOVERY MODE
# Dumps raw msdyn_eventdata samples so you can see the actual JSON structure
# ============================================================================

function Invoke-SchemaDiscovery {
    param([array]$Environments)

    $timestamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputDir   = Join-Path $scriptDir "SchemaDiscovery_$timestamp"
    New-Item -ItemType Directory -Path $outputDir | Out-Null

    Write-Host "`n🔍 SCHEMA DISCOVERY MODE" -ForegroundColor Yellow
    Write-Host "   Sampling msdyn_aievents records from each environment..." -ForegroundColor Yellow
    Write-Host "   Output folder: $outputDir`n" -ForegroundColor Gray

    $allSamples = @()

    foreach ($env in $Environments) {
        Write-Host "   Sampling: $($env.EnvironmentName)" -ForegroundColor Gray

        # Get a token scoped to THIS environment's URL (fixes audience validation)
        $envToken = Get-DataverseEnvToken -EnvUrl $env.DataverseUrl
        if (-not $envToken) {
            Write-Host "      ⚠ Could not acquire token — skipping" -ForegroundColor Yellow
            continue
        }

        $headers = @{
            "Authorization"    = "Bearer $envToken"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        # Query most recent events — just take a small sample
        $url = "$($env.DataverseUrl)/api/data/v9.2/msdyn_aievents" +
               "?`$select=msdyn_aieventid,msdyn_name,msdyn_eventdata,createdon" +
               "&`$orderby=createdon desc" +
               "&`$top=5"

        try {
            $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
            $records  = $response.value

            if ($records -and $records.Count -gt 0) {
                Write-Host "      ✓ Got $($records.Count) sample records" -ForegroundColor Green

                foreach ($record in $records) {
                    $parsedEventData = $null
                    if ($record.msdyn_eventdata) {
                        try   { $parsedEventData = $record.msdyn_eventdata | ConvertFrom-Json }
                        catch { $parsedEventData = $record.msdyn_eventdata }
                    }

                    $sample = [PSCustomObject]@{
                        Environment      = $env.EnvironmentName
                        EnvironmentId    = $env.EnvironmentId
                        EventId          = $record.msdyn_aieventid
                        EventName        = $record.msdyn_name
                        CreatedOn        = $record.createdon
                        EventDataRaw     = $record.msdyn_eventdata
                        EventDataParsed  = $parsedEventData | ConvertTo-Json -Depth 10
                    }

                    $allSamples += $sample

                    # Also write individual JSON files for easy inspection
                    if ($parsedEventData) {
                        $fileName = "Sample_$($env.EnvironmentId.Substring(0,[Math]::Min(8,$env.EnvironmentId.Length)))_$($record.msdyn_aieventid.Substring(0,[Math]::Min(8,$record.msdyn_aieventid.Length))).json"
                        $parsedEventData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir $fileName) -Encoding UTF8
                    }
                }
            }
            else {
                Write-Host "      ℹ No msdyn_aievents records in this environment" -ForegroundColor Gray
            }
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }

            if ($statusCode -eq 403 -or $statusCode -eq 401) {
                Write-Host "      ⚠ No access to Dataverse in this environment (skip)" -ForegroundColor Yellow
            }
            elseif ($statusCode -eq 404) {
                Write-Host "      ℹ msdyn_aievents table not found (environment may not have AI Builder)" -ForegroundColor Gray
            }
            else {
                Write-Host "      ⚠ Error: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    # Export combined samples
    if ($allSamples.Count -gt 0) {
        $csvPath = Join-Path $outputDir "AllSamples.csv"
        $allSamples | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
        Write-Host "📁 Schema discovery output: $outputDir" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Files written:" -ForegroundColor White
        Write-Host "   • AllSamples.csv    — all samples with EventDataParsed column" -ForegroundColor Gray
        Write-Host "   • Sample_*.json     — individual msdyn_eventdata payloads" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   NEXT STEPS:" -ForegroundColor Cyan
        Write-Host "   1. Open the .json files and identify the field that discriminates" -ForegroundColor White
        Write-Host "      resource type (Agent vs Flow vs App)." -ForegroundColor White
        Write-Host "   2. Identify the field that holds the credit count." -ForegroundColor White
        Write-Host "   3. Identify the field that holds the resource GUID/name." -ForegroundColor White
        Write-Host "   4. Update `$script:EventDataFields at the top of this script." -ForegroundColor White
        Write-Host "   5. Re-run without -DiscoverSchema for the full report." -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
    }
    else {
        Write-Host "`n⚠ No msdyn_aievents records found across all environments." -ForegroundColor Yellow
        Write-Host "   This may mean AI Builder / Copilot Credits have not been used," -ForegroundColor Yellow
        Write-Host "   or the Dataverse token lacks access to these environments." -ForegroundColor Yellow
    }
}

# ============================================================================
# STEP 3: QUERY msdyn_aievents AND PARSE EVENT DATA
# ============================================================================

function Get-AIEvents {
    param(
        [string]$DataverseUrl,
        [string]$EnvironmentName,
        [string]$EnvironmentId,
        [datetime]$FromDate
    )

    # Get token scoped to this specific environment (fixes audience validation)
    $envToken = Get-DataverseEnvToken -EnvUrl $DataverseUrl
    if (-not $envToken) {
        Write-Host "      ⚠ Could not acquire token for '$EnvironmentName' — skipping" -ForegroundColor Yellow
        return @()
    }

    $headers = @{
        "Authorization"    = "Bearer $envToken"
        "Accept"           = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        # Note: Prefer odata.maxpagesize is omitted — some older Dataverse instances return
        # 400 when this header is present. Page size is controlled via $top instead.
    }

    $fromFilter = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")

    $url = "$DataverseUrl/api/data/v9.2/msdyn_aievents" +
           "?`$select=msdyn_aieventid,msdyn_name,msdyn_eventdata,createdon,_msdyn_aimodelid_value" +
           "&`$filter=createdon ge $fromFilter" +
           "&`$orderby=createdon desc" +
           "&`$top=$MaxEventsPerEnvironment"

    $events = @()

    try {
        $page = 1
        $nextLink = $url

        while ($nextLink) {
            $response  = Invoke-RestMethod -Uri $nextLink -Method GET -Headers $headers
            $batch     = $response.value

            if ($batch -and $batch.Count -gt 0) {
                $events += $batch
            }

            # Follow OData next-link only while under the per-env cap
            if ($response.'@odata.nextLink' -and $events.Count -lt $MaxEventsPerEnvironment) {
                $nextLink = $response.'@odata.nextLink'
                $page++
            }
            else {
                $nextLink = $null
            }
        }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }

        if ($statusCode -eq 403 -or $statusCode -eq 401) {
            Write-Host "      ⚠ Access denied to Dataverse in '$EnvironmentName' — skipping" -ForegroundColor Yellow
        }
        elseif ($statusCode -eq 404) {
            Write-Host "      ℹ msdyn_aievents not found in '$EnvironmentName' (no AI Builder)" -ForegroundColor Gray
        }
        else {
            Write-Host "      ⚠ $EnvironmentName — $($_.Exception.Message)" -ForegroundColor Yellow
        }
        return @()
    }

    return $events
}

# ============================================================================
# STEP 4: ENRICH RESOURCES FROM METADATA TABLES
# Returns hashtables: flowLookup, appLookup, botLookup keyed by GUID
# ============================================================================

function Get-ResourceMetadata {
    param([string]$DataverseUrl)

    # Reuse the env-specific token (exchange is cheap, rotation is handled)
    $envToken = Get-DataverseEnvToken -EnvUrl $DataverseUrl
    if (-not $envToken) { return @{ Flows=@{}; Apps=@{}; Bots=@{} } }

    $headers = @{
        "Authorization"    = "Bearer $envToken"
        "Accept"           = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    $flowLookup = @{}
    $appLookup  = @{}
    $botLookup  = @{}

    # Power Automate cloud flows
    try {
        $url      = "$DataverseUrl/api/data/v9.2/workflows?`$select=workflowid,name,category,statecode&`$filter=category eq 5&`$top=5000"
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        foreach ($flow in $response.value) {
            $flowLookup[$flow.workflowid] = @{
                Name     = $flow.name
                Category = $flow.category
                State    = $flow.statecode
            }
        }
    }
    catch { <# Table may not be accessible — continue #> }

    # Canvas apps
    try {
        $url      = "$DataverseUrl/api/data/v9.2/canvasapps?`$select=canvasappid,displayname,apptype&`$top=5000"
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        foreach ($app in $response.value) {
            $appLookup[$app.canvasappid] = @{
                Name    = $app.displayname
                AppType = "Canvas"
            }
        }
    }
    catch { <# Continue #> }

    # Model-driven apps
    try {
        $url      = "$DataverseUrl/api/data/v9.2/appmodules?`$select=appmoduleid,name,uniquename&`$top=5000"
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        foreach ($app in $response.value) {
            $appLookup[$app.appmoduleid] = @{
                Name    = $app.name
                AppType = "Model-Driven"
            }
        }
    }
    catch { <# Continue #> }

    # Copilot Studio bots — include schemaname for matching against botSchemaName in eventdata
    try {
        $url      = "$DataverseUrl/api/data/v9.2/bots?`$select=botid,name,solutionid,schemaname&`$top=5000"
        $response = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
        foreach ($bot in $response.value) {
            $botLookup[$bot.botid] = @{
                Name       = $bot.name
                SolutionId = $bot.solutionid
                SchemaName = $bot.schemaname
            }
        }
    }
    catch { <# Continue #> }

    return @{
        Flows = $flowLookup
        Apps  = $appLookup
        Bots  = $botLookup
    }
}

# ============================================================================
# STEP 5: PARSE EVENTS INTO STRUCTURED CONSUMPTION RECORDS
# ============================================================================

function ConvertTo-ConsumptionRecord {
    param(
        [object]$AIEvent,
        [string]$EnvironmentId,
        [string]$EnvironmentName,
        [hashtable]$ResourceMetadata
    )

    $parsed = $null
    if ($AIEvent.msdyn_eventdata) {
        try { $parsed = $AIEvent.msdyn_eventdata | ConvertFrom-Json }
        catch {
            return [PSCustomObject]@{
                EnvironmentId      = $EnvironmentId
                EnvironmentName    = $EnvironmentName
                EventId            = $AIEvent.msdyn_aieventid
                EventName          = $AIEvent.msdyn_name
                CreatedOn          = $AIEvent.createdon
                SourceTypeRaw      = "ParseError"
                SourceTypeFriendly = "ParseError"
                CreditCount        = 0
                CreditUnits        = 0
                FeatureName        = $null
                IsAgent            = $false
                ResourceId         = $null
                ResourceName       = "(event data not parseable)"
                BotSchemaName      = $null
                SolutionId         = $null
                Channel            = $null
                LLMModel           = $null
                AIModelId          = $AIEvent._msdyn_aimodelid_value
            }
        }
    }

    # Extract credit count from nested messageConsumption object
    $credits = 0
    $units   = 0
    $featureName = $null
    if ($parsed -and $parsed.messageConsumption) {
        try { $credits = [double]$parsed.messageConsumption.consumption } catch {}
        try { $units   = [double]$parsed.messageConsumption.units }        catch {}
        $featureName = $parsed.messageConsumption.featureName
    }

    # Extract flat fields using candidate-key list
    $sourceTypeRaw = Get-EventDataField -EventData $parsed -CandidateKeys $script:EventDataFields.SourceType
    $resourceName  = Get-EventDataField -EventData $parsed -CandidateKeys $script:EventDataFields.ResourceName
    $botSchemaName = Get-EventDataField -EventData $parsed -CandidateKeys $script:EventDataFields.BotSchemaName
    $channel       = Get-EventDataField -EventData $parsed -CandidateKeys $script:EventDataFields.Channel
    $llmModel      = Get-EventDataField -EventData $parsed -CandidateKeys $script:EventDataFields.LLMModel

    # Attempt metadata enrichment — bots table provides a stable resource ID via schemaName
    $resourceId = $null
    $solutionId = $null
    if ($botSchemaName) {
        # Find bot by schemaName in the metadata lookup
        $match = $ResourceMetadata.Bots.GetEnumerator() | Where-Object { $_.Value.Name -eq $resourceName -or $_.Value.SchemaName -eq $botSchemaName } | Select-Object -First 1
        if ($match) {
            $resourceId = $match.Key
            $solutionId = $match.Value.SolutionId
        }
    }
    if (-not $resourceName -and $resourceId) {
        if ($ResourceMetadata.Flows[$resourceId]) { $resourceName = $ResourceMetadata.Flows[$resourceId].Name }
        elseif ($ResourceMetadata.Apps[$resourceId]) { $resourceName = $ResourceMetadata.Apps[$resourceId].Name }
        elseif ($ResourceMetadata.Bots[$resourceId]) { $resourceName = $ResourceMetadata.Bots[$resourceId].Name }
    }

    $friendlyType = ConvertTo-FriendlySourceType -RawValue $sourceTypeRaw

    return [PSCustomObject]@{
        EnvironmentId      = $EnvironmentId
        EnvironmentName    = $EnvironmentName
        EventId            = $AIEvent.msdyn_aieventid
        EventName          = $AIEvent.msdyn_name
        CreatedOn          = $AIEvent.createdon
        SourceTypeRaw      = $sourceTypeRaw
        SourceTypeFriendly = $friendlyType
        CreditCount        = $credits
        CreditUnits        = $units
        FeatureName        = $featureName
        IsAgent            = ($friendlyType -eq "Copilot Studio Agent")
        ResourceId         = $resourceId
        ResourceName       = $resourceName
        BotSchemaName      = $botSchemaName
        SolutionId         = $solutionId
        Channel            = $channel
        LLMModel           = $llmModel
        AIModelId          = $AIEvent._msdyn_aimodelid_value
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    $startTime = Get-Date

    # Authenticate to both APIs needed
    $ppToken = Get-AuthToken `
        -Resource "https://api.bap.microsoft.com" `
        -DisplayName "Power Platform Admin API"

    # Auth to generic Dataverse resource to seed the refresh token in cache.
    # Actual per-environment calls will exchange this refresh token for
    # env-scoped access tokens (required by Dataverse audience validation).
    $null = Get-AuthToken `
        -Resource "https://api.crm.dynamics.com" `
        -DisplayName "Dataverse (token seed)"

    # Get environments
    $environments = Get-DataverseEnvironments -PPToken $ppToken

    if ($environments.Count -eq 0) {
        Write-Host "⚠ No environments with Dataverse found — nothing to query." -ForegroundColor Yellow
        exit 0
    }

    # ── DISCOVERY MODE ──────────────────────────────────────────────────────
    if ($DiscoverSchema) {
        Invoke-SchemaDiscovery -Environments $environments
        exit 0
    }

    # ── FULL REPORT MODE ────────────────────────────────────────────────────
    $fromDate   = (Get-Date).AddDays(-$LookbackDays)
    $allRecords = @()
    $envCount   = 0

    Write-Host "`n📊 STEP 2: Querying msdyn_aievents across all environments..." -ForegroundColor Cyan
    Write-Host "   From: $($fromDate.ToString('yyyy-MM-dd'))  To: $(Get-Date -Format 'yyyy-MM-dd')  ($LookbackDays days)`n" -ForegroundColor Gray

    foreach ($env in $environments) {
        $envCount++
        Write-Host "   [$envCount/$($environments.Count)] $($env.EnvironmentName)" -ForegroundColor Gray

        $events = Get-AIEvents `
            -DataverseUrl   $env.DataverseUrl `
            -EnvironmentName $env.EnvironmentName `
            -EnvironmentId   $env.EnvironmentId `
            -FromDate        $fromDate

        if ($events.Count -gt 0) {
            Write-Host "      ✓ $($events.Count) events — enriching metadata..." -ForegroundColor Green

            $metadata = Get-ResourceMetadata -DataverseUrl $env.DataverseUrl

            foreach ($aiEvent in $events) {
                $record = ConvertTo-ConsumptionRecord `
                    -AIEvent         $aiEvent `
                    -EnvironmentId   $env.EnvironmentId `
                    -EnvironmentName $env.EnvironmentName `
                    -ResourceMetadata $metadata
                $allRecords += $record
            }
        }
        else {
            Write-Host "      ℹ No AI events in this window" -ForegroundColor Gray
        }
    }

    if ($allRecords.Count -eq 0) {
        Write-Host "`n⚠ No msdyn_aievents records found in the $LookbackDays-day window." -ForegroundColor Yellow
        Write-Host "   Suggestions:" -ForegroundColor Yellow
        Write-Host "   • Try -LookbackDays 90 or higher" -ForegroundColor Gray
        Write-Host "   • Run with -DiscoverSchema to check if any records exist at all" -ForegroundColor Gray
        exit 0
    }

    # ── AGGREGATE SUMMARY ───────────────────────────────────────────────────
    Write-Host "`n📈 Aggregating consumption by resource type..." -ForegroundColor Cyan

    # By source type
    $bySourceType = $allRecords |
        Group-Object SourceTypeFriendly |
        ForEach-Object {
            $group = $_.Group
            [PSCustomObject]@{
                "Resource Type"  = $_.Name
                "Event Count"    = $group.Count
                "Total Credits"  = [math]::Round(($group | Measure-Object CreditCount -Sum).Sum, 4)
                "Total Units"    = [math]::Round(($group | Measure-Object CreditUnits -Sum).Sum, 0)
                "Environments"   = ($group | Select-Object -ExpandProperty EnvironmentName -Unique) -join '; '
            }
        } | Sort-Object "Total Credits" -Descending

    # By individual resource (drill-down)
    $byResource = $allRecords |
        Group-Object { "$($_.EnvironmentId)|$($_.ResourceName)|$($_.BotSchemaName)" } |
        ForEach-Object {
            $group = $_.Group
            $first = $group | Select-Object -First 1
            [PSCustomObject]@{
                "Resource Type"    = $first.SourceTypeFriendly
                "Is Agent"         = $first.IsAgent
                "Resource Name"    = $first.ResourceName
                "Bot Schema Name"  = $first.BotSchemaName
                "Resource ID"      = $first.ResourceId
                "Solution ID"      = $first.SolutionId
                "Environment"      = $first.EnvironmentName
                "Channel"          = ($group | Select-Object -ExpandProperty Channel -Unique) -join '; '
                "LLM Model"        = ($group | Select-Object -ExpandProperty LLMModel -Unique) -join '; '
                "Event Count"      = $group.Count
                "Total Credits"    = [math]::Round(($group | Measure-Object CreditCount -Sum).Sum, 4)
                "Total Units"      = [math]::Round(($group | Measure-Object CreditUnits -Sum).Sum, 0)
                "First Event"      = ($group | Sort-Object CreatedOn | Select-Object -First 1).CreatedOn
                "Last Event"       = ($group | Sort-Object CreatedOn -Descending | Select-Object -First 1).CreatedOn
            }
        } | Sort-Object "Total Credits" -Descending

    # ── CONSOLE OUTPUT ──────────────────────────────────────────────────────
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   CONSUMPTION SUMMARY BY RESOURCE TYPE                              ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    $bySourceType | Format-Table -AutoSize -Property @(
        @{Label = "Resource Type";  Expression = { $_."Resource Type" };  Width = 30}
        @{Label = "Events";         Expression = { $_."Event Count" };    Width = 8}
        @{Label = "Total Credits";  Expression = { $_."Total Credits" };  Width = 14}
        @{Label = "Total Units";    Expression = { $_."Total Units" };    Width = 12}
        @{Label = "Environments";   Expression = { $_."Environments" };   Width = 40}
    )

    Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   TOP 20 RESOURCES BY CREDIT CONSUMPTION                            ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    $byResource | Select-Object -First 20 | Format-Table -AutoSize -Property @(
        @{Label = "Type";          Expression = { $_."Resource Type" };   Width = 25}
        @{Label = "Resource Name"; Expression = { $_."Resource Name" };   Width = 30}
        @{Label = "Credits";       Expression = { $_."Total Credits" };   Width = 10}
        @{Label = "Units";         Expression = { $_."Total Units" };     Width = 8}
        @{Label = "Channel";       Expression = { $_."Channel" };         Width = 10}
        @{Label = "LLM Model";     Expression = { $_."LLM Model" };       Width = 25}
        @{Label = "Environment";   Expression = { $_."Environment" };     Width = 22}
    )

    # ── WARN ABOUT UNKNOWN TYPES ─────────────────────────────────────────────
    $unknownTypes = $allRecords | Where-Object { $_.SourceTypeFriendly -eq "Unknown" -or $null -eq $_.SourceTypeRaw }
    if ($unknownTypes.Count -gt 0) {
        $count = $unknownTypes.Count
        Write-Host "⚠ WARNING: $count events had no recognisable source-type discriminator." -ForegroundColor Yellow
        Write-Host "   These appear as 'Unknown' in the report." -ForegroundColor Yellow
        Write-Host "   Run with -DiscoverSchema to inspect the raw eventdata JSON" -ForegroundColor Yellow
        Write-Host "   and update `$script:SourceTypeMap at the top of this script.`n" -ForegroundColor Yellow
    }

    # ── CSV EXPORTS ──────────────────────────────────────────────────────────
    $timestamp   = Get-Date -Format "yyyyMMdd-HHmmss"
    $outputDir   = Join-Path $scriptDir "output"
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

    $summaryFile = Join-Path $outputDir "GeneralConsumption_Summary_${timestamp}.csv"
    $bySourceType | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8
    Write-Host "💾 Summary by resource type : $(Split-Path $summaryFile -Leaf)" -ForegroundColor Cyan

    $detailFile  = Join-Path $outputDir "GeneralConsumption_ByResource_${timestamp}.csv"
    $byResource  | Export-Csv -Path $detailFile -NoTypeInformation -Encoding UTF8
    Write-Host "💾 Detail by resource       : $(Split-Path $detailFile -Leaf)" -ForegroundColor Cyan

    $rawFile     = Join-Path $outputDir "GeneralConsumption_AllEvents_${timestamp}.csv"
    $allRecords  | Export-Csv -Path $rawFile -NoTypeInformation -Encoding UTF8
    Write-Host "💾 Raw events               : $(Split-Path $rawFile -Leaf)" -ForegroundColor Cyan

    Write-Host "   Location: $outputDir`n" -ForegroundColor Gray

    # ── FINAL TOTALS ────────────────────────────────────────────────────────
    $totalCredits = [math]::Round(($allRecords | Measure-Object CreditCount -Sum).Sum, 4)
    $duration     = (Get-Date) - $startTime

    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   TOTALS                                                             ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

    Write-Host "   Total events processed : $($allRecords.Count)" -ForegroundColor White
    Write-Host "   Total credits consumed : $totalCredits" -ForegroundColor White
    Write-Host "   Environments covered   : $($environments.Count)" -ForegroundColor White
    Write-Host "   Date range             : $LookbackDays days" -ForegroundColor White
    Write-Host "   Execution time         : $([math]::Round($duration.TotalMinutes, 1)) minutes`n" -ForegroundColor White

    Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ General consumption report completed!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    }
    exit 1
}
