# Azure AD App Registration Setup Guide

This guide walks you through setting up the Azure AD App Registration required for the Copilot Studio Agent Report Generator.

## What This Tool Does

- **Multi-Environment Mode (Default)**: Discovers ALL environments in your tenant and fetches agents from each
- **Single-Environment Mode**: Queries a single Dataverse environment (use `--single-env` flag)

## Prerequisites

- Azure AD Global Administrator or Application Administrator role
- Power Platform Administrator role (required for multi-environment discovery)
- Dataverse System Administrator role (for creating application users)

---

## Step 1: Create the App Registration

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Microsoft Entra ID** (Azure Active Directory)
3. Click **App registrations** in the left menu
4. Click **+ New registration**

### Registration Details

| Field | Value |
|-------|-------|
| **Name** | `Copilot Studio Agent Reporter` |
| **Supported account types** | `Accounts in this organizational directory only (Single tenant)` |
| **Redirect URI** | Leave blank (not needed for daemon/service apps) |

5. Click **Register**

---

## Step 2: Note the Application IDs

After registration, copy these values for your `config.py`:

| Value | Location | Config Variable |
|-------|----------|-----------------|
| **Application (client) ID** | Overview page | `AZURE_CLIENT_ID` |
| **Directory (tenant) ID** | Overview page | `AZURE_TENANT_ID` |

---

## Step 3: Create Client Secret

