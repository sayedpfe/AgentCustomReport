# App Registration Setup Guide for Certificate-Based Authentication

This guide explains how to configure Azure AD App Registration with certificate-based authentication for the Copilot Studio Agent Report script.

## Prerequisites

- **Azure AD Admin Access**: Global Administrator or Application Administrator role
- **PowerShell Access**: Ability to run PowerShell scripts on the target machine
- **Certificate**: Self-signed or CA-signed certificate with private key

---

## Step 1: Create Self-Signed Certificate (Optional)

If you don't have a certificate, create a self-signed one:

### Using PowerShell:

```powershell
# Create self-signed certificate
$cert = New-SelfSignedCertificate `
    -Subject "CN=CopilotAgentReporting" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

# Export certificate (without private key) for upload to Azure
$certPath = "$env:TEMP\CopilotAgentReporting.cer"
Export-Certificate -Cert $cert -FilePath $certPath

# Display certificate thumbprint (you'll need this later)
Write-Host "Certificate Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "Certificate exported to: $certPath" -ForegroundColor Yellow
```

**Important Notes:**
- The certificate is stored in `Cert:\CurrentUser\My`
- The thumbprint will be used in the PowerShell script
- The `.cer` file will be uploaded to Azure AD
- Keep the private key secure and never share it

---

## Step 2: Create Azure AD App Registration

### Via Azure Portal:

1. **Navigate to Azure Portal**
   - Go to [https://portal.azure.com](https://portal.azure.com)
   - Search for "Azure Active Directory" or "Microsoft Entra ID"

2. **Create App Registration**
   - Click **App registrations** → **+ New registration**
   - **Name**: `Copilot Studio Agent Reporting`
   - **Supported account types**: "Accounts in this organizational directory only"
   - **Redirect URI**: Leave blank
   - Click **Register**

3. **Note the Application Details**
   - **Application (client) ID**: Copy this (e.g., `12345678-1234-1234-1234-123456789abc`)
   - **Directory (tenant) ID**: Copy this (e.g., `b22f8675-8375-455b-941a-67bee4cf7747`)

---

## Step 3: Upload Certificate to App Registration

1. **In your App Registration**, go to **Certificates & secrets**
2. Click **Certificates** tab → **Upload certificate**
3. Select the `.cer` file exported in Step 1
4. Add a description: "Copilot Agent Reporting Certificate"
5. Click **Add**

**Verify:** You should see the certificate with its thumbprint matching Step 1.

---

## Step 4: Configure API Permissions

### Required Permissions:

The app needs access to two APIs. **IMPORTANT**: Test each API separately to validate permissions.

#### 4.1 Azure Service Management (Azure Resource Graph)

1. Click **API permissions** → **+ Add a permission**
2. Select **Azure Service Management**
3. Select **Delegated permissions** → **user_impersonation**
4. Click **Add permissions**

**✅ Test this first**: Run `.\tests\Test-CertAuth-InventoryAPI.ps1` to validate

> **Note:** Azure Resource Graph works with both delegated and application permissions. Certificate-based auth uses client_credentials flow (app-only). If you experience issues, ensure the permission is granted and admin consent is provided.

#### 4.2 Power Platform API (Licensing) - ⚠️ EXPERIMENTAL

**IMPORTANT**: The Power Platform Licensing API may not support application (app-only) permissions required for certificate-based authentication.

**Recommendation for v1.1**: Use **hybrid authentication**:
- ✅ Certificate auth for Azure Resource Graph (works perfectly)
- ✅ Device Code Flow for Licensing API (requires user interaction)

If you still want to try certificate auth for Licensing API:

1. Click **API permissions** → **+ Add a permission**
2. Select **APIs my organization uses**
3. Search for one of these:
   - `Power Platform API` (App ID: `49676daf-ff23-4e2c-a0f7-e1ff93c85e66`)
   - `licensing.powerplatform.microsoft.com`
4. Check available permissions:
   - Try **Application permissions** (if available)
   - Or **Delegated permissions** (may not work with certificate auth)
5. Click **Add permissions**

**✅ Test this**: Run `.\tests\Test-CertAuth-LicensingAPI.ps1` to validate

> **Known Limitation**: The Licensing API is v0.1-alpha and undocumented. It may require delegated permissions with user context, which doesn't work with certificate-based (app-only) authentication. If this fails, use Device Code Flow for this API specifically.

#### 4.3 (Optional) Dataverse

If using `-IncludeDataverse` switch:

1. Click **+ Add a permission**
2. Search for: `Dataverse` or `Common Data Service`
3. Select **Delegated permissions** → **user_impersonation**
4. Click **Add permissions**

### Grant Admin Consent

**CRITICAL STEP:**
1. Click **Grant admin consent for [Your Organization]**
2. Confirm by clicking **Yes**
3. Verify all permissions show **✓ Granted for [Your Organization]**

---

## Step 5: Configure Application Settings (Optional)

### Token Configuration:

1. Go to **Token configuration**
2. Click **+ Add optional claim**
3. Select **Access token**
4. Check: `email`, `preferred_username`, `upn`
5. Click **Add**

This improves logging and debugging.

---

## Step 6: Test Authentication

**IMPORTANT**: Test each API separately to identify permission issues.

### Test 1: Azure Resource Graph (Inventory API)

```powershell
.\tests\Test-CertAuth-InventoryAPI.ps1 `
    -AppId "YOUR-APP-ID-HERE" `
    -CertificateThumbprint "YOUR-CERTIFICATE-THUMBPRINT-HERE" `
    -TenantId "YOUR-TENANT-ID-HERE"
```

