# Quick Reference Card - Copilot Studio Agent Report

## 📋 Quick Commands

```powershell
# V1.2 - RECOMMENDED (Authorization Code + Refresh Token)
.\Get-CompleteCopilotReport-v1.2.ps1                # Standard run
.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth   # Force re-authentication
.\Get-CompleteCopilotReport-v1.2.ps1 -LookbackDays 7  # Weekly report
.\Get-CompleteCopilotReport-v1.2.ps1 -IncludeDataverse  # With Solution ID
.\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation  # Azure Automation

# V1.0 - FALLBACK (Device Code)
.\Get-CompleteCopilotReport.ps1                     # Device code flow
.\Get-CompleteCopilotReport.ps1 -LookbackDays 30   # With custom period
.\Get-CompleteCopilotReport.ps1 -IncludeDataverse  # With Dataverse
```

---

## 🎯 When to Use Which Version

| Scenario | Use This | Command |
|----------|----------|---------|
| 🤖 Scheduled automation | **v1.2** | `.\Get-CompleteCopilotReport-v1.2.ps1` |
| 📊 Daily/weekly reports | **v1.2** | `.\Get-CompleteCopilotReport-v1.2.ps1 -LookbackDays 7` |
| ☁️ Azure Automation | **v1.2** | `.\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation` |
| 📝 One-time report | **v1.0** | `.\Get-CompleteCopilotReport.ps1` |
| 🔒 High security (explicit consent) | **v1.0** | `.\Get-CompleteCopilotReport.ps1` |
| 🖥️ SSH/remote session | **v1.0** | `.\Get-CompleteCopilotReport.ps1` |

---

## 🔑 Key Differences

| Feature | v1.0 (Device Code) | v1.2 (Refresh Token) |
|---------|-------------------|----------------------|
| **User Interaction** | Every run | First run only |
| **Automation** | ❌ No | ✅ Yes |
| **Azure Automation** | ❌ No | ✅ Yes |
| **Setup Time** | 2 min | 5 min |
| **Best For** | Ad-hoc reports | Scheduled reports |

---

## 📂 Output Files

| File | Location | Contains |
|------|----------|----------|
| **Report CSV** | `scripts/CopilotAgents_CompleteReport_<timestamp>.csv` | All agent data + credits |
| **Token Cache** | `%USERPROFILE%\.copilot-report-tokens.json` | Refresh tokens (v1.2 only) |

---

## 🔧 Common Scenarios

### Scenario 1: First Time Setup (v1.2)

```powershell
cd scripts
.\Get-CompleteCopilotReport-v1.2.ps1
# Browser opens → Sign in → Done!
# Subsequent runs: NO interaction needed
```

### Scenario 2: Weekly Automation

```powershell
# Run locally once to get tokens
.\Get-CompleteCopilotReport-v1.2.ps1

# Extract tokens
$cache = Get-Content "$env:USERPROFILE\.copilot-report-tokens.json" | ConvertFrom-Json
$cache.management_azure_com.RefreshToken
$cache.licensing_powerplatform_microsoft_com.RefreshToken

# Store in Azure Automation Variables (via Portal)
# Schedule: Weekly on Monday at 6 AM
```

### Scenario 3: Monthly Delta Report

```powershell
# Azure Automation runbook schedule
.\Get-CompleteCopilotReport-v1.2.ps1 -Mode AzureAutomation -LookbackDays 30
# Runs monthly, shows last 30 days of credit consumption
```

### Scenario 4: Emergency Fallback

```powershell
# If v1.2 has issues, use v1.0
.\Get-CompleteCopilotReport.ps1
# Manual device code each time, but guaranteed to work
```

---

## 🚨 Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| "Refresh token not found" | `.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth` |
| "Browser doesn't open" | Check port 8400 availability OR use v1.0 |
| "403 Forbidden" | Verify user has Azure subscription access |
| "Token expired" | `.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth` |
| Script hangs | Check firewall, try v1.0 fallback |

---

## 📊 Report Fields (All Versions)

