# Testing Guide for Certificate Authentication

This guide helps you test certificate-based authentication step-by-step.

## Prerequisites

1. **Certificate created** (see APP_REGISTRATION_SETUP.md Step 1)
2. **App Registration created** (see APP_REGISTRATION_SETUP.md Step 2)
3. **Certificate uploaded** to App Registration (see APP_REGISTRATION_SETUP.md Step 3)

## Test Sequence

### Step 1: Test Azure Resource Graph API ✅

This API typically works well with certificate authentication.

```powershell
cd tests
.\Test-CertAuth-InventoryAPI.ps1 `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-CERT-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```

**Expected Success Output:**
```
╔══════════════════════════════════════════════════════════════════════╗
║   ✅ TEST PASSED - Azure Resource Graph                              ║
╚══════════════════════════════════════════════════════════════════════╝

Results:
  ✓ Certificate found and validated
  ✓ Token acquired successfully
  ✓ Azure Resource Graph query succeeded
  ✓ App Registration permissions are correct
```

**If this fails:**

| Error | Cause | Solution |
|-------|-------|----------|
| Certificate not found | Thumbprint wrong or cert not installed | Run: `Get-ChildItem "Cert:\CurrentUser\My" \| Format-Table Thumbprint, Subject` |
| AADSTS700016 | Wrong App ID or Tenant ID | Verify IDs in Azure Portal |
| AADSTS50027 | Certificate not uploaded to app | Upload .cer file to App Registration |
| 403 Forbidden | Missing API permissions | Add Azure Service Management permission + admin consent |

### Step 2: Test Power Platform Licensing API ⚠️

This API may NOT support certificate authentication.

```powershell
.\Test-CertAuth-LicensingAPI.ps1 `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-CERT-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```

**Possible Outcomes:**

#### Outcome A: Success ✅
```
╔══════════════════════════════════════════════════════════════════════╗
║   ✅ TEST PASSED - Power Platform Licensing API                      ║
╚══════════════════════════════════════════════════════════════════════╝
```
**Action**: You can use full certificate authentication! Proceed to main script.

#### Outcome B: Permission Error (401/403) ⚠️
```
❌ Query failed!
⚠ PERMISSION ERROR (403)

The Licensing API likely requires DELEGATED permissions, not APPLICATION permissions.
```

**Action**: This is expected. The Licensing API requires user context. Use Device Code Flow for this API.

**Why this happens:**
- Certificate auth uses `client_credentials` grant (app-only, no user)
- Licensing API is v0.1-alpha and undocumented
- It likely requires delegated permissions (user context)
- Delegated permissions need an actual user to sign in

**Your options:**
1. Use full Device Code Flow (v1.0 approach) - works perfectly
2. Wait for Microsoft to add application permissions
3. Use hybrid approach (future v1.2 feature)

## Troubleshooting Matrix

### Azure Resource Graph Issues

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| Token acquired but query fails (403) | Missing API permission | Add "Azure Service Management" → "user_impersonation" |
| JWT token invalid | Certificate thumbprint mismatch | Verify cert uploaded to Azure matches local cert |
| Certificate has no private key | Wrong export format (.cer vs .pfx) | Import .pfx with private key |

### Licensing API Issues

| Symptom | Root Cause | Fix |
|---------|------------|-----|
| 401 Unauthorized | API requires delegated permissions | Use Device Code Flow instead |
| Token request fails | No suitable resource endpoint | API may not support app-only auth |
| 403 Forbidden | Similar to 401 | Use Device Code Flow instead |

## Decision Tree

```
Certificate Auth Tests
│
├─ Test 1: Azure Resource Graph
│  │
│  ├─ ✅ PASS → Continue to Test 2
│  │
│  └─ ❌ FAIL → Fix permissions/certificate
│     └─ See troubleshooting table
│
└─ Test 2: Licensing API
   │
   ├─ ✅ PASS → Use full certificate auth
   │  └─ Run: Get-CompleteCopilotReport.ps1 -UseCertificateAuth ...
   │
   └─ ❌ FAIL (401/403) → Expected
      └─ Options:
         ├─ 1. Use Device Code Flow (proven to work)
         │  └─ Run: Get-CompleteCopilotReport.ps1 (no params)
         │
         ├─ 2. Try different permission
         │  └─ Check Azure Portal for other Power Platform APIs
         │
         └─ 3. Wait for v1.2 hybrid mode
            └─ Will use cert for Graph, device code for Licensing
```

## Quick Reference

### Get Your Values

```powershell
# App ID and Tenant ID
# Go to Azure Portal → App registrations → Your App
# Copy "Application (client) ID" and "Directory (tenant) ID"

# Certificate Thumbprint
Get-ChildItem "Cert:\CurrentUser\My" | 
    Where-Object { $_.Subject -like "*CopilotAgentReporting*" } |
    Select-Object Thumbprint, Subject, NotAfter

# OR if you know partial thumbprint
Get-ChildItem "Cert:\CurrentUser\My" | 
    Where-Object { $_.Thumbprint -like "ABCD*" } |
    Format-Table Thumbprint, Subject, NotAfter
```

### Test Commands Template

```powershell
# Variables (fill these in)
$appId = "YOUR-APP-ID-HERE"
$thumbprint = "YOUR-CERT-THUMBPRINT-HERE"
$tenantId = "YOUR-TENANT-ID-HERE"

# Test 1: Azure Resource Graph
.\tests\Test-CertAuth-InventoryAPI.ps1 -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId

# Test 2: Licensing API
.\tests\Test-CertAuth-LicensingAPI.ps1 -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId

# If both pass: Run main script
..\scripts\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId
```

## Next Steps

### If Both Tests Pass ✅
You have full certificate authentication working! Use the main script with `-UseCertificateAuth`.

### If Only Test 1 Passes ⚠️
This is the expected scenario for most tenants. The Licensing API requires user context.

**Recommended**: Use Device Code Flow (v1.0) which is proven to work:
```powershell
.\Get-CompleteCopilotReport.ps1
```

**Future**: v1.2 will support hybrid authentication (cert + device code).

### If Test 1 Fails ❌
Fix the App Registration setup before proceeding:
1. Verify certificate is uploaded
2. Check API permissions
3. Grant admin consent
4. Wait 5-10 minutes for propagation

---

**Last Updated:** January 23, 2026  
**Version:** 1.1