**Expected Result**: Should retrieve sample agents successfully.

**If this fails**, check:
- Certificate is uploaded to App Registration
- Azure Service Management permission is granted
- Admin consent is provided

### Test 2: Power Platform Licensing API

```powershell
.\tests\Test-CertAuth-LicensingAPI.ps1 `
    -AppId "YOUR-APP-ID-HERE" `
    -CertificateThumbprint "YOUR-CERTIFICATE-THUMBPRINT-HERE" `
    -TenantId "YOUR-TENANT-ID-HERE"
```

**Expected Result**: May succeed or may return 401/403 error.

**If this fails with 401/403**: This is expected. The Licensing API likely requires delegated permissions (user context), not application permissions (app-only). See "Hybrid Authentication" section below.

### Test 3: Full Script

Once both tests pass, run the complete script:

```powershell
.\Get-CompleteCopilotReport.ps1 `
    -UseCertificateAuth `
    -AppId "YOUR-APP-ID-HERE" `
    -CertificateThumbprint "YOUR-CERTIFICATE-THUMBPRINT-HERE" `
    -TenantId "YOUR-TENANT-ID-HERE"
```

### Expected Output:

```
╔══════════════════════════════════════════════════════════════════════╗
║   COMPLETE COPILOT STUDIO AGENT REPORT v1.1                         ║
║   Certificate-Based & Device Code Authentication                    ║
╚══════════════════════════════════════════════════════════════════════╝

🔒 Authentication Mode: Certificate-based (Non-interactive)
   App ID: 12345678-1234-1234-1234-123456789abc
   Certificate: ABCDEF1234567890ABCDEF1234567890ABCDEF12

🔐 Authenticating to Azure Resource Graph (Certificate)...
   ✓ Certificate found: CN=CopilotAgentReporting
   ✓ Authenticated to Azure Resource Graph

🔐 Authenticating to Power Platform Licensing API (Certificate)...
   ✓ Certificate found: CN=CopilotAgentReporting
   ✓ Authenticated to Power Platform Licensing API
```

---

## Troubleshooting

### Error: "Certificate not found"

**Cause:** Certificate not in CurrentUser\My or LocalMachine\My store.

**Solution:**
```powershell
# Check certificate exists
Get-ChildItem "Cert:\CurrentUser\My" | Where-Object { $_.Thumbprint -eq "YOUR-THUMBPRINT" }

# If not found, reimport certificate with private key
$pfxPassword = ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText
Import-PfxCertificate -FilePath "C:\Path\To\Certificate.pfx" -CertStoreLocation "Cert:\CurrentUser\My" -Password $pfxPassword
```

### Error: "Insufficient privileges to complete the operation"

**Cause:** Missing API permissions or admin consent not granted.

**Solution:**
1. Verify API permissions are configured (Step 4)
2. Ensure **admin consent** is granted (green checkmarks)
3. Wait 5-10 minutes for permissions to propagate

### Error: "AADSTS700016: Application not found"

**Cause:** Incorrect App ID or app not registered in tenant.

**Solution:**
- Verify App ID from Azure Portal → App registrations
- Ensure using the correct Tenant ID
- Check app is not deleted or expired

### Error: "AADSTS50027: JWT token is invalid or malformed"

**Cause:** Certificate mismatch or certificate not uploaded to app registration.

**Solution:**
1. Verify certificate thumbprint matches in both:
   - Local machine: `Get-ChildItem "Cert:\CurrentUser\My\YOUR-THUMBPRINT"`
   - Azure Portal: App registration → Certificates & secrets
2. Re-upload certificate if needed

### Error: "The credentials in the request are invalid"

**Cause:** Certificate doesn't have a private key or private key is not accessible.

**Solution:**
```powershell
# Check if certificate has private key
$cert = Get-Item "Cert:\CurrentUser\My\YOUR-THUMBPRINT"
$cert.HasPrivateKey  # Should return True

