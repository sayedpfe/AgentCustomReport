# Copilot Studio Usage API - Complete Guide

## Overview

This guide explains how to use the **undocumented Power Platform Licensing API** to retrieve Copilot Studio agent usage data (Billed and Non-Billed Copilot Credits) programmatically.

## Discovery

The Licensing API endpoint was discovered by inspecting network traffic in the Power Platform Admin Center when viewing **Licensing → Copilot Studio → Environments → Message consumption by resource**.

## API Endpoint

```
https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/{tenantId}/entitlements/MCSMessages/environments/{environmentId}/resources?fromDate={MM-dd-yyyy}&toDate={MM-dd-yyyy}
```

### Parameters

| Parameter | Description | Format | Example |
|-----------|-------------|--------|---------|
| `tenantId` | Azure AD Tenant ID | GUID | `b22f8675-8375-455b-941a-67bee4cf7747` |
| `environmentId` | Power Platform Environment ID | GUID | `50f3edf1-abe7-e31d-9602-dc56f4f3e404` |
| `fromDate` | Start date of reporting period | MM-dd-yyyy | `11-01-2025` |
| `toDate` | End date of reporting period | MM-dd-yyyy | `11-30-2025` |

### Authentication

**Required Token:** Bearer token for `https://licensing.powerplatform.microsoft.com`

**How to obtain:**
```powershell
# Using Az.Accounts module
$token = (Get-AzAccessToken -ResourceUrl "https://licensing.powerplatform.microsoft.com").Token
```

### Response Format

```json
{
    "value": [
        {
            "resources": [
                {
                    "resourceId": "2d650591-c4c8-429b-9075-3ae63c06edab",
                    "consumed": 0.39,
                    "unit": "MB",
                    "lastRefreshedDate": "0001-01-01T00:00:00",
                    "metadata": {
                        "ProductName": "Copilot Studio",
                        "FeatureName": "Agent flow actions",
                        "ResourceName": "AgentFlowGetQuestions",
                        "ToolInvoked": "",
                        "KnowledgeSources": "",
                        "LLMModel": "",
                        "ChannelId": "M365 Copilot",
                        "NonBillableQuantity": 14.17
                    }
                }
            ]
        }
    ]
}
```

### Response Fields

| Field | Description | Example |
|-------|-------------|---------|
| `resourceId` | Agent/Resource ID (botid) | `2d650591-c4c8-429b-9075-3ae63c06edab` |
| `consumed` | **Billed Copilot Credits** | `0.39` |
| `metadata.NonBillableQuantity` | **Non-Billed Copilot Credits** | `14.17` |
| `metadata.ProductName` | Always "Copilot Studio" | `Copilot Studio` |
| `metadata.FeatureName` | Feature type | `Agent flow actions`, `Classic answer`, `Text and generative AI tools (basic)` |
| `metadata.ResourceName` | Agent name | `AgentFlowGetQuestions` |
| `metadata.ChannelId` | Deployment channel | `M365 Copilot`, `Teams`, `Autonomous` |

## Feature Types

| Feature Name | Description | Credit Cost |
|--------------|-------------|-------------|
| `Agent flow actions` | Power Automate flow executions | 13 credits per 100 actions |
| `Classic answer` | Traditional bot responses | 1 credit per message |
| `Text and generative AI tools (basic)` | AI-generated responses | 1-100 credits per 10 responses |

## Available Scripts

### 1. Get-AgentsWithUsage.ps1

**Purpose:** Combines agent inventory with usage data in a consolidated report (one row per agent).

**Usage:**
```powershell
# Default: Previous month
.\Get-AgentsWithUsage.ps1

# Specific month
.\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025

# Custom output path
.\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025 -OutputPath "C:\Reports\AgentUsage.csv"
```

**Output Columns:**
- Agent Name
- Agent ID
- Environment
- Environment Type
- Environment ID
- Billed Copilot Credits
- Non-Billed Copilot Credits
- Total Credits
- Feature Details (comma-separated)
- Created On
- Modified On
- Published On
- Status
- Report Period

