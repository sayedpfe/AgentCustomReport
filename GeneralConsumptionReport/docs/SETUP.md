# Setup Guide

This guide covers prerequisites, permissions, and authentication options for running the General Copilot Credits Consumption Report.

---

## Prerequisites

### PowerShell Version

| Version | Support |
|---|---|
| PowerShell 7.2+ | ✅ Recommended |
| Windows PowerShell 5.1 | ✅ Supported |
| PowerShell Core on macOS/Linux | ⚠ Should work; browser sign-in tested on Windows |

Check your version:

```powershell
$PSVersionTable.PSVersion
```

### No modules to install

The script uses only built-in .NET/PowerShell HTTP APIs (`Invoke-RestMethod`, `System.Net.HttpListener`). No `Az`, `MSOnline`, or `Microsoft365DSC` modules are needed.

---

## Required Permissions

The account you sign in with needs the following across your tenant:

| What | Minimum Role |
|---|---|
| List all Power Platform environments | **Power Platform Admin** or **Global Admin** in M365/Entra |
| Query `msdyn_aievents` in each environment | **Environment Viewer** (or any role with read access to `msdyn_aievent` table) |
| Read bot metadata (`bots` table) | Same — **Environment Viewer** is sufficient |

> **Note**: You will see `Access denied to Dataverse in 'X' — skipping` for environments where your account has no access (e.g., personal developer environments owned by another user). This is expected and the script continues with the remaining environments.

---

## Authentication — Interactive Browser Sign-in (Default)

On first run, the script opens a browser window for interactive sign-in using the **PKCE authorization code flow**:

```powershell
.\Get-GeneralConsumptionReport.ps1 -LookbackDays 30
```

1. A browser tab opens to `login.microsoftonline.com`
2. Sign in with your Power Platform Admin account
3. The script captures the authorization code and exchanges it for tokens
4. A refresh token is cached at `~\.copilot-report-tokens.json`

Subsequent runs reuse the cached refresh token — **no browser prompt** unless the token has expired (typically 90 days).

### Clearing the cache

```powershell
# Option 1 — use the built-in flag
.\Get-GeneralConsumptionReport.ps1 -ForceReauth

# Option 2 — delete the cache file manually
Remove-Item ~\.copilot-report-tokens.json
```

### Token cache security

The cache file stores a refresh token scoped to your user account. Treat it like a password:

- It is stored in your user profile (`%USERPROFILE%`), not in the project folder
- Do not commit it to source control (add `*.copilot-report-tokens.json` to `.gitignore`)
- If you share a machine, use `-ForceReauth` before running to ensure you are signed in as the correct account

---

## Authentication — Azure Automation / Unattended Mode

If you want to schedule the report to run automatically (e.g., via Azure Automation or a CI pipeline), use **service principal** authentication.

### Step 1 — Register an Azure AD app

1. Go to [portal.azure.com](https://portal.azure.com) → **Azure Active Directory → App registrations → New registration**
2. Name it something like `CopilotConsumptionReport`
3. Set **Supported account types** to "Accounts in this organizational directory only"
4. No redirect URI needed for client-credentials flow

### Step 2 — Add required API permissions

| API | Permission | Type |
|---|---|---|
| `https://api.bap.microsoft.com` | `user_impersonation` | Delegated (or Application if supported) |
| Dynamics CRM (`https://api.crm.dynamics.com`) | `user_impersonation` | Delegated |

> For fully unattended use: Application permissions require additional configuration in each Dataverse environment — see [Microsoft Docs: Use a service principal with Dataverse](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal).

### Step 3 — Create a client secret

In the app registration → **Certificates & secrets → New client secret**. Copy the value — you will only see it once.

### Step 4 — Run with AzureAutomation mode

```powershell
.\Get-GeneralConsumptionReport.ps1 -Mode AzureAutomation -LookbackDays 30
```

Store the client secret securely in Azure Key Vault or an Azure Automation credential asset, and update the script's `$clientId` / credential retrieval section accordingly.

---

## Proxy / Firewall Requirements

The script makes HTTPS calls to:

| Endpoint | Purpose |
|---|---|
| `login.microsoftonline.com` | Authentication (token endpoint) |
| `api.bap.microsoft.com` | Power Platform Admin API — environment list |
| `*.crm.dynamics.com` | Dataverse per-environment API (each environment has its own subdomain) |

All calls are outbound HTTPS (port 443). No inbound ports are required.

---

## First-Run Checklist

```
□ PowerShell 7+ installed
□ Signed in with a Power Platform Admin account
□ Can access https://admin.powerplatform.microsoft.com in a browser
□ At least one environment in your tenant has Dataverse provisioned
□ Run -DiscoverSchema first to validate msdyn_eventdata field names
```
