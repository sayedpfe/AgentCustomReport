# Quick Start Guide - Get Agent Usage Data

## 🎯 Goal
Get Copilot Studio agent usage data (Billed and Non-Billed Copilot Credits) exactly like you see in Power Platform Admin Center.

## ⚡ Quick Commands

### Option 1: Consolidated Report (One row per agent)
```powershell
cd "D:\OneDrive\OneDrive - Microsoft\Documents\Learning Projects\AgentCustomReport"
.\mzcustomscripts\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025
```

**Output:** `AgentUsageReport_YYYYMMDD.csv`
- One row per agent
- Total Billed Credits per agent
- Total Non-Billed Credits per agent
- Feature details in one column

**Best for:** Executive summaries, high-level cost analysis

---

### Option 2: Detailed Report (One row per agent per feature)
```powershell
cd "D:\OneDrive\OneDrive - Microsoft\Documents\Learning Projects\AgentCustomReport"
.\mzcustomscripts\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025
```

**Output:** `AgentUsage_Detailed_YYYYMMDD.csv`
- Multiple rows per agent (one per feature type)
- Matches PPAC table exactly
- Shows feature breakdown: Agent flow actions, Classic answer, AI tools
- Channel-level details (Teams, M365 Copilot, etc.)

**Best for:** Detailed analysis, matching PPAC exports, feature-level insights

---

## 📋 Prerequisites

### 1. Install PowerShell Modules (One-time)
```powershell
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser -Force
```

### 2. Required Permissions
You need one of these Azure AD roles:
- Power Platform Administrator
- Dynamics 365 Administrator
- Global Administrator

---

## 🔍 What You'll See

### During Execution:
```
==================================================================
  COPILOT STUDIO AGENTS - USAGE REPORT GENERATOR
==================================================================

Report Period: November 2025
Date Range: 11/01/2025 - 11/30/2025

[1/5] Authentication
✓ Azure: Authenticated as user@contoso.com
✓ Power Platform: Authenticated

[2/5] Obtaining access tokens
✓ Tokens acquired successfully

[3/5] Retrieving environments
✓ Found 12 environments

[4/5] Scanning environments for agents and usage
    This may take several minutes...

  [1/12] Contoso Production
      ✓ 5 agent(s), 3 with usage data
  [2/12] Contoso Development
      - No agents
  ...

[5/5] Generating report

==================================================================
✓ REPORT GENERATED SUCCESSFULLY
==================================================================

  📊 Statistics:
     Total Agents:              23
     Agents with Usage:         15
     Environments Scanned:      12
     Environments with Agents:  4

  💳 Credit Usage (November 2025):
     Total Billed Credits:      15.67
     Total Non-Billed Credits:  103.25
     Grand Total:               118.92

  📁 Output File: AgentUsageReport_20250109.csv
```

---

## 📊 Understanding the Output

### Consolidated Report Columns:

| Column | Description | Example |
|--------|-------------|---------|
| Agent Name | Display name of the agent | `Offboarding Agent` |
| Agent ID | Unique identifier (botid) | `2d650591-c4c8-429b-9075-3ae63c06edab` |
| Environment | Environment name | `Contoso Production` |
| Billed Copilot Credits | **Paid credits consumed** | `11.0` |
| Non-Billed Copilot Credits | **Free credits consumed** | `72.0` |
| Total Credits | Sum of billed + non-billed | `83.0` |
| Feature Details | Feature breakdown | `Agent flow actions [B: 0.39, NB: 14.17]; Classic answer [B: 11, NB: 0]` |

### Detailed Report Columns:

| Column | Description | Example |
|--------|-------------|---------|
| Name | Agent name | `AgentFlowGetQuestions` |
| Product | Always "Copilot Studio" | `Copilot Studio` |
| Feature | Feature type | `Agent flow actions` |
| BilledCopilotCredits | **Billed credits for this feature** | `0.39` |
| NonBilledCopilotCredits | **Non-billed credits for this feature** | `14.17` |
| ChannelId | Deployment channel | `M365 Copilot`, `Teams`, `Autonomous` |
| Environment | Environment name | `Contoso Production` |

---

## 🎓 Feature Types Explained