**Use Case:** Executive reporting, high-level usage overview, cost analysis.

### 2. Get-AgentsUsage-DetailedReport.ps1

**Purpose:** Matches the exact format of PPAC "Message consumption by resource" table (one row per agent per feature).

**Usage:**
```powershell
# All environments
.\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025

# Single environment
.\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025 -EnvironmentId "50f3edf1-abe7-e31d-9602-dc56f4f3e404"

# Specify tenant
.\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025 -TenantId "b22f8675-8375-455b-941a-67bee4cf7747"
```

**Output Columns:**
- Name (Agent name)
- Product (Copilot Studio)
- Feature (Feature type)
- BilledCopilotCredits
- NonBilledCopilotCredits
- ChannelId
- ToolInvoked
- KnowledgeSources
- LLMModel
- ResourceId (Agent ID)
- Environment
- EnvironmentId

**Use Case:** Detailed analysis, feature-level breakdown, matching PPAC exports.

## Prerequisites

### PowerShell Modules

```powershell
# Install required modules
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
```

### Permissions

**Required Azure AD Roles:**
- Power Platform Administrator (or)
- Dynamics 365 Administrator (or)
- Global Administrator

**API Permissions:**
- Access is role-based through Azure AD authentication
- No explicit API permissions needed if you have admin center access

## Example: Manual API Call

```powershell
# 1. Authenticate
Connect-AzAccount

# 2. Get token
$token = (Get-AzAccessToken -ResourceUrl "https://licensing.powerplatform.microsoft.com").Token

# 3. Build URL
$tenantId = (Get-AzContext).Tenant.Id
$environmentId = "YOUR-ENVIRONMENT-ID"
$url = "https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/$tenantId/entitlements/MCSMessages/environments/$environmentId/resources?fromDate=11-01-2025&toDate=11-30-2025"

# 4. Call API
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/json"
}

$response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get

# 5. Parse results
foreach ($resource in $response.value[0].resources) {
    [PSCustomObject]@{
        AgentName = $resource.metadata.ResourceName
        Feature = $resource.metadata.FeatureName
        Billed = $resource.consumed
        NonBilled = $resource.metadata.NonBillableQuantity
    }
}
```

## Combining with Inventory API

To get a complete picture, combine both APIs:

1. **Inventory API** → Agent metadata (owner, created date, environment details)
2. **Licensing API** → Usage/consumption data (credits)

Example integration:
```powershell
# Get all agents from Inventory API
$agents = # ... use Inventory API or Dataverse

# For each environment, get usage data
foreach ($env in $environments) {
    $usageData = # ... call Licensing API

    # Match agents with usage by botid/resourceId
    # Combine into final report
}
```

This is exactly what `Get-AgentsWithUsage.ps1` does!

## Power BI Integration

### Option 1: Direct Import
1. Run one of the PowerShell scripts
2. Import the generated CSV into Power BI
3. Create visualizations

### Option 2: Power Query (Scheduled Refresh)

Create a custom Power Query function:

```powerquery
let
    GetUsageData = (TenantId as text, EnvironmentId as text, FromDate as text, ToDate as text) =>
    let
        Url = "https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/" & TenantId & "/entitlements/MCSMessages/environments/" & EnvironmentId & "/resources?fromDate=" & FromDate & "&toDate=" & ToDate,
        Source = Json.Document(Web.Contents(Url)),
        Resources = Source[value]{0}[resources],
        ToTable = Table.FromList(Resources, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        Expanded = Table.ExpandRecordColumn(ToTable, "Column1", {"resourceId", "consumed", "metadata"}),
        ExpandedMeta = Table.ExpandRecordColumn(Expanded, "metadata", {"ProductName", "FeatureName", "ResourceName", "NonBillableQuantity", "ChannelId"})
    in
        ExpandedMeta
in
    GetUsageData
```

