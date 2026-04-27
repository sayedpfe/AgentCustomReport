# Azure Automation Setup Guide

Complete guide to setting up the Copilot Studio Agent Report in Azure Automation with automated scheduling.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Azure Automation Account                                │
│                                                          │
│  ┌────────────────────────────────────────────┐        │
│  │ Runbook: Get-CompleteCopilotReport         │        │
│  │ - Runs on schedule (daily/weekly)          │        │
│  │ - Uses stored refresh token                │        │
│  │ - No user interaction needed               │        │
│  └────────────────────────────────────────────┘        │
│                                                          │
│  ┌────────────────────────────────────────────┐        │
│  │ Variables (Encrypted)                       │        │
│  │ - CopilotReportRefreshToken_management     │        │
│  │ - CopilotReportRefreshToken_licensing      │        │
│  │ - TenantId                                  │        │
│  └────────────────────────────────────────────┘        │
│                                                          │
│  ┌────────────────────────────────────────────┐        │
│  │ Schedule                                    │        │
│  │ - Daily at 6 AM                             │        │
│  │ - Weekly on Monday                          │        │
│  │ - Monthly on 1st                            │        │
│  └────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ Azure Storage/Email  │
              │ - Store CSV reports  │
              │ - Email to team      │
              └──────────────────────┘
```

---

## Part 1: Initial Setup (Local)

### Step 1: Run Script Locally to Get Refresh Token

First, run the script locally to authenticate and get refresh tokens:

```powershell
cd scripts
.\Get-CompleteCopilotReport-v1.2.ps1
```

This will:
1. Open your browser for Microsoft sign-in
2. Ask you to consent to permissions
3. Acquire access token + refresh token
4. Save refresh token to: `%USERPROFILE%\.copilot-report-tokens.json`

### Step 2: Extract Refresh Tokens

```powershell
# Read the cached tokens
$cache = Get-Content "$env:USERPROFILE\.copilot-report-tokens.json" | ConvertFrom-Json

# Display refresh tokens (keep these secure!)
Write-Host "Azure Resource Graph Token:"
Write-Host $cache.management_azure_com.RefreshToken
Write-Host ""
Write-Host "Licensing API Token:"
Write-Host $cache.licensing_powerplatform_microsoft_com.RefreshToken
```

**IMPORTANT**: These tokens are sensitive. Handle them like passwords.

---

## Part 2: Azure Automation Account Setup

### Step 1: Create Automation Account

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for "Automation Accounts"
3. Click "+ Create"
4. Fill in:
   - **Subscription**: Your subscription
   - **Resource Group**: Create new or select existing
   - **Name**: `CopilotStudioReporting`
   - **Region**: Your preferred region
5. Click "Review + Create" → "Create"

### Step 2: Import PowerShell Script as Runbook

1. Go to your Automation Account
2. Click "Runbooks" → "+ Create a runbook"
3. Fill in:
   - **Name**: `Get-CopilotStudioReport`
   - **Runbook type**: PowerShell
   - **Runtime version**: 7.2
   - **Description**: "Automated Copilot Studio agent reporting"
4. Click "Create"
5. Paste the complete script content
6. Click "Save" → "Publish"

### Step 3: Create Encrypted Variables for Refresh Tokens

1. Go to "Variables" in your Automation Account
2. Click "+ Add a variable"

**Variable 1: Azure Resource Graph Token**
- **Name**: `CopilotReportRefreshToken_management_azure_com`
- **Type**: String
- **Value**: [Paste refresh token from Step 2 above]
- **Encrypted**: ✅ YES
- Click "Create"

**Variable 2: Licensing API Token**
- **Name**: `CopilotReportRefreshToken_licensing_powerplatform_microsoft_com`
- **Type**: String
- **Value**: [Paste refresh token from Step 2 above]
- **Encrypted**: ✅ YES
- Click "Create"

**Variable 3: Tenant ID (optional, if not using default)**
- **Name**: `TenantId`
- **Type**: String
- **Value**: `b22f8675-8375-455b-941a-67bee4cf7747`
- **Encrypted**: No
- Click "Create"

### Step 4: Test the Runbook

1. Go to your runbook
2. Click "Start"
3. Fill in parameters:
   - **Mode**: `AzureAutomation`
   - **LookbackDays**: `365`
4. Click "OK"
5. Monitor the job output
6. Verify it completes successfully

---

## Part 3: Schedule Automation

### Option A: Daily Reports

1. Go to your runbook
2. Click "Schedules" → "+ Add a schedule"
3. Click "Link a schedule to your runbook"
4. Click "+ Add a schedule"
5. Fill in:
   - **Name**: `Daily-6AM`
   - **Description**: "Generate daily report at 6 AM"
   - **Starts**: Tomorrow
   - **Time zone**: Your timezone
   - **Recurrence**: Recurring
   - **Recur every**: 1 Day
6. Click "Create"
7. Set parameters:
   - **Mode**: `AzureAutomation`
   - **LookbackDays**: `365`
8. Click "OK"

### Option B: Weekly Reports

1. Same steps as above, but:
   - **Name**: `Weekly-Monday-6AM`
   - **Recur every**: 1 Week
   - **On these days**: Monday
   - **LookbackDays**: `7` (for weekly delta)

### Option C: Monthly Reports

1. Same steps as above, but:
   - **Name**: `Monthly-First-Day`
   - **Recur every**: 1 Month
   - **On day**: 1
   - **LookbackDays**: `30` (for monthly delta)

---

## Part 4: Output Handling

### Option A: Store in Azure Storage

Add this to the end of your runbook:

```powershell
# Upload to Azure Storage
$storageAccountName = "your-storage-account"
$containerName = "copilot-reports"
$storageKey = Get-AutomationVariable -Name "StorageAccountKey"

$ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey
Set-AzStorageBlobContent -File $outputPath -Container $containerName -Context $ctx -Force
```

### Option B: Send via Email (Logic Apps)

1. Create Logic App triggered by Azure Automation job completion
2. Read CSV from Automation job output
3. Send email with attachment via Office 365 connector

### Option C: Store in SharePoint

1. Create Power Automate flow
2. Trigger: When a file is created in Azure Storage
3. Action: Upload to SharePoint document library
4. Action: Send email notification

---

## Part 5: Maintenance

### Refresh Token Rotation (Every 90 Days)

Refresh tokens expire after 90 days of non-use. To prevent this:

**Option 1: Automatic Renewal (Recommended)**
The script automatically gets a new refresh token when calling the API. Update your Automation Variables with the new token from script output.

**Option 2: Manual Renewal**
Every 90 days (set a calendar reminder):
1. Run the script locally: `.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth`
2. Extract new refresh tokens
3. Update Azure Automation Variables

### Monitoring

1. Set up alerts for runbook failures:
   - Go to Automation Account → Alerts
   - Create alert rule for "Job failed"
2. Check job history regularly:
   - Go to Runbook → Jobs
   - Review recent executions

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Refresh token not found" | Variable not set | Check Automation Variables are created correctly |
| "Refresh token expired" | Token > 90 days old | Re-authenticate and update variables |
| "403 Forbidden" | Permissions issue | This is expected with app-only auth. Use refresh token approach |
| Runbook timeout | Report too large | Increase timeout or filter data |

---

## Part 6: Cost Estimation

### Azure Automation Pricing (Pay-as-you-go)

| Component | Cost | Monthly (Daily runs) |
|-----------|------|----------------------|
| Job runtime | $0.002/minute | ~$1.80 (30 mins/day) |
| Storage | First 500 MB free | $0 |
| **Total** | | **~$2-5/month** |

### Comparison

| Solution | Cost | Maintenance | Scalability |
|----------|------|-------------|-------------|
| Azure Automation | $2-5/month | Low | High |
| Azure Function | $5-10/month | Medium | Very High |
| VM (always-on) | $30-100/month | High | Medium |
| Local scheduled task | $0 | High | Low |

---

## Part 7: Best Practices

### Security

- ✅ Always encrypt refresh tokens in Automation Variables
- ✅ Use Azure Key Vault for additional token encryption
- ✅ Enable audit logging on Automation Account
- ✅ Restrict runbook edit permissions to admins only
- ✅ Review access logs regularly

### Reliability

- ✅ Set up failure alerts
- ✅ Test runbook after any changes
- ✅ Keep backups of working runbook versions
- ✅ Document any customizations
- ✅ Have a rollback plan

### Performance

- ✅ Use appropriate LookbackDays for schedule (7 for weekly, 30 for monthly)
- ✅ Filter data if report gets too large
- ✅ Consider parallel processing for multiple environments
- ✅ Monitor execution time and optimize if needed

---

## Part 8: Advanced Scenarios

### Multi-Tenant Reporting

If you manage multiple tenants:

1. Create separate Automation Variables for each tenant:
   - `TenantA_RefreshToken_management`
   - `TenantA_RefreshToken_licensing`
   - `TenantB_RefreshToken_management`
   - `TenantB_RefreshToken_licensing`

2. Create separate schedules for each tenant

3. Modify script to accept tenant parameter

### Custom Email Reports

Add to runbook:

```powershell
# Generate HTML summary
$html = @"
<h1>Copilot Studio Report</h1>
<p>Total Agents: $($agents.Count)</p>
<p>Total Credits: $($totalCredits) MB</p>
<p>Report generated: $(Get-Date)</p>
"@

# Send email via SendGrid or SMTP
Send-MailMessage -To "team@company.com" -Subject "Copilot Studio Report" -Body $html -BodyAsHtml -Attachments $csvPath
```

### Integration with Power BI

1. Store reports in Azure Storage or SharePoint
2. Create Power BI dataset connected to storage
3. Set up automatic refresh
4. Build dashboard for trend analysis

---

## Support

For issues:
1. Check runbook job output for errors
2. Review [TESTING_GUIDE.md](../tests/TESTING_GUIDE.md)
3. Verify refresh tokens are not expired
4. Check Azure Automation service health

---

**Last Updated**: January 23, 2026  
**Version**: 1.2
