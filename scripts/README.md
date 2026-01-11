# Copilot Studio Agent Scripts Collection

This folder contains PowerShell scripts for retrieving Copilot Studio agent information across Power Platform environments.

## 🏆 Recommended Solution: Power Platform Inventory API

The **Power Platform Inventory API** is the definitive solution for retrieving all Copilot Studio agents programmatically.

### Why Inventory API is Best:
- ✅ **Single authentication** - No per-environment logins
- ✅ **Complete coverage** - Gets all 115 agents across all 13 environments
- ✅ **Environment metadata** - Includes names, types, regions automatically
- ✅ **Matches Admin Center** - Same data source, same accuracy
- ✅ **Official Microsoft API** - Documented and supported
- ✅ **No setup required** - No Application User configuration needed

---

## 📋 Available Scripts

### 1. Get-AllAgents-InventoryAPI-v2.ps1 ⭐ RECOMMENDED
**Status:** ✅ Production-ready  
**Authentication:** Interactive device code flow  
**Coverage:** ALL agents across ALL environments  

**Features:**
- Queries Power Platform Inventory API
- Gets all Copilot Studio agents in single call
- Joins with environment data automatically
- Returns 9 of 12 mandatory customer fields

**Available Fields:**
- Agent ID, Name, Type
- Environment ID, Name, Type, Region
- Created At, Modified At
- Owner ID, Created By

**Usage:**
```powershell
.\Get-AllAgents-InventoryAPI-v2.ps1
```

**Output:** `CopilotAgents_InventoryAPI.csv` with complete agent inventory

**API Endpoint:**  
`POST https://api.powerplatform.com/resourcequery/resources/query?api-version=2024-10-01`

---

### 2. Get-AllCopilotAgents-InventoryAPI.ps1
**Status:** ✅ Alternative version (basic query without join)  
**Authentication:** Interactive device code flow  
**Coverage:** ALL 115 agents  

**Usage:**
```powershell
.\Get-AllCopilotAgents-InventoryAPI.ps1
```

---

### 3. Create-FinalReport.ps1
**Status:** ✅ Report formatter  
**Input:** Admin Center CSV export or Inventory API output  
**Output:** Formatted report with 12 mandatory fields  

**Features:**
- Reads CSV export (Admin Center or Inventory API)
- Maps to customer-required 12 fields
- Adds field status indicators
- Creates standardized report format

**Usage:**
```powershell
.\Create-FinalReport.ps1 -InputCsv "..\PPAC_Copilot Studio Agents Inventory.csv"
```

---

## 📊 Field Mapping

The Inventory API provides **9 of 12** mandatory customer fields:

| Customer Field | Inventory API Field | Status |
|---|---|---|
| Agent Identifier | `name` | ✅ Available |
| Environment ID | `properties.environmentId` | ✅ Available |
| Agent Name | `properties.displayName` | ✅ Available |
| Agent Description | - | ❌ Not in API |
| Created At | `properties.createdAt` | ✅ Available |
| Updated At | `properties.modifiedAt` | ✅ Available |
| Solution ID | - | ⚠️ Requires Dataverse |
| Agent Owner | `properties.ownerId` | ✅ Available |
| Active Users | - | ⚠️ Requires Dataverse |
| Billed Credits | - | ❌ Not exposed |
| Non-Billed Credits | - | ❌ Not exposed |
| Is Published | - | ⚠️ Requires Dataverse |

---

## 🚀 Quick Start

**Get all agents in 3 steps:**

```powershell
# 1. Navigate to scripts folder
cd "d:\OneDrive\OneDrive - Microsoft\Documents\Learning Projects\AgentCustomReport\scripts"

# 2. Run the Inventory API script
.\Get-AllAgents-InventoryAPI-v2.ps1

# 3. Output file created
# Result: ..\CopilotAgents_InventoryAPI.csv
```

**Expected Results:**
- 115 agents total
- 80 from Contoso (default)
- 16 from Prod
- 11 from Dev Env
- 8 from other environments

---

## 📖 API Documentation

**Power Platform Inventory API:**  
https://learn.microsoft.com/en-us/power-platform/admin/inventory-api

**Resource Type:**  
`microsoft.copilotstudio/agents`

**Query Structure:**
```json
{
  "Options": { "Top": 1000, "Skip": 0 },
  "TableName": "PowerPlatformResources",
  "Clauses": [
    {
      "$type": "where",
      "FieldName": "type",
      "Operator": "in~",
      "Values": ["'microsoft.copilotstudio/agents'"]
    }
  ]
}
```

---

## 🔧 Troubleshooting

**Issue:** Authentication fails  
**Solution:** Ensure you have Global Admin or Power Platform Admin role

**Issue:** Returns fewer than 115 agents  
**Solution:** Check pagination - increase `Top` value or implement skipToken handling

**Issue:** Environment names missing  
**Solution:** Use `Get-AllAgents-InventoryAPI-v2.ps1` which includes environment join

---

## 📝 Version History

**v2 (January 2026) - Inventory API**
- ✅ Uses official Power Platform Inventory API
- ✅ Single authentication for all environments
- ✅ Complete 115 agent coverage
- ✅ Environment metadata included

**v1 (September 2025) - Multiple approaches**
- ⚠️ Dataverse API (per-environment auth required)
- ⚠️ PAC CLI (undercounts agents)
- ✅ Admin Center CSV export (manual)

---

## 📄 License

Scripts provided as-is for Microsoft internal use. Requires appropriate Power Platform permissions.
