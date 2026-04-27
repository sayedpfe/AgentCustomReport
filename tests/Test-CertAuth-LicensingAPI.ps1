<#
.SYNOPSIS
    Test certificate authentication with Power Platform Licensing API
    
.DESCRIPTION
    Validates that the App Registration has correct permissions for Power Platform Licensing API.
    Run this AFTER successfully testing the Azure Resource Graph API.
    
.PARAMETER AppId
    Azure AD Application (Client) ID
    
.PARAMETER CertificateThumbprint
    Certificate thumbprint (must be in CurrentUser\My or LocalMachine\My)
    
.PARAMETER TenantId
    Azure AD Tenant ID
    
.EXAMPLE
    .\Test-CertAuth-LicensingAPI.ps1 -AppId "12345678-1234-1234-1234-123456789abc" -CertificateThumbprint "ABCD..." -TenantId "b22f8675-8375-455b-941a-67bee4cf7747"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$AppId,
    
    [Parameter(Mandatory=$true)]
    [string]$CertificateThumbprint,
    
    [Parameter(Mandatory=$true)]
    [string]$TenantId
)

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   TEST: Power Platform Licensing API - Certificate Authentication   ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  App ID:       $AppId" -ForegroundColor Gray
Write-Host "  Certificate:  $CertificateThumbprint" -ForegroundColor Gray
Write-Host "  Tenant ID:    $TenantId" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# STEP 1: Find Certificate
# ============================================================================

Write-Host "📋 STEP 1: Locating certificate..." -ForegroundColor Cyan

$cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
if (-not $cert) {
    $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
}

if (-not $cert) {
    Write-Host "   ❌ Certificate not found" -ForegroundColor Red
    exit 1
}

Write-Host "   ✓ Certificate found: $($cert.Subject)" -ForegroundColor Green
Write-Host "   ✓ Has private key: $($cert.HasPrivateKey)" -ForegroundColor Green

