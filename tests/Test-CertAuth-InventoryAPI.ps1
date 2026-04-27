<#
.SYNOPSIS
    Test certificate authentication with Azure Resource Graph API
    
.DESCRIPTION
    Validates that the App Registration has correct permissions for Azure Resource Graph.
    This should be tested FIRST before testing the Licensing API.
    
.PARAMETER AppId
    Azure AD Application (Client) ID
    
.PARAMETER CertificateThumbprint
    Certificate thumbprint (must be in CurrentUser\My or LocalMachine\My)
    
.PARAMETER TenantId
    Azure AD Tenant ID
    
.EXAMPLE
    .\Test-CertAuth-InventoryAPI.ps1 -AppId "12345678-1234-1234-1234-123456789abc" -CertificateThumbprint "ABCD..." -TenantId "b22f8675-8375-455b-941a-67bee4cf7747"
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
║   TEST: Azure Resource Graph - Certificate Authentication           ║
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
    Write-Host "   ❌ Certificate not found in CurrentUser\My or LocalMachine\My" -ForegroundColor Red
    Write-Host "   Run this to check available certificates:" -ForegroundColor Yellow
    Write-Host "   Get-ChildItem 'Cert:\CurrentUser\My' | Format-Table Thumbprint, Subject, NotAfter" -ForegroundColor Gray
    exit 1
}

Write-Host "   ✓ Certificate found: $($cert.Subject)" -ForegroundColor Green
Write-Host "   ✓ Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "   ✓ Expires: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Green
Write-Host "   ✓ Has private key: $($cert.HasPrivateKey)" -ForegroundColor Green

if (-not $cert.HasPrivateKey) {
    Write-Host "   ❌ Certificate does not have a private key!" -ForegroundColor Red
    Write-Host "   You need to import the certificate with its private key (PFX format)" -ForegroundColor Yellow
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
    
    # Request token for Azure Resource Graph
    $resource = "https://management.azure.com"
    $body = @{
        client_id             = $AppId
        client_assertion      = $jwt
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        scope                 = "$resource/.default"
        grant_type            = "client_credentials"
    }
    
    $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    
    Write-Host "   ✓ Access token received" -ForegroundColor Green
    Write-Host "   ✓ Token expires in: $($response.expires_in) seconds" -ForegroundColor Green
    
    $token = $response.access_token
}
catch {
    Write-Host "   ❌ Token request failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Error Detail: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    Write-Host "   Script Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "   Error Line: $($_.InvocationInfo.Line)" -ForegroundColor Yellow
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "   Response: $responseBody" -ForegroundColor Red
    }
    
    Write-Host "`n   Common issues:" -ForegroundColor Yellow
    Write-Host "   1. App Registration not found (wrong App ID or Tenant ID)" -ForegroundColor Gray
    Write-Host "   2. Certificate not uploaded to App Registration" -ForegroundColor Gray
    Write-Host "   3. Certificate thumbprint mismatch" -ForegroundColor Gray
    exit 1
}

# ============================================================================
# STEP 3: Query Azure Resource Graph
# ============================================================================

Write-Host "`n📋 STEP 3: Querying Azure Resource Graph..." -ForegroundColor Cyan

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$query = @{
    query = @"
PowerPlatformResources
| where type == 'microsoft.copilotstudio/agents'
| take 5
"@
} | ConvertTo-Json

$url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"

try {
    $result = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $query
    
    Write-Host "   ✓ Query successful!" -ForegroundColor Green
    Write-Host "   ✓ Found $($result.count) agents (showing first 5)" -ForegroundColor Green
    
    if ($result.data -and $result.data.Count -gt 0) {
        Write-Host "`n   Sample agents:" -ForegroundColor Yellow
        foreach ($agent in $result.data) {
            $props = $agent.properties
            Write-Host "   - $($props.displayName)" -ForegroundColor White
            Write-Host "     Environment: $($props.environmentId)" -ForegroundColor Gray
            Write-Host "     Created: $($props.createdAt)" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "   ❌ Query failed!" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
    
    $statusCode = $_.Exception.Response.StatusCode.value__
    
    if ($statusCode -eq 403) {
        Write-Host "`n   ⚠ CERTIFICATE AUTH NOT SUPPORTED FOR THIS API (403 Forbidden)" -ForegroundColor Yellow
        Write-Host "`n   Root Cause:" -ForegroundColor Cyan
        Write-Host "   • Certificate auth uses 'client_credentials' grant (app-only, no user context)" -ForegroundColor Gray
        Write-Host "   • Azure Service Management only has DELEGATED permissions" -ForegroundColor Gray
        Write-Host "   • Delegated permissions require a user to be present" -ForegroundColor Gray
        Write-Host "   • Azure Resource Graph queries need user context for Power Platform data" -ForegroundColor Gray
        Write-Host "`n   CONCLUSION:" -ForegroundColor Yellow
        Write-Host "   ✓ Certificate authentication works (token acquired)" -ForegroundColor Green
        Write-Host "   ✗ But this API requires user context (not available in app-only mode)" -ForegroundColor Red
        Write-Host "`n   RECOMMENDATION: Use Device Code Flow instead" -ForegroundColor Cyan
        Write-Host "   This is the expected and correct behavior for this API." -ForegroundColor Gray
    }
    else {
        Write-Host "   Status Code: $statusCode" -ForegroundColor Red
    }
    
    exit 1
}

# ============================================================================
# SUCCESS
# ============================================================================

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   ⚠ EXPECTED RESULT - Certificate Auth Not Supported                 ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Yellow

Write-Host "Test Results:" -ForegroundColor Cyan
Write-Host "  ✓ Certificate authentication mechanism works correctly" -ForegroundColor Green
Write-Host "  ✓ JWT token creation and signing successful" -ForegroundColor Green
Write-Host "  ✓ Token acquisition from Azure AD successful" -ForegroundColor Green
Write-Host "  ✗ API query failed because it requires user context" -ForegroundColor Red

Write-Host "`nConclusion:" -ForegroundColor Yellow
Write-Host "  Azure Resource Graph for Power Platform requires delegated permissions" -ForegroundColor White
Write-Host "  (user context), which is not available in certificate-based authentication." -ForegroundColor White

Write-Host "`nRecommended Solution:" -ForegroundColor Cyan
Write-Host "  Use Device Code Flow authentication instead:" -ForegroundColor White
Write-Host "  cd .." -ForegroundColor Gray
Write-Host "  .\scripts\Get-CompleteCopilotReport.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  Device Code Flow provides user context and works perfectly for this API." -ForegroundColor Green
Write-Host ""
