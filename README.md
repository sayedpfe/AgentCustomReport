# Copilot Studio Agent Reporting Solution (v1.2)

This repository provides **PowerShell scripts** and a **web application** to generate comprehensive usage and consumption reports for Copilot Studio agents across Power Platform environments using **Azure Resource Graph** and **Power Platform Licensing APIs**.

## Overview

This solution retrieves agent metadata and consumption data from Azure Resource Graph and Power Platform APIs to create a consolidated report with 8 of the 12 requested fields. The solution uses direct KQL queries through Azure Resource Graph for reliable data retrieval.

**v1.2 Features:**
- ✅ **NEW: ASP.NET Core Web Application** with interactive dashboard
- ✅ Certificate-based authentication (recommended for enterprise/automation)
- ✅ Device Code Flow (backward compatible, interactive)
- ✅ Service principal support for scheduled tasks
- ✅ Refresh token support for Licensing API (web app)
- ✅ Interactive charts and KPI cards (web app)

## Choose Your Solution

| Solution | Best For | Setup Complexity |
|----------|----------|------------------|
| **[Web App](webapp/)** | Teams, on-demand reports, non-technical users | Medium |
| **PowerShell** | Automation, single user, scripts | Low |

---

## Web Application (v1.2) - NEW

A full-featured ASP.NET Core web application with Azure AD authentication and interactive dashboard.

### Features
- Azure AD Single Sign-On
- Real-time agent inventory display
- Credit consumption visualization with Chart.js
- KPI summary cards
- Sortable/filterable/paginated table
- CSV export

### Quick Start (Web App)
```bash
cd webapp/aspnet
dotnet restore
dotnet run
# Navigate to https://localhost:5001
```

### Screenshots
See the [demo video](Video/AgentCustomReport.mp4) for a walkthrough.

### Key Technical Discovery
The Licensing API (`https://licensing.powerplatform.microsoft.com/v0.1-alpha`) **cannot be accessed via standard app registration**. It requires using Microsoft's public client ID (`51f81489-12ee-4a9e-aaae-a2591f45987d`) with Device Code Flow - the same approach used in the PowerShell script.

The web app implements this via:
1. Azure AD SSO for Power Platform Inventory API (standard)
2. Device Code Flow for Licensing API (one-time authorization per session)
3. Encrypted refresh tokens for seamless re-authentication

See [webapp/README.md](webapp/README.md) for detailed setup instructions.

---

## PowerShell Scripts

## Quick Start (PowerShell)

### Interactive Mode (Device Code Flow):
```powershell
.\scripts\Get-CompleteCopilotReport.ps1
```

### Enterprise/Automation Mode (Certificate-Based):
```powershell
.\scripts\Get-CompleteCopilotReport.ps1 `
    -UseCertificateAuth `
    -AppId "YOUR-APP-ID" `
    -CertificateThumbprint "YOUR-CERT-THUMBPRINT" `
    -TenantId "YOUR-TENANT-ID"
```

**📖 Setup Guide:** See [APP_REGISTRATION_SETUP.md](APP_REGISTRATION_SETUP.md) for certificate configuration

This retrieves all 8 available fields in a single execution with automatic authentication handling.

## Available Data Fields (8/12)

| # | Field | Available | Source | Notes |
|---|-------|-----------|--------|-------|
| 1 | Agent Identifier (Primary Key) | ✅ Yes | Azure Resource Graph | Agent GUID |
| 2 | Environment ID | ✅ Yes | Azure Resource Graph | Environment identifier |
| 3 | Agent Name | ✅ Yes | Azure Resource Graph | Agent display name |
| 4 | Agent Description | ❌ No | N/A | Not available in any API |
| 5 | Created At (timestamp) | ✅ Yes | Azure Resource Graph | Creation timestamp |
| 6 | Updated At (timestamp) | ❌ No | N/A | Not exposed by Resource Graph |
| 7 | Solution ID | ❌ No | N/A | Requires Dataverse per-environment query |
| 8 | Agent Owner | ✅ Yes | Azure Resource Graph | Owner identifier |
| 9 | Active Users | ❌ No | N/A | Not available in any API |
| 10 | Billed Copilot Credits | ✅ Yes | Licensing API* | Consumption in MB |
| 11 | Non-Billed Credits | ✅ Yes | Licensing API* | Non-billable consumption in MB |
| 12 | Is Published | ✅ Yes | Azure Resource Graph | Last published timestamp |

**\* Licensing API discovered via browser developer tools - no official documentation available**

## API Endpoints Used

