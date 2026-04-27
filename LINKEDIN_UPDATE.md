# LinkedIn Post Update - AgentCustomReport v1.2

## Original Post
[View Original Post](https://www.linkedin.com/posts/sayedaly_powerplatform-copilotstudio-apis-activity-7416205468815179776-zwdN)

---

## Suggested Update Post

### Option 1: Short Update (Recommended for LinkedIn)

```
UPDATE: AgentCustomReport now has a Web Application! 🎉

Following the positive response to my PowerShell solution for Copilot Studio reporting, I've built a full web dashboard.

🆕 What's New in v1.2:
• ASP.NET Core web app with Azure AD SSO
• Interactive dashboard with Chart.js visualizations
• KPI cards showing total agents, credits, and activity
• Sortable/filterable table with pagination
• Same undocumented Licensing API - now with refresh tokens!

🔑 Key Technical Learning:
The Licensing API cannot be accessed via standard app registration. The web app uses the same Device Code Flow approach as the PowerShell script, with Microsoft's public client ID.

📺 Watch the demo: [Video Link]
📁 GitHub: https://github.com/sayedpfe/AgentCustomReport

#PowerPlatform #CopilotStudio #ASPNET #WebDevelopment #APIs
```

---

### Option 2: Detailed Technical Update

```
🚀 Major Update: AgentCustomReport v1.2 - Now with Web Dashboard!

Remember my PowerShell tool for Copilot Studio reporting? It's grown into a full web application!

🎯 THE CHALLENGE
Building a web app to display Copilot agent credit usage seemed straightforward... until I discovered the Licensing API won't accept tokens from custom app registrations. It's an undocumented first-party Microsoft API.

💡 THE SOLUTION
The web app uses DUAL authentication:
1️⃣ Power Platform Inventory API → Azure AD SSO (standard)
2️⃣ Licensing API → Device Code Flow with Microsoft's public client ID

Same approach as the PowerShell script, but now with:
• Encrypted refresh tokens (90-day validity)
• Auto-refresh before expiration
• Per-user session storage

📊 NEW FEATURES
• KPI Summary Cards - agents, credits, billed vs non-billed at a glance
• Interactive Charts - top 10 agents, credit breakdown
• Enhanced Table - sort, filter, search, pagination
• Column Visibility - customize your view
• CSV Export - download full reports

🛠️ TECH STACK
• ASP.NET Core 8.0
• Microsoft Identity Web
• Chart.js for visualizations
• Bootstrap 5 + Bootstrap Icons

📺 Demo Video: [Link to AgentCustomReport.mp4]
📁 Full Source Code: https://github.com/sayedpfe/AgentCustomReport

The repo now includes:
• PowerShell script (v1.1) - for automation
• Web app (v1.2) - for teams and dashboards

Which version would you use? Let me know in the comments! 👇

#PowerPlatform #CopilotStudio #ASPNET #APIs #ReverseEngineering #OpenSource #WebDevelopment #DotNet
```

---

## Key Points to Highlight

### 1. Evolution from PowerShell to Web App
- v1.0: PowerShell with Device Code Flow
- v1.1: Added certificate authentication for automation
- v1.2: Full web application with dashboard

### 2. Technical Discovery (Important!)
The Licensing API (`https://licensing.powerplatform.microsoft.com/v0.1-alpha`) is:
- Undocumented (found via browser dev tools)
- First-party Microsoft API
- **Cannot grant permissions to custom app registrations**
- Only works with Microsoft's public client ID: `51f81489-12ee-4a9e-aaae-a2591f45987d`

This is why both the PowerShell script and web app use Device Code Flow with this specific client ID.

### 3. Web App Features
- Azure AD Single Sign-On
- Device Code Flow for Licensing API (one-time per session)
- Encrypted refresh tokens (ASP.NET Core Data Protection)
- KPI cards, charts, sortable tables
- CSV export

### 4. Value Proposition
| For | Use |
|-----|-----|
| Individual admins | PowerShell script |
| Teams / Non-technical users | Web application |
| Automation | PowerShell + Certificate auth |

---

## Video Highlights

Reference points from the demo video (`Video/AgentCustomReport.mp4`):

1. **Login Flow**: Azure AD SSO → automatic redirect
2. **Agents List**: Shows all 115+ agents across environments
3. **Authorize Licensing API**: Device code flow demonstration
4. **Credit Data Loading**: Shows billed/non-billed breakdown
5. **Interactive Features**: Sorting, filtering, pagination demo
6. **Charts**: Top 10 agents, billed vs non-billed doughnut
7. **CSV Export**: Download report functionality

---

## Hashtags

Primary:
- #PowerPlatform
- #CopilotStudio
- #APIs

Technical:
- #ASPNET
- #DotNet
- #WebDevelopment

Engagement:
- #OpenSource
- #ReverseEngineering
- #DevTools

---

## Call to Action Ideas

1. "Which version would you use - PowerShell or Web App?"
2. "Has anyone else struggled with undocumented Microsoft APIs?"
3. "What features would you add to this dashboard?"
4. "Tag someone who manages Copilot Studio agents!"

---

## Links to Include

- **GitHub Repository**: https://github.com/sayedpfe/AgentCustomReport
- **Original Post**: https://www.linkedin.com/posts/sayedaly_powerplatform-copilotstudio-apis-activity-7416205468815179776-zwdN
- **Demo Video**: Upload `Video/AgentCustomReport.mp4` to LinkedIn

---

## Image Suggestions

Consider creating screenshots or thumbnails showing:
1. Dashboard with KPI cards and charts
2. Side-by-side: PowerShell output vs Web dashboard
3. Authentication flow diagram
4. Before/After comparison

---

**Last Updated**: January 25, 2026
