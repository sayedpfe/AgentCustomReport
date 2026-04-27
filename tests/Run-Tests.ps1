# Test Certificate Authentication - Configuration Helper
# Run this first to set your values, then run the test scripts

# Your certificate thumbprint (detected automatically)
$thumbprint = "807E06E0BC3AC2AC071B0F1DBF8FD71B5EFDA17F"

# TODO: Fill in your values from Azure Portal
$appId = "74f44fdc-35fa-4b89-b8df-fa150f361f81"  # Example: "12345678-1234-1234-1234-123456789abc"
$tenantId = "b22f8675-8375-455b-941a-67bee4cf7747"  # Your tenant ID

Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   Certificate Authentication - Test Configuration                   ║
╚══════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Certificate Details:" -ForegroundColor Yellow
Write-Host "  ✓ Thumbprint: $thumbprint" -ForegroundColor Green
Write-Host "  ✓ Has Private Key: Yes" -ForegroundColor Green
Write-Host ""

Write-Host "TODO - Get these from Azure Portal:" -ForegroundColor Yellow
Write-Host "  1. Go to https://portal.azure.com" -ForegroundColor White
Write-Host "  2. Search for 'App registrations'" -ForegroundColor White
Write-Host "  3. Click your 'Copilot Studio Agent Reporting' app" -ForegroundColor White
Write-Host "  4. Copy 'Application (client) ID' → Update `$appId above" -ForegroundColor White
Write-Host "  5. Copy 'Directory (tenant) ID' → Update `$tenantId above" -ForegroundColor White
Write-Host ""

if ($appId -eq "YOUR-APP-ID-HERE") {
    Write-Host "⚠ Please update the App ID in this script before testing" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "After updating, run:" -ForegroundColor Cyan
    Write-Host "  .\Run-Tests.ps1" -ForegroundColor White
    exit
}

# Test 1: Azure Resource Graph
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 1: Azure Resource Graph (Inventory API)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

.\Test-CertAuth-InventoryAPI.ps1 -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId

$test1Success = $LASTEXITCODE -eq 0

Write-Host ""
Write-Host "Press ENTER to continue to Test 2..." -ForegroundColor Yellow
Read-Host

# Test 2: Licensing API
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST 2: Power Platform Licensing API" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

.\Test-CertAuth-LicensingAPI.ps1 -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId

$test2Success = $LASTEXITCODE -eq 0

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($test1Success) {
    Write-Host "  ✅ Test 1: Azure Resource Graph - PASSED" -ForegroundColor Green
} else {
    Write-Host "  ❌ Test 1: Azure Resource Graph - FAILED" -ForegroundColor Red
}

if ($test2Success) {
    Write-Host "  ✅ Test 2: Licensing API - PASSED" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Test 2: Licensing API - FAILED (may be expected)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Recommended Authentication Method:" -ForegroundColor Cyan

if ($test1Success -and $test2Success) {
    Write-Host "  ✅ Use CERTIFICATE AUTHENTICATION (both tests passed)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run this command:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor White
    Write-Host "  .\scripts\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId '$appId' -CertificateThumbprint '$thumbprint' -TenantId '$tenantId'" -ForegroundColor White
}
elseif ($test1Success -and -not $test2Success) {
    Write-Host "  ⚠ Use DEVICE CODE FLOW (Licensing API requires user context)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run this command:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor White
    Write-Host "  .\scripts\Get-CompleteCopilotReport.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "  This will prompt you to log in once with a browser." -ForegroundColor Gray
}
else {
    Write-Host "  ❌ Fix App Registration setup first" -ForegroundColor Red
    Write-Host ""
    Write-Host "  See APP_REGISTRATION_SETUP.md for troubleshooting" -ForegroundColor Yellow
}

Write-Host ""
