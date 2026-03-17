# Field Map Guide

The `msdyn_aievents` Dataverse table stores a JSON payload in the `msdyn_eventdata` column. This schema is **not publicly documented by Microsoft** and the JSON key names can vary between tenants and over time as the platform evolves.

This guide explains how to discover and adapt the field map for your tenant.

---

## Step 1 — Run Schema Discovery

```powershell
.\Get-GeneralConsumptionReport.ps1 -DiscoverSchema
```

This creates a folder named `SchemaDiscovery_TIMESTAMP\` in the working directory. Inside, each environment that has events gets a subfolder with up to 5 sample JSON files named `event_<id>.json`.

Example output structure:

```
SchemaDiscovery_20260317-075345/
├── Prod/
│   ├── event_abc123.json
│   ├── event_def456.json
│   └── event_...
├── Dev Env/
│   └── event_...
└── Pipeline Env/
    └── event_...
```

---

## Step 2 — Inspect the JSON

Open a few of the JSON files. A typical Copilot Studio Agent event in this tenant looks like:

```json
{
  "messageConsumption": {
    "featureName": "Text and generative AI tools (basic)",
    "units": 3,
    "consumption": 0.3
  },
  "resourceName": "Offboarding Agent",
  "botSchemaName": "crd17_hrDynamicOffboardingQuestions",
  "consumptionSource": "Api",
  "partnerSource": "MicrosoftCopilotStudio",
  "llmModelName": "gpt-41-mini-2025-04-14"
}
```

An AI Builder event may look different — possibly with no `messageConsumption` wrapper, or with additional fields like `modelId` or `actionType`.

---

## Step 3 — Compare With the Script's Field Map

Open `Get-GeneralConsumptionReport.ps1` and find the `$script:EventDataFields` section near the top (around line 95):

```powershell
$script:EventDataFields = @{
    ResourceName  = @("resourceName", "ResourceName", "AppName", "FlowName", "Name")
    SourceType    = @("partnerSource", "PartnerSource", "Source", "AppType", "Type")
    Channel       = @("consumptionSource", "ConsumptionSource", "ChannelId", "Channel")
    LLMModel      = @("llmModelName", "LlmModelName", "ModelName")
    BotSchemaName = @("botSchemaName", "BotSchemaName")
}
```

Each entry is an **ordered candidate-key list**. The script tries each key left-to-right until it finds a non-null value. So if your tenant uses `AppName` instead of `resourceName`, add `"AppName"` earlier in the `ResourceName` list.

---

## Step 4 — Update the Field Map If Needed

### Example: Tenant uses `agentName` instead of `resourceName`

```powershell
ResourceName  = @("agentName", "resourceName", "ResourceName", "AppName", "FlowName", "Name")
```

### Example: Tenant uses `source` instead of `partnerSource`

```powershell
SourceType    = @("source", "partnerSource", "PartnerSource", "Source", "AppType", "Type")
```

---

## Understanding the Credit Structure

### Nested `messageConsumption` (most Copilot Studio events)

```json
{
  "messageConsumption": {
    "consumption": 0.3,     ← Copilot Credits (decimal)
    "units": 3,             ← message units (integer)
    "featureName": "..."    ← feature description
  }
}
```

The script handles this nesting specially in `ConvertTo-ConsumptionRecord`:

```powershell
if ($parsed -and $parsed.messageConsumption) {
    $credits     = [double]$parsed.messageConsumption.consumption
    $units       = [double]$parsed.messageConsumption.units
    $featureName = $parsed.messageConsumption.featureName
}
```

If your tenant stores credits at the top level (e.g., `"credits": 0.3`), add a fallback after the `if` block:

```powershell
if ($credits -eq 0 -and $parsed.credits) {
    $credits = [double]$parsed.credits
}
```

### Events with no `msdyn_eventdata` payload

Many events have `msdyn_eventdata = null`. These are typically internal platform events (session state tracking, token refreshes) that do not correspond to user-facing AI interactions. The script records them with `CreditCount = 0` and classifies them as `Unknown` source type. They are harmless and can be filtered out of the CSV by `Is Agent = True` if you only care about agent events.

---

## Known `partnerSource` Values

These values have been seen in the wild. The script maps them in `$script:SourceTypeMap`:

| Raw `partnerSource` | Friendly Label |
|---|---|
| `MicrosoftCopilotStudio` | Copilot Studio Agent |
| `PVA` | Copilot Studio Agent (legacy Power Virtual Agents) |
| `AIBuilder` | AI Builder |
| `DynamicCodeInterpreter` | AI Builder |
| `Flow` / `CloudFlow` / `Workflow` | Power Automate Flow |
| `CanvasApp` / `Canvas` | Power Apps (Canvas) |
| `ModelDrivenApp` | Power Apps (Model-Driven) |
| *(null / missing)* | Unknown |

If you encounter a new value in your tenant, add it to `$script:SourceTypeMap`:

```powershell
$script:SourceTypeMap = @{
    ...
    "YourNewValue" = "Friendly Label"
}
```

Then rerun the report.

---

## Tip: Use the AllEvents CSV for Deep Investigation

The `GeneralConsumption_AllEvents_*.csv` file contains one row per raw event with all extracted fields. Sort by `SourceTypeRaw = Unknown` to find unmapped `partnerSource` values in your environment.
