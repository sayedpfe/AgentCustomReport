# Power BI Template for Copilot Studio Agent Report

This folder contains the Power BI template files for visualizing the agent report data.

## Setup Instructions

### Option 1: Connect to CSV/Excel Output

1. Open Power BI Desktop
2. Click **Get Data** → **Text/CSV** or **Excel**
3. Navigate to the `output` folder and select the generated file
4. Click **Load**

### Option 2: Connect Directly to Dataverse

1. Open Power BI Desktop
2. Click **Get Data** → **Dataverse** (or **Common Data Service**)
3. Enter your environment URL
4. Sign in with your credentials
5. Select the following tables:
   - `bot` (main agents table)
   - `solutioncomponent` (for solution mappings)
   - `solution` (for solution details)
   - `systemuser` (for owner information)

### Option 3: Use Power BI Dataflow

For enterprise scenarios, create a Power BI Dataflow that:
1. Connects to Dataverse for agent metadata
2. Uses Power Query to call the Admin API for usage data
3. Merges the data into a unified dataset

## Recommended Visualizations

### 1. Agent Overview Dashboard
- **Card**: Total Agents Count
- **Card**: Published Agents Count  
- **Card**: Total Active Users
- **Pie Chart**: Agent Status Distribution (Active/Inactive)

### 2. Usage Analytics
- **Bar Chart**: Top 10 Agents by Active Users
- **Line Chart**: Copilot Credits Over Time
- **Table**: Billed vs Non-Billed Credits by Agent

### 3. Ownership & Solutions
- **Bar Chart**: Agents by Owner
- **Table**: Agents by Solution
- **Treemap**: Agents by Business Unit

### 4. Deployment Channels
- **Donut Chart**: Channel Distribution
- **Matrix**: Agents × Channels

## Sample DAX Measures

```dax
// Total Agents
Total Agents = COUNTROWS('Agents')

// Published Agents
Published Agents = CALCULATE(COUNTROWS('Agents'), 'Agents'[is_published] = TRUE)

// Publication Rate
Publication Rate = DIVIDE([Published Agents], [Total Agents], 0)

// Total Billed Credits
Total Billed Credits = SUM('Agents'[billed_credits])

// Total Non-Billed Credits  
Total Non-Billed Credits = SUM('Agents'[non_billed_credits])

// Credit Efficiency
Credit Efficiency = DIVIDE([Total Non-Billed Credits], [Total Billed Credits] + [Total Non-Billed Credits], 0)
```

## Data Refresh

- **Manual**: Run the Python script and refresh Power BI
- **Scheduled**: Set up a scheduled task or Azure Function to run the Python script, then use Power BI scheduled refresh
- **Real-time**: Connect Power BI directly to Dataverse for live data

## Files

- `AgentReport.pbit` - Power BI Template (create after first run)
- `README.md` - This file
