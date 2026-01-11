# Copilot Studio Agent Reporting Solution

This repository provides PowerShell scripts to generate comprehensive usage and consumption reports for Copilot Studio agents across Power Platform environments.

## Overview

This solution retrieves agent metadata and consumption data from Power Platform APIs to create a consolidated report with 8 of the 12 requested fields. The remaining fields are not available through any public or discoverable API endpoints.

## Available Data Fields (8/12)

| # | Field | Available | Source | Notes |
|---|-------|-----------|--------|-------|
| 1 | Agent Identifier (Primary Key) | ✅ Yes | Inventory API | `Item ID` field |
| 2 | Environment ID | ✅ Yes | Inventory API | Environment identifier |
| 3 | Agent Name | ✅ Yes | Inventory API | Agent display name |
| 4 | Agent Description | ❌ No | N/A | Not available in any API |
| 5 | Created At (timestamp) | ✅ Yes | Inventory API | `Created on` field |
| 6 | Updated At (timestamp) | ✅ Yes | Inventory API | `Modified on` field |
| 7 | Solution ID | ❌ No | N/A | Requires Dataverse per-environment query |
| 8 | Agent Owner | ✅ Yes | Inventory API | Owner identifier |
| 9 | Active Users | ❌ No | N/A | Not available in any API |
| 10 | Billed Copilot Credits | ✅ Yes | Licensing API* | Consumption in MB |
| 11 | Non-Billed Credits | ✅ Yes | Licensing API* | Non-billable consumption in MB |
| 12 | Is Published | ✅ Yes | Inventory API | `Published on` timestamp |

**\* Licensing API discovered via browser developer tools - no official documentation available**

## API Endpoints Used

### 1. Power Platform Inventory API (Documented)
- **Endpoint**: `https://api.powerplatform.com/resourcequery/resources/query?api-version=2024-10-01`
- **Method**: POST
- **Documentation**: Public Microsoft API
- **Authentication**: OAuth 2.0 (Device Code Flow)
- **Purpose**: Retrieves agent metadata including name, environment, owner, creation dates
- **Returns**: All agents across all environments (tested: 115 agents)

**Query Format**:
```json
{
  "Options": {
    "Top": 1000,
    "Skip": 0
  },
  "TableName": "PowerPlatformResources",
  "Clauses": [
    {
      "$type": "where",
      "FieldName": "type",
      "Operator": "in~",
      "Values": ["Microsoft.PowerPlatform/copilots"]
    }
  ]
}
```

### 2. Licensing API - Credits Consumption (Undocumented)
- **Endpoint**: `https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/{tenantId}/entitlements/MCSMessages/environments/{environmentId}/resources?fromDate={MM-DD-YYYY}&toDate={MM-DD-YYYY}`
- **Method**: GET
- **Documentation**: ⚠️ **None - Discovered via browser developer tools**
- **Authentication**: OAuth 2.0 (Device Code Flow)
- **Client ID**: `51f81489-12ee-4a9e-aaae-a2591f45987d`
- **Purpose**: Retrieves actual consumption data including billed and non-billed credits
- **Date Requirements**: 
  - Dates are **MANDATORY** (API returns empty without them)
  - Format: `MM-DD-YYYY`
  - Recommended range: **365 days** for complete historical data
  - Testing showed 365-day range returns 13x more data than 30-day range (1495 MB vs 112 MB)

**Important Notes**:
- This API is **version 0.1-alpha** (pre-release/unsupported)
- No official Microsoft documentation exists
- Discovered by inspecting network traffic in PPAC browser developer tools
- May change or be deprecated without notice
- Returns consumption broken down by:
  - Channel (M365 Copilot, Teams, Autonomous)
  - Feature type (Classic answer, Agent flow actions, Generative AI tools)
  - Billable vs Non-billable consumption

## Scripts

### 1. Get-AllAgents-InventoryAPI-v2.ps1
Retrieves all Copilot Studio agents using the Power Platform Inventory API.

**Returns**: 6 fields for all agents
- Agent ID, Name
- Environment ID, Name, Type, Region
- Owner
- Created/Modified/Published dates

**Usage**:
```powershell
.\Get-AllAgents-InventoryAPI-v2.ps1
```

**Output**: `CopilotAgents_InventoryAPI.csv`

### 2. Get-CopilotCredits-v2.ps1
Retrieves credits consumption data using the undocumented Licensing API.

**Parameters**:
- `-TenantId`: Azure AD Tenant ID (default: auto-detect)
- `-LookbackDays`: Number of days to look back (default: 365)

**Returns**: Billed and Non-billed credits per agent
- Credits consumption in MB
- Breakdown by channel and feature

**Usage**:
```powershell
# Default: 365-day lookback (recommended)
.\Get-CopilotCredits-v2.ps1

# Custom: 90-day lookback
.\Get-CopilotCredits-v2.ps1 -LookbackDays 90
```

**Output**: 
- `CopilotCredits_Detailed_TIMESTAMP.csv` - All consumption records
- `CopilotCredits_Summary_TIMESTAMP.csv` - Aggregated by agent

### 3. Merge-InventoryAndCredits.ps1
Combines Inventory and Credits data into a single comprehensive report.

**Usage**:
```powershell
.\Merge-InventoryAndCredits.ps1
```

**Output**: `CopilotAgents_Complete_TIMESTAMP.csv`
- All agents from Inventory (115 total)
- Credits data merged (0 for agents without usage)
- 8 of 12 requested fields

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

**Note**: You'll authenticate twice when running the merge workflow:
- Once for Inventory API
- Once for Licensing API

## Workflow

1. **Run Inventory API script** to get all agents:
   ```powershell
   cd mzcustomscripts
   .\Get-AllAgents-InventoryAPI-v2.ps1
   ```

2. **Run Credits API script** to get consumption data:
   ```powershell
   .\Get-CopilotCredits-v2.ps1
   ```

3. **Merge the datasets**:
   ```powershell
   .\Merge-InventoryAndCredits.ps1
   ```

4. **Review output**: `CopilotAgents_Complete_TIMESTAMP.csv`

## Limitations & Unavailable Fields

### Fields Not Available via API

1. **Agent Description**
   - Not returned by Inventory API
   - Not available in any public or discovered API
   - Would require direct Dataverse query per environment

2. **Solution ID**
   - Not returned by Inventory API
   - Available only via Dataverse query
   - Format: `dataverse://environments/{env}/tables/bot/rows/{agentId}?columns=solutionid`
   - Requires per-environment authentication

3. **Active Users**
   - Not available in any API endpoint
   - Microsoft Analytics API only shows aggregate metrics
   - Individual agent user counts not exposed

### Tested but Non-Working Approaches

The following approaches were tested but did not provide the required data:

1. **Official Licensing API** (`/entitlements/MCSMessages/summary`)
   - Returns license capacity (50,000 messages)
   - Does NOT return actual consumption data

2. **Microsoft.PowerPlatform.SDK**
   - .NET SDK does not expose credits/consumption APIs
   - Compilation issues with current SDK version

3. **PPAC Export API** (`/api/PowerPlatform/Environment/Export`)
   - Returns 405 Method Not Allowed
   - Not accessible via public authentication

4. **Resource Graph API**
   - Only returns resource metadata, not consumption

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

**Last Updated**: January 11, 2026
