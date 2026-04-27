# Authentication Options Comparison

This document compares different authentication methods for accessing Azure Resource Graph and Power Platform Licensing APIs.

---

## Quick Decision Matrix

| Need | Best Option |
|------|-------------|
| ✅ Fully automated scheduled reports | **Authorization Code + Refresh Token + Azure Automation** |
| ✅ Manual reports with minimal user interaction | **Authorization Code + Refresh Token (Local)** |
| ✅ Interactive reports (okay with device code each time) | **Device Code Flow** |
| ❌ Zero user interaction ever | **NOT POSSIBLE** (APIs require delegated permissions) |

---

## Option 1: Authorization Code Flow + Refresh Token ⭐ RECOMMENDED

### How It Works

```
User's First Run:
1. Run script locally
2. Browser opens → Sign in to Microsoft
3. OAuth redirects to localhost:8400
4. Script receives authorization code
5. Exchanges code for access token + refresh token
6. Saves refresh token to cache

Subsequent Runs (Local):
1. Script reads cached refresh token
2. Exchanges refresh token for new access token
3. No browser, no user interaction needed
4. Refresh token automatically renewed (90-day validity)

Azure Automation:
1. Store refresh token in encrypted Automation Variable
2. Script runs on schedule
3. Uses cached refresh token for authentication
4. Fully automated, zero user interaction
```

### Pros

✅ **Best User Experience**: Browser-based sign-in (familiar OAuth flow)  
✅ **Automation-Ready**: Refresh tokens work for 90 days without user  
✅ **Azure Automation Compatible**: Store tokens securely in encrypted variables  
✅ **Long-Lived**: Tokens refresh automatically on each use  
✅ **Industry Standard**: Standard OAuth 2.0 authorization code flow with PKCE  
✅ **Secure**: PKCE prevents authorization code interception  

### Cons

