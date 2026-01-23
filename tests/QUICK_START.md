# Quick Start: Testing Certificate Authentication

## Goal
Validate that your App Registration is correctly configured for certificate-based authentication **before** running the full report script.

## What You'll Learn
- ✅ Whether Azure Resource Graph works with your certificate (it should!)
- ⚠️ Whether Licensing API supports certificate auth (it might not)
- 🎯 Which authentication method to use for production

## Prerequisites (5 minutes)

You need these three values from Azure Portal:

1. **App ID** (Application/Client ID)
   - Azure Portal → App registrations → Your App → Overview
   - Example: `12345678-1234-1234-1234-123456789abc`

2. **Certificate Thumbprint**
   ```powershell
   # Run this to find your certificate
   Get-ChildItem "Cert:\CurrentUser\My" | Format-Table Thumbprint, Subject, NotAfter
   ```
   - Look for the certificate you created
   - Example: `ABCDEF1234567890ABCDEF1234567890ABCDEF12`

3. **Tenant ID**
   - Azure Portal → Azure Active Directory → Overview → Tenant ID
   - Example: `b22f8675-8375-455b-941a-67bee4cf7747`

## Test 1: Azure Resource Graph (2 minutes)

This should work if your App Registration is configured correctly.

```powershell
cd tests

.\Test-CertAuth-InventoryAPI.ps1 `
    -AppId "PASTE-YOUR-APP-ID-HERE" `
    -CertificateThumbprint "PASTE-YOUR-THUMBPRINT-HERE" `
    -TenantId "PASTE-YOUR-TENANT-ID-HERE"
```

### ✅ Success Looks Like This:
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

**If successful → Proceed to Test 2**

### ❌ If It Fails:

| Error Message | What To Do |
|--------------|------------|
| "Certificate not found" | Check thumbprint is correct: `Get-ChildItem "Cert:\CurrentUser\My"` |
| "Certificate does not have a private key" | Import the .pfx (not .cer) with private key |
| "AADSTS700016: Application not found" | Verify App ID and Tenant ID are correct |
| "403 Forbidden" | Add Azure Service Management permission in Azure Portal |

**Need help?** See [TESTING_GUIDE.md](TESTING_GUIDE.md) for detailed troubleshooting.

## Test 2: Licensing API (2 minutes)

This test will tell you if the Licensing API supports certificate authentication.

```powershell
.\Test-CertAuth-LicensingAPI.ps1 `
    -AppId "PASTE-YOUR-APP-ID-HERE" `
    -CertificateThumbprint "PASTE-YOUR-THUMBPRINT-HERE" `
    -TenantId "PASTE-YOUR-TENANT-ID-HERE"
```

### Possible Results:

#### ✅ Success (Rare but Possible):
```
╔══════════════════════════════════════════════════════════════════════╗
║   ✅ TEST PASSED - Power Platform Licensing API                      ║
╚══════════════════════════════════════════════════════════════════════╝
```
**Great!** You can use full certificate authentication. Skip to "Using Certificate Auth" below.

#### ⚠️ Permission Error (Expected):
```
❌ Query failed!
⚠ PERMISSION ERROR (403)

The Licensing API likely requires DELEGATED permissions, not APPLICATION permissions.
Certificate-based auth uses client_credentials (app-only) flow.
This API may require user context (delegated flow with Device Code).
```

**This is normal.** The Licensing API is undocumented and may not support app-only authentication.

## Your Authentication Options

### If Both Tests Pass ✅
**Use certificate authentication:**
```powershell
cd ..
.\scripts\Get-CompleteCopilotReport.ps1 `
    -UseCertificateAuth `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```

### If Only Test 1 Passes ⚠️ (Most Common)
**Use Device Code Flow (proven to work):**
```powershell
cd ..
.\scripts\Get-CompleteCopilotReport.ps1
```

This requires you to sign in once with a browser, but retrieves all data successfully.

**Why?** The Licensing API requires user context, which certificate authentication doesn't provide.

### If Test 1 Fails ❌
**Fix your App Registration first:**
1. Verify certificate is uploaded to Azure AD
2. Check API permissions are granted
3. Grant admin consent
4. Wait 5 minutes and try again

See [APP_REGISTRATION_SETUP.md](../APP_REGISTRATION_SETUP.md) for setup instructions.

## Summary

| Scenario | Test 1 | Test 2 | Recommended Approach |
|----------|--------|--------|---------------------|
| Best case | ✅ Pass | ✅ Pass | Use certificate auth (fully automated) |
| Common case | ✅ Pass | ❌ Fail | Use Device Code Flow (one login) |
| Setup issue | ❌ Fail | N/A | Fix App Registration first |

## FAQs

**Q: Why does Test 2 fail with 403?**  
A: The Licensing API (v0.1-alpha) is undocumented. It likely requires delegated permissions (user context), which certificate authentication doesn't provide. This is a Microsoft API limitation, not your configuration.

**Q: Can I automate the script if Test 2 fails?**  
A: Not fully. The Device Code Flow requires one-time user login. For scheduled tasks, you'd need to check if Microsoft adds application permissions to the Licensing API.

**Q: Is the Device Code Flow secure?**  
A: Yes. It uses OAuth 2.0 with Microsoft's public client ID. It's the same flow used by many Microsoft tools.

**Q: Will this be fixed in the future?**  
A: We're planning v1.2 with hybrid authentication:
- Certificate auth for Azure Resource Graph (non-interactive)
- Device Code Flow for Licensing API (one-time login)
- Best of both worlds

**Q: What if I need fully automated reporting now?**  
A: Use v1.0 with Device Code Flow. It works reliably and gets all the data. The certificate authentication limitation is only for the Licensing API, not the main Inventory API.

## Next Steps

1. ✅ Run Test 1 (Azure Resource Graph)
2. ⚠️ Run Test 2 (Licensing API)
3. 🎯 Choose authentication method based on results
4. 📊 Generate your report!

For detailed setup instructions, see [APP_REGISTRATION_SETUP.md](../APP_REGISTRATION_SETUP.md).

For troubleshooting, see [TESTING_GUIDE.md](TESTING_GUIDE.md).

---

**Created:** January 23, 2026  
**Version:** 1.1