if (-not $cert.HasPrivateKey) {
    Write-Host "   ❌ Certificate does not have a private key!" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 2: Create JWT and Get Token
# ============================================================================

Write-Host "`n📋 STEP 2: Requesting access token..." -ForegroundColor Cyan

try {
    # Create JWT assertion
    $now = [DateTime]::UtcNow
    $exp = $now.AddMinutes(10)
    
    $header = @{
        alg = "RS256"
        typ = "JWT"
        x5t = ([Convert]::ToBase64String($cert.GetCertHash()) -replace '\+', '-' -replace '/', '_').TrimEnd('=')
    } | ConvertTo-Json -Compress
    
    $payload = @{
        aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        exp = [Math]::Floor(($exp.ToUniversalTime() - (Get-Date "1970-01-01").ToUniversalTime()).TotalSeconds)
        iss = $AppId
        jti = [Guid]::NewGuid().ToString()
        nbf = [Math]::Floor(($now.ToUniversalTime() - (Get-Date "1970-01-01").ToUniversalTime()).TotalSeconds)
        sub = $AppId
    } | ConvertTo-Json -Compress
    
    $headerBase64 = ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header)) -replace '\+', '-' -replace '/', '_').TrimEnd('=')
    $payloadBase64 = ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)) -replace '\+', '-' -replace '/', '_').TrimEnd('=')
    
    $toSign = "$headerBase64.$payloadBase64"
    $toSignBytes = [System.Text.Encoding]::UTF8.GetBytes($toSign)
    
    # Sign with certificate private key
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    $signature = $rsa.SignData($toSignBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $signatureBase64 = ([Convert]::ToBase64String($signature) -replace '\+', '-' -replace '/', '_').TrimEnd('=')
    
    $jwt = "$headerBase64.$payloadBase64.$signatureBase64"
    
    Write-Host "   ✓ JWT assertion created and signed" -ForegroundColor Green
    
    # Try multiple resource endpoints for Power Platform
    $resourceAttempts = @(
        "https://licensing.powerplatform.microsoft.com",
        "https://api.powerplatform.com",
        "49676daf-ff23-4e2c-a0f7-e1ff93c85e66"  # Power Platform API App ID
    )
    
    $token = $null
    $successfulResource = $null
    
    foreach ($resource in $resourceAttempts) {
        Write-Host "   Trying resource: $resource" -ForegroundColor Gray
        
        $body = @{
            client_id             = $AppId
            client_assertion      = $jwt
            client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            scope                 = "$resource/.default"
            grant_type            = "client_credentials"
        }
        
        try {
            $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
            $token = $response.access_token
            $successfulResource = $resource
            Write-Host "   ✓ Access token received for: $resource" -ForegroundColor Green
            Write-Host "   ✓ Token expires in: $($response.expires_in) seconds" -ForegroundColor Green
            break
        }
        catch {
            Write-Host "   ⚠ Failed for $resource : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    if (-not $token) {
        throw "Failed to get token for any Power Platform resource"
    }
}
catch {
    Write-Host "   ❌ Token request failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    
    Write-Host "`n   This API might require delegated permissions rather than application permissions." -ForegroundColor Yellow
    Write-Host "   Certificate authentication typically uses client_credentials (app-only) flow." -ForegroundColor Gray
    Write-Host "   The Licensing API may not support this flow." -ForegroundColor Gray
    
    exit 1
}

# ============================================================================
# STEP 3: Get Sample Environment for Testing
# ============================================================================

Write-Host "`n📋 STEP 3: Getting sample environment..." -ForegroundColor Cyan

# First, get an environment ID from Azure Resource Graph
$azureToken = $null
try {
    # Get Azure token to query for environments
    $azureBody = @{
        client_id             = $AppId
        client_assertion      = $jwt
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        scope                 = "https://management.azure.com/.default"
        grant_type            = "client_credentials"
    }
    
    $azureResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $azureBody -ContentType "application/x-www-form-urlencoded"
    $azureToken = $azureResponse.access_token
    
    $azureHeaders = @{
        "Authorization" = "Bearer $azureToken"
        "Content-Type"  = "application/json"
    }
    
    $envQuery = @{
        query = "PowerPlatformResources | where type == 'microsoft.copilotstudio/agents' | take 1 | project environmentId = properties.environmentId"
    } | ConvertTo-Json
    
    $envResult = Invoke-RestMethod -Uri "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01" -Method POST -Headers $azureHeaders -Body $envQuery
    
    if ($envResult.data -and $envResult.data.Count -gt 0) {
        $envId = $envResult.data[0].environmentId
        Write-Host "   ✓ Found sample environment: $envId" -ForegroundColor Green
    }
    else {
        Write-Host "   ⚠ No environments found, using placeholder" -ForegroundColor Yellow
        $envId = "00000000-0000-0000-0000-000000000000"
    }
}
catch {
    Write-Host "   ⚠ Could not get environment, using placeholder" -ForegroundColor Yellow
    $envId = "00000000-0000-0000-0000-000000000000"
}

# ============================================================================
# STEP 4: Query Licensing API
# ============================================================================

Write-Host "`n📋 STEP 4: Querying Licensing API..." -ForegroundColor Cyan

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$endDate = Get-Date
$startDate = $endDate.AddDays(-30)
$fromDate = $startDate.ToString("MM-dd-yyyy")
$toDate = $endDate.ToString("MM-dd-yyyy")

$url = "https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/$TenantId/entitlements/MCSMessages/environments/$envId/resources?fromDate=$fromDate&toDate=$toDate"

Write-Host "   URL: $url" -ForegroundColor Gray

try {
    $result = Invoke-RestMethod -Uri $url -Method GET -Headers $headers
    
    Write-Host "   ✓ Query successful!" -ForegroundColor Green
    
    if ($result.resources -and $result.resources.Count -gt 0) {
        Write-Host "   ✓ Found $($result.resources.Count) resources with consumption data" -ForegroundColor Green
        
        Write-Host "`n   Sample data:" -ForegroundColor Yellow
        $result.resources | Select-Object -First 3 | ForEach-Object {
            Write-Host "   - Resource: $($_.resourceName)" -ForegroundColor White
            Write-Host "     Total Consumption: $($_.totalConsumedQuantity) MB" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "   ⚠ No consumption data found for this environment" -ForegroundColor Yellow
        Write-Host "   This is OK - it means the API is accessible but no data exists" -ForegroundColor Gray
    }
}
catch {
    Write-Host "   ❌ Query failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    
    $statusCode = $_.Exception.Response.StatusCode.value__
    
    if ($statusCode -eq 403 -or $statusCode -eq 401) {
        Write-Host "`n   ⚠ PERMISSION ERROR ($statusCode)" -ForegroundColor Yellow
        Write-Host "`n   The Licensing API likely requires DELEGATED permissions, not APPLICATION permissions." -ForegroundColor Yellow
        Write-Host "   Certificate-based auth uses client_credentials (app-only) flow." -ForegroundColor Gray
        Write-Host "   This API may require user context (delegated flow with Device Code)." -ForegroundColor Gray
        Write-Host "`n   Possible solutions:" -ForegroundColor Cyan
        Write-Host "   1. Use Device Code Flow for Licensing API (current v1.0 approach)" -ForegroundColor White
        Write-Host "   2. Request Microsoft to add application permission support" -ForegroundColor White
        Write-Host "   3. Use a hybrid approach:" -ForegroundColor White
        Write-Host "      - Certificate auth for Azure Resource Graph" -ForegroundColor Gray
        Write-Host "      - Device Code Flow for Licensing API" -ForegroundColor Gray
    }
    else {
        Write-Host "   Status Code: $statusCode" -ForegroundColor Red
    }
    
    Write-Host "`n   Resource used: $successfulResource" -ForegroundColor Gray
    
    exit 1
}

# ============================================================================
# SUCCESS
# ============================================================================

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   ✅ TEST PASSED - Power Platform Licensing API                      ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "Results:" -ForegroundColor Yellow
Write-Host "  ✓ Certificate found and validated" -ForegroundColor Green
Write-Host "  ✓ Token acquired successfully" -ForegroundColor Green
Write-Host "  ✓ Licensing API query succeeded" -ForegroundColor Green
Write-Host "  ✓ App Registration permissions are correct" -ForegroundColor Green

Write-Host "`nYou can now use the main script with certificate authentication:" -ForegroundColor Cyan
Write-Host "  .\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId '$AppId' -CertificateThumbprint '$CertificateThumbprint' -TenantId '$TenantId'" -ForegroundColor White
Write-Host ""