| Field | Source | Always Available |
|-------|--------|------------------|
| Agent ID | Azure Resource Graph | ✅ |
| Agent Name | Azure Resource Graph | ✅ |
| Environment ID | Azure Resource Graph | ✅ |
| Environment Region | Azure Resource Graph | ✅ |
| Billed Credits (MB) | Licensing API | ✅ |
| Non-Billed Credits (MB) | Licensing API | ✅ |
| Created On | Azure Resource Graph | ✅ |
| Published On | Azure Resource Graph | ✅ |
| Owner | Azure Resource Graph | ✅ |
| Solution ID | Dataverse | ⚠️ Optional (-IncludeDataverse) |
| Agent Description | Dataverse | ⚠️ Optional (-IncludeDataverse) |

---

## 🔒 Security Checklist

- [ ] Don't commit `.copilot-report-tokens.json` to Git
- [ ] Use encrypted Azure Automation Variables
- [ ] Review access logs regularly
- [ ] Rotate tokens every 90 days (automatic with v1.2)
- [ ] Use dedicated service account for automation
- [ ] Limit permissions to minimum required

---

## 📞 Quick Links

| Resource | Link |
|----------|------|
| **Full Documentation** | [README.md](README.md) |
| **Authentication Comparison** | [AUTHENTICATION_OPTIONS.md](AUTHENTICATION_OPTIONS.md) |
| **Azure Automation Setup** | [AZURE_AUTOMATION_SETUP.md](AZURE_AUTOMATION_SETUP.md) |
| **Implementation Details** | [V1.2_IMPLEMENTATION_SUMMARY.md](V1.2_IMPLEMENTATION_SUMMARY.md) |
| **Troubleshooting** | [tests/TESTING_GUIDE.md](tests/TESTING_GUIDE.md) |

---

## ⏱️ Performance Reference

| Task | Time (Approx) |
|------|---------------|
| **First authentication (v1.2)** | 30-60 seconds |
| **Cached authentication (v1.2)** | 2-5 seconds |
| **Device code auth (v1.0)** | 30-60 seconds |
| **Retrieve 115 agents** | 10-30 seconds |
| **Credits for 23 environments** | 1-3 minutes |
| **Dataverse queries (optional)** | 5-10 minutes |
| **Total execution** | 2-5 minutes (without Dataverse) |

---

## 💰 Azure Automation Cost Estimate

| Component | Cost | Monthly (Daily Run) |
|-----------|------|---------------------|
| Job runtime | $0.002/min | ~$1.80 (30 min/day) |
| Storage | Free (first 500 MB) | $0 |
| **Total** | | **~$2-5/month** |

---

## 📅 Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| **Check token validity** | Monthly | Review Azure Automation job logs |
| **Rotate tokens (if needed)** | 90 days | `.\Get-CompleteCopilotReport-v1.2.ps1 -ForceReauth` |
| **Review report accuracy** | Weekly | Spot-check CSV output |
| **Update script** | As needed | Pull latest from repository |
| **Audit access logs** | Monthly | Check Azure AD sign-in logs |

---

## 🎓 Learning Path

1. **Beginner**: Run v1.0 (Device Code) locally
2. **Intermediate**: Run v1.2 locally with refresh tokens
3. **Advanced**: Deploy to Azure Automation
4. **Expert**: Multi-tenant, Power BI integration, custom alerts

---

## 🆘 Support Resources

| Issue Type | Resource |
|------------|----------|
| Authentication errors | [AUTHENTICATION_OPTIONS.md](AUTHENTICATION_OPTIONS.md) |
| API errors (403, 401) | [tests/TESTING_GUIDE.md](tests/TESTING_GUIDE.md) |
| Azure Automation setup | [AZURE_AUTOMATION_SETUP.md](AZURE_AUTOMATION_SETUP.md) |
| Script errors | [V1.2_IMPLEMENTATION_SUMMARY.md](V1.2_IMPLEMENTATION_SUMMARY.md) |
| General questions | [README.md](README.md) |

---

**Print this card and keep it handy!**  
**Version**: 1.2.0  
**Last Updated**: January 23, 2026