1. In your App Registration, go to **Certificates & secrets**
2. Click **+ New client secret**
3. Enter description: `Agent Report Secret`
4. Select expiration: `24 months` (recommended)
5. Click **Add**
6. **⚠️ IMPORTANT**: Copy the **Value** immediately (you won't see it again!)
7. Save this as `AZURE_CLIENT_SECRET` in your `config.py`

---

## Step 4: Configure API Permissions

### 4.1 Add Dataverse Permission (Required)

1. Go to **API permissions**
2. Click **+ Add a permission**
3. Select **APIs my organization uses**
4. Search for and select: `Dataverse` (or `Common Data Service`)
5. Select **Delegated permissions**
6. Check: `user_impersonation`
7. Click **Add permissions**

### 4.2 Add Power Platform API Permission (Required for Multi-Environment)

This permission allows the app to discover all environments in your tenant.

1. Click **+ Add a permission**
2. Select **APIs my organization uses**
3. Search for: `Power Platform API`
4. Select **Application permissions**
5. Add these permissions:
   - `AppManagement.Read.All` (Read environments)
   - Or any available admin permissions

**Alternative - Using BAP API:**

1. Search for: `Microsoft Business Application Platform` or `PowerApps Service`
2. Add appropriate permissions

> **Note**: If these APIs are not visible, you may need to register them first via PowerShell or they may be named differently in your tenant.

### 4.3 Grant Admin Consent

1. Click **Grant admin consent for [Your Org]**
2. Click **Yes** to confirm

Your permissions should look like:

| API | Permission | Type | Status |
|-----|------------|------|--------|
| Dataverse | user_impersonation | Delegated | ✅ Granted |
| Power Platform API | AppManagement.Read.All | Application | ✅ Granted |

---

## Step 5: Assign Power Platform Admin Role

For the app to discover all environments, you need to assign it an admin role:

### Option A: Power Platform Administrator (Recommended)

1. Go to [Microsoft 365 Admin Center](https://admin.microsoft.com)
2. Navigate to **Roles** → **Role assignments**
3. Find **Power Platform Administrator**
4. Add your service principal (search by the App Registration name)

### Option B: Using PowerShell

```powershell
# Connect to Azure AD
Connect-AzureAD

# Get your Service Principal
$sp = Get-AzureADServicePrincipal -Filter "DisplayName eq 'Copilot Studio Agent Reporter'"

# Get the Power Platform Admin role
$role = Get-AzureADDirectoryRole | Where-Object {$_.DisplayName -eq "Power Platform Administrator"}

# Assign the role
Add-AzureADDirectoryRoleMember -ObjectId $role.ObjectId -RefObjectId $sp.ObjectId
```

---

## Step 6: Create Application User in EACH Environment

For multi-environment access, you need to create an Application User in **each Dataverse environment** you want to query.

### Option A: Manual (Per Environment)

Repeat these steps for each environment:

1. Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Select an **Environment**
3. Click **Settings** → **Users + permissions** → **Application users**
4. Click **+ New app user**
5. Click **+ Add an app**
6. Search for: `Copilot Studio Agent Reporter`
7. Select it and click **Add**
8. Select your **Business Unit** (usually root)
9. Click **Create**
10. Assign security role: **System Reader** (minimum for read-only access)

### Option B: PowerShell Script (Batch)

```powershell
# Install the module if needed
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell

# Connect
Add-PowerAppsAccount

# Get all environments
$environments = Get-AdminPowerAppEnvironment

# Your App Registration's Application ID
$appId = "YOUR_CLIENT_ID"

# Create application user in each environment
foreach ($env in $environments) {
    try {
        # This requires the environment to have a Dataverse database
        if ($env.CommonDataServiceDatabaseType -eq "Common Data Service") {
            Write-Host "Creating app user in: $($env.DisplayName)"
            # Note: Actual command depends on your module version
            # New-PowerAppManagementApp -ApplicationId $appId -EnvironmentName $env.EnvironmentName
        }
    } catch {
        Write-Host "Skipped: $($env.DisplayName) - $($_.Exception.Message)"
    }
}
```

### Option C: Using Power Automate (Automated)

Create a flow that:
1. Triggers on schedule
2. Lists all environments
3. Creates application users where missing
4. Assigns security roles

---

## Step 7: Create Custom Security Role (Production)

For least-privilege access, create a custom security role:

### 7.1 Create the Role

1. In PPAC, go to **Settings** → **Users + permissions** → **Security roles**
2. Click **+ New role**
3. Name it: `Copilot Agent Reporter`

### 7.2 Set Permissions

Set **Organization-level Read** permission for these tables:

| Table (Entity) | Read | Notes |
|----------------|------|-------|
| `Bot` (chatbot) | ✅ Organization | Main agents table |
| `Bot Component` | ✅ Organization | For channels |
| `Solution` | ✅ Organization | Solution details |
| `Solution Component` | ✅ Organization | Agent-solution mapping |
| `User` | ✅ Organization | Owner information |
| `Business Unit` | ✅ Organization | BU information |

### 7.3 Assign to Application User

Assign this role to the Application User in each environment.

---

## Step 8: Update config.py

Update your configuration file:

```python
# Azure AD App Registration
AZURE_TENANT_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AZURE_CLIENT_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
AZURE_CLIENT_SECRET = "your-client-secret-value"

# Optional: Filter to specific environments (leave empty for ALL)
ENVIRONMENT_IDS = []

# Optional: Filter by type
ENVIRONMENT_TYPES = ["Production", "Sandbox"]
```

---

## Step 9: Test the Connection

### Test Multi-Environment Mode (Default)

```powershell
cd "d:\OneDrive\OneDrive - Microsoft\Documents\Learning Projects\AgentCustomReport"
.\venv\Scripts\activate
python main.py --no-analytics
```

### Test Single Environment Mode

```powershell
python main.py --single-env
```

---

## Troubleshooting

### Error: Failed to authenticate with Power Platform APIs

- App Registration needs Power Platform Admin role
- Try adding `Power Platform API` permissions explicitly
- Ensure admin consent was granted

### Error: No environments found

- Service Principal lacks Power Platform Admin role
- BAP API permissions not granted
- Try using `--single-env` mode as fallback

### Error: 403 Forbidden from Dataverse

- Application User not created in that environment
- Security role not assigned
- Security role doesn't have Read permission on `bot` table

### Error: Some environments skipped

- Application User missing in those environments
- Environment doesn't have Dataverse database
- Rate limiting (try `--sequential` flag)

### Error: AADSTS700016 - Application not found

- Verify the Client ID is correct
- Ensure the app is in the same tenant as Power Platform

---

## Security Best Practices

### For Production

1. **Use Azure Key Vault** for secrets instead of config.py
2. **Create a custom security role** with minimum required permissions
3. **Use Managed Identity** if running in Azure
4. **Set secret expiration alerts** in Azure
5. **Enable audit logging** for the application user
6. **Rotate secrets** regularly (at least annually)

### Principle of Least Privilege

| Environment Type | Recommended Access |
|-----------------|-------------------|
| Production | Read-only custom role |
| Sandbox | System Reader |
| Development | System Administrator (for testing only) |

---

## Summary Checklist

### Azure AD Setup
- [ ] Created App Registration
- [ ] Noted Tenant ID and Client ID
- [ ] Created Client Secret
- [ ] Added Dataverse API permission
- [ ] Added Power Platform API permissions (multi-env)
- [ ] Granted Admin Consent
- [ ] Assigned Power Platform Admin role (multi-env)

### Per Environment Setup
- [ ] Created Application User
- [ ] Assigned Security Role

### Configuration
- [ ] Updated config.py with credentials
- [ ] Tested connection successfully

---

## Next Steps

Run the report:

```powershell
# All environments (default)
python main.py

# Production environments only
python main.py --env-type Production

# Specific environments
python main.py --environments env-id-1 env-id-2

# Single environment (legacy)
python main.py --single-env
```