| Feature | Description | Credit Cost |
|---------|-------------|-------------|
| **Agent flow actions** | Power Automate flows triggered by agents | 13 credits per 100 actions |
| **Classic answer** | Traditional bot responses (no AI) | 1 credit per message |
| **Text and generative AI tools (basic)** | AI-generated responses with simple tools | 1-100 credits per 10 responses |

---

## 💡 Common Use Cases

### Use Case 1: Monthly Cost Report for Management
```powershell
# Get consolidated report
.\mzcustomscripts\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025

# Open the CSV in Excel
# Create pivot table by Environment
# Show sum of Billed Copilot Credits
```

### Use Case 2: Identify High-Usage Agents
```powershell
# Get consolidated report
.\mzcustomscripts\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025

# Import and sort by Total Credits
Import-Csv "AgentUsageReport_*.csv" |
    Sort-Object {[double]$_.'Total Credits'} -Descending |
    Select-Object -First 10 'Agent Name', 'Total Credits', 'Environment' |
    Format-Table -AutoSize
```

### Use Case 3: Feature-Level Analysis
```powershell
# Get detailed report
.\mzcustomscripts\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025

# Analyze by feature type
Import-Csv "AgentUsage_Detailed_*.csv" |
    Group-Object Feature |
    Select-Object Name, Count,
        @{N='Total Billed';E={($_.Group | Measure-Object BilledCopilotCredits -Sum).Sum}} |
    Format-Table -AutoSize
```

### Use Case 4: Single Environment Report
```powershell
# Get your environment ID first
Get-AdminPowerAppEnvironment | Select-Object DisplayName, EnvironmentName

# Query single environment
.\mzcustomscripts\Get-AgentsUsage-DetailedReport.ps1 -Month 11 -Year 2025 -EnvironmentId "50f3edf1-abe7-e31d-9602-dc56f4f3e404"
```

---

## 🐛 Troubleshooting

### Error: "Connect-AzAccount: Access token is empty"
**Solution:**
```powershell
Disconnect-AzAccount
Connect-AzAccount
```

### Error: "Module Az.Accounts not found"
**Solution:**
```powershell
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
```

### Empty Results / Zero Agents
**Possible Causes:**
1. No agents have been used in the specified month
2. Date format issue - ensure MM-dd-yyyy format
3. Permission issues - verify you have Power Platform Administrator role

**Verification:**
- Check the same data in Power Platform Admin Center UI
- Try the previous month: `-Month 10 -Year 2025`
- Use `-Verbose` flag to see detailed logs

### Script Hangs on Authentication
**Solution:**
- Close any browser windows with Azure/Power Platform sessions
- Run in a fresh PowerShell window
- Clear cached credentials: `Clear-AzContext -Force`

---

## 📈 Next Steps

1. **Run for multiple months** to see trends:
   ```powershell
   # Loop through last 6 months
   for ($month = 6; $month -le 11; $month++) {
       .\mzcustomscripts\Get-AgentsWithUsage.ps1 -Month $month -Year 2025 `
           -OutputPath "Reports\Usage_2025_$month.csv"
   }
   ```

2. **Import into Power BI** for visualization:
   - See [powerbi/README.md](powerbi/README.md)

3. **Schedule monthly reports** via Task Scheduler:
   - Run on 1st of each month
   - Email results to stakeholders

4. **Combine with Inventory data**:
   ```powershell
   # Get inventory
   .\mzcustomscripts\Get-AllCopilotAgents-InventoryAPI.ps1

   # Get usage
   .\mzcustomscripts\Get-AgentsWithUsage.ps1 -Month 11 -Year 2025

   # Merge in Excel using Agent ID
   ```

---

## 📚 Additional Documentation

- **Complete API Guide:** [USAGE-API-GUIDE.md](USAGE-API-GUIDE.md)
- **Project Overview:** [README.md](README.md)
- **PowerShell Scripts:** [mzcustomscripts/README.md](mzcustomscripts/README.md)

---

## ⚠️ Important Notes

1. **API Status:** This uses an **undocumented alpha API** (v0.1-alpha)
   - May change without notice
   - No official Microsoft support
   - Use at your own risk

2. **Data Latency:** Usage data typically available within 24-48 hours

3. **Rate Limits:** Unknown - recommend delays between bulk operations

4. **Billing Cycles:** Credits are measured by calendar month

---

**Last Updated:** 2025-01-09