### 1. Azure Resource Graph API (Recommended - Official)
- **Endpoint**: `https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01`
- **Method**: POST with direct KQL query
- **Documentation**: [Azure Resource Graph documentation](https://learn.microsoft.com/en-us/azure/governance/resource-graph/)
- **Authentication**: OAuth 2.0 (Device Code Flow) with Azure Management scope
- **Purpose**: Retrieves Power Platform inventory including agent metadata
- **Advantages**: 
  - Uses direct KQL queries (simpler, more reliable)
  - Official Microsoft API with full documentation
  - Works with standard Azure authentication
  - More stable than preview APIs

**Query Format**:
```json
{
  "query": "PowerPlatformResources\n| where type == 'microsoft.copilotstudio/agents'\n| take 1000"
}
```

**Sample KQL Query**:
```kql
PowerPlatformResources
| where type == 'microsoft.copilotstudio/agents'
| extend properties = parse_json(properties)
| project 
    name,
    location,
    displayName = properties.displayName,
    environmentId = properties.environmentId,
    createdAt = properties.createdAt,
    ownerId = properties.ownerId,
    lastPublishedAt = properties.lastPublishedAt
| take 1000
```

### 2. Licensing API - Credits Consumption (Undocumented)
- **Endpoint**: `https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/{tenantId}/entitlements/MCSMessages/environments/{environmentId}/resources?fromDate={MM-DD-YYYY}&toDate={MM-DD-YYYY}`
- **Method**: GET
- **Documentation**: ⚠️ **None - Discovered via browser developer tools**
- **Authentication**: OAuth 2.0 (Device Code Flow or Certificate-based)
- **Client ID**: `51f81489-12ee-4a9e-aaae-a2591f45987d` (Device Code) or your App Registration ID (Certificate)
- **Purpose**: Retrieves actual consumption data including billed and non-billed credits
- **Date Requirements**: 
  - Dates are **MANDATORY** (API returns empty without them)
  - Format: `MM-DD-YYYY`
  - Recommended range: **365 days** for complete historical data
  - Testing showed 365-day range returns 13x more data than 30-day range (1495 MB vs 112 MB)

**Important Notes**:
- This API is **version 0.1-alpha** (pre-release/unsupported)
- No official Microsoft documentation exists
- Discovered by inspecting network traffic in PPAC browser developer tools (F12)
- May change or be deprecated without notice
- Returns consumption broken down by:
  - Channel (M365 Copilot, Teams, Autonomous)
  - Feature type (Classic answer, Agent flow actions, Generative AI tools)
  - Billable vs Non-billable consumption

## Authentication Methods

### 1. Certificate-Based (Recommended for Enterprise)
**Best for**: Automation, scheduled tasks, production environments

**Setup**: See [APP_REGISTRATION_SETUP.md](APP_REGISTRATION_SETUP.md)

**Usage**:
```powershell
.\scripts\Get-CompleteCopilotReport.ps1 `
    -UseCertificateAuth `
    -AppId "12345678-1234-1234-1234-123456789abc" `
    -CertificateThumbprint "ABCDEF1234567890ABCDEF1234567890ABCDEF12" `
    -TenantId "b22f8675-8375-455b-941a-67bee4cf7747"
```

**Advantages**:
- ✅ Non-interactive (no user login required)
- ✅ Suitable for automation and scheduled tasks
- ✅ Service principal support
- ✅ Enhanced security with certificate credentials
- ✅ No token expiration issues for scheduled runs

**Requirements**:
- Azure AD App Registration
- Certificate uploaded to app registration
- Certificate installed on execution machine
- API permissions configured and admin consent granted

### 2. Device Code Flow (Interactive - Backward Compatible)
**Best for**: Interactive testing, one-time runs, troubleshooting

**Usage**:
```powershell
.\scripts\Get-CompleteCopilotReport.ps1
```

**Advantages**:
- ✅ No setup required
- ✅ Uses standard Microsoft public client
- ✅ Works immediately without configuration

**Limitations**:
- ❌ Requires user browser interaction
- ❌ Not suitable for automation
- ❌ Cannot be used in scheduled tasks

## Scripts

### Get-CompleteCopilotReport.ps1 (Recommended - All-in-One Solution)
Single comprehensive script that retrieves all available data in one execution.

**Features**:
- ✅ Two authentication methods (certificate or device code)
- ✅ Automatic authentication handling (2 auth flows: Azure + Licensing)
- ✅ Uses Azure Resource Graph with direct KQL (most reliable method)
- ✅ Retrieves all 115 agents across all environments
- ✅ Collects credits data with 365-day lookback
- ✅ Smart merging of all data sources
- ✅ Detailed progress indicators and summary statistics
- ✅ Saves timestamped CSV output

**Parameters**:
- `-TenantId`: Azure AD Tenant ID (default: auto-detected from token)
- `-LookbackDays`: Credits lookback period (default: 365 days)
- `-IncludeDataverse`: Include Solution ID/Description from Dataverse (optional, experimental)

**Usage**:
```powershell
# Simple execution (recommended)
.\Get-CompleteCopilotReport.ps1

# With custom lookback
.\Get-CompleteCopilotReport.ps1 -LookbackDays 90

# With Dataverse fields (experimental)
.\Get-CompleteCopilotReport.ps1 -IncludeDataverse
```

**Output**: `CopilotAgents_CompleteReport_TIMESTAMP.csv`
- All 115 agents with 8/12 available fields
- Credits consumption (billed + non-billed)
- Execution summary with statistics

### Legacy Scripts (Optional - Individual Components)

<details>
<summary>Click to expand legacy scripts</summary>

#### Get-AllAgents-InventoryAPI-v2.ps1
Original script using Power Platform Inventory API (Note: KQLOM format may be deprecated).

**Note**: This script may fail due to recent API changes. Use `Get-CompleteCopilotReport.ps1` instead.

#### Get-CopilotCredits-v2.ps1
Standalone credits retrieval using the Licensing API.

**Parameters**:
- `-TenantId`: Azure AD Tenant ID
- `-LookbackDays`: Number of days (default: 365)

**Usage**:
```powershell
.\Get-CopilotCredits-v2.ps1 -LookbackDays 365
```

#### Merge-InventoryAndCredits.ps1
Merges separately generated Inventory and Credits CSV files.

**Usage**:
```powershell
.\Merge-InventoryAndCredits.ps1
```

</details>

## Prerequisites

- PowerShell 5.1 or higher
- Power Platform admin access
- Permissions to authenticate to:
  - `https://api.powerplatform.com`
  - `https://licensing.powerplatform.microsoft.com`

## Authentication

All scripts use **OAuth 2.0 Device Code Flow**:
1. Script displays a device code
2. Browser opens to `https://microsoft.com/devicelogin`
3. Enter the code and authenticate
4. Script continues after authentication

## Workflow

### Recommended: Single Script Execution
```powershell
cd scripts
.\Get-CompleteCopilotReport.ps1
```

This handles everything automatically:
1. Authenticates to Azure Resource Graph
2. Retrieves all 115 agents
3. Authenticates to Licensing API
4. Retrieves credits data (365-day lookback)
5. Merges all data
6. Generates timestamped CSV report

### Alternative: Legacy 3-Step Process

<details>
<summary>Click for manual 3-step workflow</summary>

1. **Run Inventory API script**:
   ```powershell
   .\Get-AllAgents-InventoryAPI-v2.ps1
   ```

2. **Run Credits API script**:
   ```powershell
   .\Get-CopilotCredits-v2.ps1
   ```

3. **Merge the datasets**:
   ```powershell
   .\Merge-InventoryAndCredits.ps1
   ```

**Note**: The Inventory API script may fail due to recent API changes. Use the comprehensive script instead.

</details>

## Limitations & Unavailable Fields

### Fields Not Available via API

1. **Agent Description**
   - Not returned by Azure Resource Graph
   - Not available in any public or discovered API
   - Would require direct Dataverse query per environment

2. **Solution ID**
   - Not returned by Azure Resource Graph
   - Available only via Dataverse query per environment
   - Format: `https://{env}.crm.dynamics.com/api/data/v9.2/bots?$select=solutionid`
   - Requires per-environment authentication and proper region URLs

3. **Active Users**
   - Not available in any API endpoint
   - Microsoft Analytics API only shows aggregate metrics
   - Individual agent user counts not exposed

4. **Updated At (Modified Timestamp)**
   - Not exposed by Azure Resource Graph for agents
   - Known limitation documented by Microsoft

### Tested but Non-Working Approaches

The following approaches were tested but did not provide the required data:

1. **Power Platform Inventory API (KQLOM JSON format)**
   - Initially worked, then broke with API changes
   - Returns "KQLOM format is wrong or it cannot be null" error
   - Microsoft documentation examples also fail
   - **Solution**: Switched to Azure Resource Graph with direct KQL

2. **Official Licensing API** (`/entitlements/MCSMessages/summary`)
   - Returns license capacity (50,000 messages)
   - Does NOT return actual consumption data

3. **Microsoft.PowerPlatform.SDK**
   - .NET SDK does not expose credits/consumption APIs
   - Compilation issues with current SDK version

4. **PPAC Export API** (`/api/PowerPlatform/Environment/Export`)
   - Returns 405 Method Not Allowed
   - Not accessible via public authentication

## Testing Results

### Date Range Impact (Credits API)
| Range | Resources Found | Billed (MB) | Non-Billed (MB) | Total (MB) |
|-------|----------------|-------------|-----------------|------------|
| No dates | 0 | 0 | 0 | 0 |
| 7 days | 0 | 0 | 0 | 0 |
| 30 days | 10 | 14.38 | 98.16 | 112.54 |
| 60 days | 10 | 14.38 | 98.16 | 112.54 |
| 90 days | 10 | 14.38 | 98.16 | 112.54 |
| **365 days** | **29** | **665.58** | **829.81** | **1495.39** |

**Recommendation**: Use 365-day lookback for complete historical data.

### Actual Test Results
- **Total Agents**: 115 (Inventory API)
- **Agents with Usage**: 34 (Credits API)
- **Agents without Usage**: 81
- **Total Consumption**: 5,505.82 MB (3,479.58 billed + 2,026.24 non-billed)
- **Environments**: 8

## Troubleshooting

### Script Errors

**400 Bad Request (Inventory API)**
- Ensure query format matches exact schema
- Do not add `-ContentType` parameter separately (already in headers)

**Empty Results (Credits API)**
- Ensure `fromDate` and `toDate` parameters are included
- Use `MM-DD-YYYY` format
- Try increasing lookback days to 365

**Authentication Fails**
- Ensure you have Power Platform admin access
- Check if conditional access policies are blocking device code flow
- Try using a different browser for authentication

### Common Issues

1. **Credits API returns 404**
   - This is a v0.1-alpha endpoint (unsupported)
   - Endpoint may change without notice
   - Verify endpoint URL matches current PPAC behavior

2. **Different agent counts**
   - Inventory API: Returns ALL agents (115)
   - Credits API: Returns only agents with usage (34)
   - This is expected behavior

3. **Date range confusion**
   - Credits API requires explicit date parameters
   - Default script uses 365-day lookback
   - Adjust `-LookbackDays` parameter as needed

## Data Structure

### Complete Report Schema
```csv
Agent ID, Agent Name, Environment, Environment ID, Environment Type, 
Environment Region, Created On, Modified On, Published On, Owner, 
Created In, Billed Credits (MB), Non-Billed Credits (MB), 
Total Credits (MB), Has Usage
```

### Credits Breakdown
Credits are tracked per:
- **Channel**: M365 Copilot, Teams, Autonomous
- **Feature**: Classic answer, Agent flow actions, Text and generative AI tools
- **Type**: Billed vs Non-billable

## Important Disclaimers

⚠️ **Licensing API Status**
- The Credits API endpoint is **undocumented and unsupported**
- Discovered via browser developer tools (PPAC network traffic)
- Version `0.1-alpha` indicates pre-release status
- May change, break, or be deprecated without notice
- Use at your own risk for production scenarios

⚠️ **Data Accuracy**
- Credits data is point-in-time based on date range
- Historical data may be incomplete for agents created after the lookback period
- Zero credits may indicate no usage OR data not yet available

⚠️ **API Limitations**
- No official SLA or support from Microsoft
- Rate limiting unknown (not documented)
- Tenant-specific data only (no cross-tenant queries)

## Future Improvements

To achieve 12/12 fields, the following would be required:

1. **Dataverse Direct Query** for Solution ID
   - Requires per-environment authentication
   - Query: `dataverse://environments/{env}/tables/bot/rows/{agentId}?columns=solutionid`

2. **Agent Description** 
   - No known API endpoint
   - May require Microsoft to expose this field in Inventory API

3. **Active Users**
   - No known API endpoint
   - Would require Microsoft Analytics API enhancement

## Support

This is a community solution based on reverse-engineered APIs. For official support:
- Power Platform Admin Center: https://admin.powerplatform.microsoft.com
- Power Platform API documentation: https://learn.microsoft.com/power-platform/admin/

## License

MIT License - Use at your own risk

## Version History

- **v1.0** (2026-01-11): Initial release
  - Inventory API integration (6 fields)
  - Credits API integration (2 fields)
  - Merge functionality
  - 8/12 fields available

---

**Documentation Files:**
- README.md - Technical documentation
- EXECUTIVE_SUMMARY.md - Executive summary
- GITHUB_CHECKLIST.md - Implementation guide

**Last Updated**: January 11, 2026