# If False, reimport certificate with private key (PFX format)
```

---

## Hybrid Authentication Approach (Recommended for v1.1)

If the Licensing API test fails with permission errors, use this hybrid approach:

### Why Hybrid?

The Power Platform Licensing API (v0.1-alpha) is undocumented and may require **delegated permissions** (user context), which doesn't work with certificate-based authentication (app-only flow). 

**Solution**: Use the best authentication method for each API:
- ✅ **Azure Resource Graph**: Certificate-based (non-interactive)
- ✅ **Licensing API**: Device Code Flow (one-time user login)

### Implementation

The main script will need to be modified to support hybrid authentication. For now, use one of these approaches:

#### Option 1: Full Certificate Auth (if both tests pass)
```powershell
.\Get-CompleteCopilotReport.ps1 `
    -UseCertificateAuth `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```

#### Option 2: Device Code Flow (v1.0 compatibility)
```powershell
.\Get-CompleteCopilotReport.ps1
```

#### Option 3: Wait for v1.2 (Hybrid Mode)
Future version will support:
```powershell
.\Get-CompleteCopilotReport.ps1 `
    -UseHybridAuth `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```
This will use certificate for Azure Resource Graph and fall back to Device Code for Licensing API.

---

## Security Best Practices

### Certificate Management:
- ✅ **Store certificates in secure locations** (CurrentUser\My for user context, LocalMachine\My for system)
- ✅ **Use strong passwords** for PFX exports
- ✅ **Rotate certificates** before expiration (set reminders)
- ✅ **Monitor certificate expiration** (typically 1-2 years)
- ❌ **Never commit certificates** to source control

### App Registration:
- ✅ **Use least-privilege permissions** (only what's needed)
- ✅ **Regular permission audits** (quarterly review)
- ✅ **Monitor sign-in logs** (Azure AD → App registrations → Sign-in logs)
- ✅ **Enable Conditional Access** if available
- ❌ **Avoid granting excessive permissions**

### Script Execution:
- ✅ **Use dedicated service accounts** for automated tasks
- ✅ **Restrict script access** (file system permissions)
- ✅ **Log all executions** (transcript or custom logging)
- ✅ **Encrypt output files** if containing sensitive data
- ❌ **Never hardcode certificates or secrets** in scripts

---

## Automation Scenarios

### Scheduled Task (Windows):

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"D:\Scripts\Get-CompleteCopilotReport.ps1`" -UseCertificateAuth -AppId `"YOUR-APP-ID`" -CertificateThumbprint `"YOUR-THUMBPRINT`" -TenantId `"YOUR-TENANT-ID`""

$trigger = New-ScheduledTaskTrigger -Daily -At 6AM

$principal = New-ScheduledTaskPrincipal -UserId "DOMAIN\ServiceAccount" -LogonType Password

Register-ScheduledTask -TaskName "Copilot Agent Report" -Action $action -Trigger $trigger -Principal $principal
```

### Azure Automation Runbook:

Store certificate in **Automation Account → Certificates**:

```powershell
# In runbook
$cert = Get-AutomationCertificate -Name "CopilotReporting"
$thumbprint = $cert.Thumbprint
$appId = Get-AutomationVariable -Name "CopilotReportingAppId"
$tenantId = Get-AutomationVariable -Name "CopilotReportingTenantId"

.\Get-CompleteCopilotReport.ps1 -UseCertificateAuth -AppId $appId -CertificateThumbprint $thumbprint -TenantId $tenantId
```

---

## Comparison: Certificate vs Device Code

| Feature | Certificate-Based | Device Code Flow |
|---------|------------------|------------------|
| **User Interaction** | None (fully automated) | Required (browser login) |
| **Setup Complexity** | High (App Registration + Certificate) | Low (no setup) |
| **Security** | High (certificate-based) | Medium (delegated permissions) |
| **Automation** | ✅ Excellent | ❌ Not suitable |
| **Scheduled Tasks** | ✅ Supported | ❌ Not supported |
| **Token Expiration** | 60-90 minutes (re-auth automatically) | 60-90 minutes (requires re-login) |
| **Best For** | Production, automation, scheduled tasks | Interactive testing, one-time runs |

---

## Additional Resources

- [Microsoft Identity Platform - Certificate credentials](https://learn.microsoft.com/en-us/azure/active-directory/develop/active-directory-certificate-credentials)
- [Azure AD App Registration best practices](https://learn.microsoft.com/en-us/azure/active-directory/develop/security-best-practices-for-app-registration)
- [PowerShell with Azure AD](https://learn.microsoft.com/en-us/powershell/azure/authenticate-azureps)

---

## Support

For issues or questions:
1. Check **Troubleshooting** section above
2. Review Azure AD sign-in logs for authentication failures
3. Verify API permissions and admin consent
4. Consult the [README.md](README.md) for general script usage

---

**Last Updated:** January 16, 2026  
**Version:** 1.1