⚠️ **Initial Setup Required**: User must sign in once  
⚠️ **Token Management**: Need to update tokens every 90 days (if script doesn't run)  
⚠️ **Local HTTP Listener**: Requires localhost:8400 available for OAuth callback  

### Implementation

- **Script**: `Get-CompleteCopilotReport-v1.2.ps1`
- **Local Mode**: `.\Get-CompleteCopilotReport-v1.2.ps1` (default)
- **Azure Automation Mode**: `.\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation`
- **Force Re-auth**: `.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth`

### Setup Guide

See [AZURE_AUTOMATION_SETUP.md](AZURE_AUTOMATION_SETUP.md)

---

## Option 2: Device Code Flow

### How It Works

```
Every Run:
1. Script starts
2. Displays device code (e.g., "ABC123")
3. User opens browser to https://microsoft.com/devicelogin
4. Enters device code
5. Signs in with Microsoft account
6. Returns to script
7. Script receives access token
8. Runs report generation
```

### Pros

✅ **Simple**: No local HTTP listener required  
✅ **Works Everywhere**: Compatible with remote sessions, SSH, etc.  
✅ **No Token Storage**: No refresh token management needed  
✅ **Secure**: User explicitly consents each time  

### Cons

❌ **Manual Every Time**: User must enter device code for each run  
❌ **Not Automation-Friendly**: Requires human interaction  
❌ **Slow**: ~30-60 seconds per authentication  
❌ **Annoying**: Repetitive for frequent runs  

### Implementation

- **Script**: `Get-CompleteCopilotReport.ps1` (v1.0)
- **Run**: `.\Get-CompleteCopilotReport.ps1`

### When to Use

- One-time reports
- Highly secure environments requiring explicit consent
- Remote/SSH sessions where local HTTP listener won't work

---

## Option 3: Certificate-Based Authentication ❌ NOT SUPPORTED

### Why It Doesn't Work

```
Certificate Auth Flow:
1. Load X.509 certificate with private key
2. Create JWT assertion signed with certificate
3. Exchange JWT for access token (client_credentials grant)
4. ❌ API returns 403 Forbidden

Root Cause:
• Certificate auth = app-only authentication (no user context)
• Azure Resource Graph = requires delegated permissions (user must be present)
• Delegated permissions ≠ compatible with app-only auth
• API design prevents app-only access for Power Platform data
```

### Testing Results

✅ Certificate authentication mechanism works perfectly  
✅ JWT creation and signing successful  
✅ Access token acquired from Azure AD  
❌ Azure Resource Graph API returns 403 Forbidden  
❌ Licensing API also returns 403 Forbidden  

### Conclusion

**Certificate authentication is technically correct but incompatible with these specific APIs.**  
This is not a configuration issue—it's an API design limitation.

### Documentation

See [tests/TESTING_GUIDE.md](tests/TESTING_GUIDE.md) for detailed analysis.

---

## Detailed Comparison

| Feature | Auth Code + Refresh | Device Code | Certificate |
|---------|---------------------|-------------|-------------|
| **User Interaction** | First run only | Every run | Never |
| **Automation** | ✅ Excellent | ❌ Not possible | ⚠️ Would be excellent (but doesn't work) |
| **Security** | ✅ OAuth 2.0 + PKCE | ✅ Explicit consent | ✅ Certificate-based |
| **Setup Complexity** | Medium | Low | Low |
| **Azure Automation** | ✅ Fully supported | ❌ Not compatible | ❌ API limitation |
| **Token Lifetime** | 90 days (auto-renew) | N/A (fresh each time) | N/A (app-only) |
| **API Compatibility** | ✅ Delegated permissions | ✅ Delegated permissions | ❌ Delegated-only APIs |
| **Enterprise Ready** | ✅ Yes | ⚠️ For manual use | ❌ Not for these APIs |

---

## Detailed Technical Breakdown

### Authorization Code Flow + Refresh Token (v1.2)

**Initial Authentication:**
```
1. Generate PKCE code verifier (random 43-128 chars)
2. Create code challenge: Base64URL(SHA256(verifier))
3. Start local HTTP server on localhost:8400
4. Open browser to:
   https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize?
     client_id={appId}
     &response_type=code
     &redirect_uri=http://localhost:8400/callback
     &scope={scopes}
     &code_challenge={challenge}
     &code_challenge_method=S256
5. User signs in → Azure AD redirects to localhost:8400/callback?code={code}
6. HTTP server receives authorization code
7. Exchange code for tokens:
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
     grant_type=authorization_code
     code={code}
     code_verifier={verifier}
     redirect_uri=http://localhost:8400/callback
8. Receive: access_token + refresh_token
9. Save refresh_token to cache
```

**Subsequent Authentications:**
```
1. Read refresh_token from cache
2. Exchange for new access token:
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
     grant_type=refresh_token
     refresh_token={cached_token}
     scope={scopes}
3. Receive: new access_token + new refresh_token
4. Update cache with new refresh_token
5. Use access_token for API calls
```

**Token Cache Structure:**
```json
{
  "management_azure_com": {
    "RefreshToken": "0.AX0A...",
    "LastUpdated": "2025-01-23T10:30:00Z",
    "ExpiresAfter": "2025-04-23T10:30:00Z"
  },
  "licensing_powerplatform_microsoft_com": {
    "RefreshToken": "0.AX0A...",
    "LastUpdated": "2025-01-23T10:30:00Z",
    "ExpiresAfter": "2025-04-23T10:30:00Z"
  }
}
```

### Device Code Flow (v1.0)

**Flow:**
```
1. Request device code:
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/devicecode
     client_id={appId}
     scope={scopes}
2. Receive:
   {
     "device_code": "ABC...XYZ",
     "user_code": "GFED-WQXZ",
     "verification_uri": "https://microsoft.com/devicelogin",
     "expires_in": 900
   }
3. Display to user: "Go to https://microsoft.com/devicelogin and enter: GFED-WQXZ"
4. Poll for completion:
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
     grant_type=urn:ietf:params:oauth:grant-type:device_code
     device_code={device_code}
5. Receive access_token when user completes authentication
```

### Certificate Authentication (v1.1) ❌ NOT COMPATIBLE

**Flow:**
```
1. Load certificate from store:
   Get-ChildItem Cert:\CurrentUser\My\{thumbprint}
2. Create JWT header:
   {
     "alg": "RS256",
     "typ": "JWT",
     "x5t": "{base64_cert_thumbprint}"
   }
3. Create JWT payload:
   {
     "aud": "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
     "iss": "{appId}",
     "sub": "{appId}",
     "jti": "{guid}",
     "nbf": {unix_timestamp},
     "exp": {unix_timestamp + 300}
   }
4. Sign JWT with certificate private key (RS256)
5. Exchange JWT for token:
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
     grant_type=client_credentials
     client_id={appId}
     client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer
     client_assertion={signed_jwt}
     scope={resource}/.default
6. ✅ Receive access_token (works!)
7. ❌ API query returns 403 Forbidden (app-only not supported)
```

**Why 403?**
- `client_credentials` grant = app-only context (no user)
- Azure Service Management has **only delegated permissions** (no application permissions)
- Delegated permissions require user to be present
- App-only authentication has no user context
- Result: 403 Forbidden

---

## API Permission Requirements

### Azure Resource Graph API

**Endpoint**: `https://management.azure.com/providers/Microsoft.ResourceGraph/resources`

**Required Permission**:
- `Azure Service Management` → `user_impersonation` (Delegated)

**Grant Type Support**:
- ✅ `authorization_code` (with user sign-in)
- ✅ `device_code` (with user sign-in)
- ✅ `refresh_token` (after initial user sign-in)
- ❌ `client_credentials` (app-only, no user)

### Power Platform Licensing API

**Endpoint**: `https://licensing.powerplatform.microsoft.com/v0.1-alpha`

**Required Permission**:
- `PowerPlatform.Admin` → Custom scope (Delegated)

**Grant Type Support**:
- ✅ `authorization_code` (with user sign-in)
- ✅ `device_code` (with user sign-in)
- ✅ `refresh_token` (after initial user sign-in)
- ❌ `client_credentials` (app-only, no user)

---

## Migration Guide

### From Device Code (v1.0) to Authorization Code (v1.2)

**No code changes needed! Just switch scripts:**

```powershell
# Old way (Device Code - v1.0)
.\Get-CompleteCopilotReport.ps1

# New way (Authorization Code - v1.2)
.\Get-CompleteCopilotReport-v1.2.ps1
```

**First run** (v1.2):
- Browser opens for sign-in
- Refresh token cached locally

**Second run** (v1.2):
- No browser needed
- Uses cached token
- Fully automated

### From Local to Azure Automation

1. **Run locally first**:
   ```powershell
   .\Get-CompleteCopilotReport-v1.2.ps1
   ```

2. **Extract refresh tokens**:
   ```powershell
   $cache = Get-Content "$env:USERPROFILE\.copilot-report-tokens.json" | ConvertFrom-Json
   $cache.management_azure_com.RefreshToken
   $cache.licensing_powerplatform_microsoft_com.RefreshToken
   ```

3. **Store in Azure Automation** (see [AZURE_AUTOMATION_SETUP.md](AZURE_AUTOMATION_SETUP.md))

4. **Run in Azure Automation**:
   ```powershell
   .\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation
   ```

---

## Frequently Asked Questions

### Q: Why can't certificate auth work with these APIs?

**A**: These APIs only support **delegated permissions**, which require a user to be present. Certificate authentication is app-only (no user), so it's fundamentally incompatible. This is not a configuration issue—it's how the APIs are designed.

### Q: Can I use managed identity in Azure Automation?

**A**: No, for the same reason as certificate auth. Managed identities are app-only and don't have user context.

### Q: How long do refresh tokens last?

**A**: 90 days if not used. But each time you use a refresh token, you get a new one with a fresh 90-day validity. So if your script runs daily, the token never expires.

### Q: Is it safe to store refresh tokens in Azure Automation Variables?

**A**: Yes, Azure Automation Variables can be encrypted. Always enable encryption for tokens.

### Q: What if my refresh token expires?

**A**: Run the script locally with `-ForceReauth` to get a new refresh token, then update Azure Automation Variables.

### Q: Can multiple people use the same refresh token?

**A**: No, refresh tokens are tied to a specific user. Each user needs their own token. For team reports, use a service account or shared admin account.

### Q: Why not use a web application instead?

**A**: You could, but it's more complex (hosting, authentication, UI development). PowerShell + refresh tokens is simpler for automated reporting.

---

## Recommendations

| Scenario | Recommended Approach |
|----------|---------------------|
| **Automated daily/weekly reports** | Auth Code + Refresh Token + Azure Automation |
| **Ad-hoc manual reports** | Device Code Flow OR Auth Code + Refresh Token (Local) |
| **One-time report** | Device Code Flow |
| **Multi-tenant management** | Auth Code + Refresh Token with separate tokens per tenant |
| **Highly secure environment** | Device Code Flow (explicit consent each time) |
| **Remote/SSH session** | Device Code Flow (no local HTTP listener needed) |

---

**Last Updated**: January 23, 2026  
**Version**: 1.2
