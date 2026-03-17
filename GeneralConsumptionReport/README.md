# General Copilot Credits Consumption Report

> **Audience**: Microsoft customers and IT Admins who need visibility into **all** Copilot Credits consumption across their Power Platform tenant — Copilot Studio Agents, Power Automate Flows, Power Apps, and AI Builder activity.

---

## What This Does

This PowerShell script queries the `msdyn_aievents` Dataverse table across **every** environment in your tenant and produces three CSV reports:

| Output File | Contents |
|---|---|
| `GeneralConsumption_Summary_*.csv` | Credit totals grouped by resource type (AI Builder, Copilot Studio Agent, Flow, App) |
| `GeneralConsumption_ByResource_*.csv` | Per-resource drill-down with solution ID, credits, units, channel, and LLM model |
| `GeneralConsumption_AllEvents_*.csv` | Raw event-level data — one row per `msdyn_aievent` record |

The `ByResource` and `AllEvents` files include:
- **`Is Agent`** — `True` when the event belongs to a Copilot Studio Agent
- **`Solution ID`** — the Power Platform Solution that contains the agent (when detectable)

---

## Quick Start (5 minutes)

### Prerequisites

- **PowerShell 7+** (recommended) or Windows PowerShell 5.1
- A Microsoft 365 / Power Platform account with at minimum **Environment Viewer** rights across your environments
- Interactive browser sign-in (PKCE flow — no app registration needed for read-only use)

See [docs/SETUP.md](docs/SETUP.md) for full prerequisite details.

---

### Step 1 — Discover the schema in your tenant

The `msdyn_eventdata` field inside `msdyn_aievents` is an undocumented JSON blob. Its key names can differ between tenants. Run this first to dump samples and confirm the field names:

```powershell
cd GeneralConsumptionReport
.\Get-GeneralConsumptionReport.ps1 -DiscoverSchema
```

This creates a `SchemaDiscovery_TIMESTAMP\` folder containing raw JSON samples from each environment that has events. Open a few JSON files and compare the key names to the `$script:EventDataFields` map at the top of the script.

> **Tip**: In most tenants you will not need to change anything — the default field map was validated on a production M365 tenant in March 2026.

---

### Step 2 — Run the full report

```powershell
.\Get-GeneralConsumptionReport.ps1 -LookbackDays 30
```

Reports are written to the `output\` subfolder.

**Common options:**

```powershell
# Last 90 days
.\Get-GeneralConsumptionReport.ps1 -LookbackDays 90

# Up to 2000 events per environment (default is 1000)
.\Get-GeneralConsumptionReport.ps1 -LookbackDays 30 -MaxEventsPerEnvironment 2000

# Force a fresh sign-in (clear cached tokens)
.\Get-GeneralConsumptionReport.ps1 -ForceReauth

# Run from Azure Automation (uses managed identity / service principal token flow)
.\Get-GeneralConsumptionReport.ps1 -LookbackDays 30 -Mode AzureAutomation
```

---

## Understanding the Output

### Summary CSV

```
Resource Type          Events  Total Credits  Total Units  Environments
Copilot Studio Agent   102     6.80           68           Prod; Dev Env
AI Builder             33      208.70         236          Prod; Pipeline Env
Unknown                291     0.00           459          Prod; Dev Env; ...
```

> **Unknown** rows are events where the `msdyn_eventdata` JSON has no `partnerSource` discriminator. These are typically background platform events (token refreshes, session checks). They consume 0 credits.

### ByResource CSV — key columns

| Column | Description |
|---|---|
| `Resource Type` | Friendly type (Copilot Studio Agent / AI Builder / Power Automate Flow / Power Apps) |
| `Is Agent` | `True` when resource type is Copilot Studio Agent |
| `Resource Name` | Display name of the bot, flow, or app |
| `Bot Schema Name` | Dataverse schema name of the Copilot Studio bot |
| `Resource ID` | Dataverse botid GUID (when matched) |
| `Solution ID` | GUID of the Power Platform Solution containing the agent |
| `Environment` | Environment display name |
| `Channel` | Interaction channel (Api, WebChat, Teams, PowerAutomateFlow, …) |
| `LLM Model` | Language model used (e.g. gpt-41-mini-2025-04-14) |
| `Total Credits` | Sum of Copilot Credits consumed |
| `Total Units` | Sum of message units |

---

## Folder Structure

```
GeneralConsumptionReport/
├── Get-GeneralConsumptionReport.ps1   ← main script
├── README.md                          ← this file
├── docs/
│   ├── SETUP.md                       ← prerequisites and authentication guide
│   └── FIELD_MAP_GUIDE.md             ← how to adapt the field map for your tenant
└── output/                            ← CSV reports are written here (git-ignored)
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `No access to Dataverse in 'X'` for ALL environments | Token audience mismatch | Run `.\Get-GeneralConsumptionReport.ps1 -ForceReauth` to clear the token cache and re-authenticate |
| `No AI events in this window` for all environments | Lookback window too short | Increase `-LookbackDays` |
| All `Solution ID` values are empty | `botSchemaName` field uses a different key in your tenant | Run `-DiscoverSchema` and update `$script:EventDataFields.BotSchemaName` — see [docs/FIELD_MAP_GUIDE.md](docs/FIELD_MAP_GUIDE.md) |
| `Access denied` on 2–3 environments | Those are personal developer environments not accessible to your account | Expected — the script skips them and continues |
| All credits show 0 but units are non-zero | Credits are in the nested `messageConsumption.consumption` key | Verify with `-DiscoverSchema`; the nesting level may differ in your tenant |

---

## Authentication

The script uses **PKCE interactive browser sign-in** — no app registration is required. On first run, a browser window opens for you to sign in. A refresh token is cached at:

```
~\.copilot-report-tokens.json
```

Subsequent runs reuse the cached refresh token silently. Use `-ForceReauth` to clear the cache.

See [docs/SETUP.md](docs/SETUP.md) for service-principal / Azure Automation setup.

---

## Relationship to AgentCustomReport

This script is a companion to `Get-CompleteCopilotReport-v1.3.ps1` in the parent project. That script focuses on **Copilot Studio agent inventory** (agent list, solution mapping, licensing). This script focuses on **consumption data** across all resource types from the `msdyn_aievents` table. The same authentication cache is shared between both scripts.