**Note:** Web.Contents may require gateway configuration for scheduled refresh.

## Limitations

### API Version: v0.1-alpha

⚠️ **This API is in ALPHA and undocumented:**
- May change without notice
- No official SLA or support
- No official documentation
- Use at your own risk

### Rate Limiting

- Unknown rate limits
- Recommend adding delays between API calls
- Use `-Verbose` flag to monitor for throttling

### Data Availability

- Data typically available within 24-48 hours
- Historical data: Varies by retention policy
- Real-time data: Not available

## Troubleshooting

### Error: 401 Unauthorized

**Solution:**
```powershell
# Clear token cache and re-authenticate
Disconnect-AzAccount
Connect-AzAccount
```

### Error: 403 Forbidden

**Cause:** Insufficient permissions

**Solution:**
- Verify you have Power Platform Administrator role
- Check if you can access the data in Power Platform Admin Center UI
- Contact your Global Administrator

### Error: 404 Not Found

**Causes:**
- Invalid environment ID
- Environment doesn't exist
- Date format incorrect

**Solution:**
- Verify environment ID: `Get-AdminPowerAppEnvironment | Select DisplayName, EnvironmentName`
- Use MM-dd-yyyy format for dates

### Empty Results

**Possible causes:**
- No usage in the specified period
- Agents exist but haven't been used
- Date range doesn't contain data

**Verification:**
- Check same data in Power Platform Admin Center UI
- Try a different date range

## Best Practices

1. **Caching:** Cache tokens to avoid repeated authentication
2. **Error Handling:** Wrap API calls in try-catch blocks
3. **Logging:** Use `-Verbose` for detailed logging
4. **Scheduling:** Run monthly reports via Task Scheduler
5. **Data Validation:** Cross-check totals with PPAC UI
6. **Backup:** Keep historical CSV exports

## Sample Reports

### Monthly Executive Summary
```powershell
# Run consolidated report
.\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025

# Generate executive summary
Import-Csv "AgentUsageReport_*.csv" |
    Group-Object Environment |
    Select-Object @{N='Environment';E={$_.Name}},
                  @{N='Agents';E={$_.Count}},
                  @{N='Total Credits';E={($_.Group | Measure-Object 'Total Credits' -Sum).Sum}} |
    Export-Csv "Executive_Summary.csv" -NoTypeInformation
```

### Feature-Level Analysis
```powershell
# Run detailed report
.\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025

# Analyze by feature
Import-Csv "AgentUsage_Detailed_*.csv" |
    Group-Object Feature |
    Select-Object @{N='Feature';E={$_.Name}},
                  @{N='Usage Count';E={$_.Count}},
                  @{N='Total Billed';E={($_.Group | Measure-Object BilledCopilotCredits -Sum).Sum}} |
    Format-Table -AutoSize
```

## Additional Resources

- [Power Platform Admin Center](https://admin.powerplatform.microsoft.com/)
- [Inventory API Documentation](https://learn.microsoft.com/en-us/power-platform/admin/inventory-api)
- [Copilot Studio Capacity Management](https://learn.microsoft.com/en-us/power-platform/admin/manage-copilot-studio-messages-capacity)
- [CoE Starter Kit](https://github.com/microsoft/coe-starter-kit) - Alternative comprehensive monitoring solution

## Support

Since this API is undocumented:
- **Community:** Power Platform Community Forums
- **Issues:** Create issues in your project repository
- **Microsoft Support:** May not support alpha/undocumented APIs

## Feedback to Microsoft

If you'd like this API to be officially supported:
1. Submit feedback via Power Platform Admin Center
2. Vote on existing Ideas in Power Platform Community
3. Contact your Microsoft Account Team
4. Request through premier support channels

---

**Last Updated:** 2025-01-09
**API Version:** v0.1-alpha
**Status:** Undocumented / Unsupported
