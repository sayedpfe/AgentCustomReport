<#
.SYNOPSIS
    Merge Inventory API data (all 115 agents) with Credits API data (usage)
.DESCRIPTION
    Combines the complete agent list from Inventory API with credits consumption data.
    Agents without usage will show 0 for billed and non-billed credits.
#>

param(
    [string]$InventoryFile = "..\CopilotAgents_InventoryAPI.csv",
    [string]$CreditsFile = ".\CopilotCredits_Summary_*.csv"  # Uses latest
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   MERGE: Inventory + Credits Data                                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Find inventory file
$invPath = Join-Path $scriptDir $InventoryFile
if (-not (Test-Path $invPath)) {
    Write-Host "❌ Inventory file not found: $invPath" -ForegroundColor Red
    exit 1
}

# Find latest credits file
$creditsPath = Get-ChildItem -Path $scriptDir -Filter "CopilotCredits_Summary_*.csv" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

if (-not $creditsPath) {
    Write-Host "❌ No credits summary file found matching: $CreditsFile" -ForegroundColor Red
    exit 1
}

Write-Host "📂 Loading data files..." -ForegroundColor Cyan
Write-Host "   Inventory: $(Split-Path $invPath -Leaf)" -ForegroundColor Gray
Write-Host "   Credits:   $($creditsPath.Name)" -ForegroundColor Gray
Write-Host ""

# Load data
$inventory = Import-Csv $invPath
$credits = Import-Csv $creditsPath.FullName

Write-Host "📊 Data loaded:" -ForegroundColor White
Write-Host "   Total Agents (Inventory): $($inventory.Count)" -ForegroundColor Green
Write-Host "   Agents with Usage (Credits): $($credits.Count)" -ForegroundColor Green
Write-Host "   Agents with Zero Usage: $($inventory.Count - $credits.Count)" -ForegroundColor Yellow
Write-Host ""

# Create lookup dictionary for credits
$creditsLookup = @{}
foreach ($credit in $credits) {
    $creditsLookup[$credit.ResourceId] = $credit
}

# Merge data
Write-Host "🔗 Merging datasets..." -ForegroundColor Cyan

$mergedData = foreach ($agent in $inventory) {
    $agentId = $agent."Item ID"
    $creditData = $creditsLookup[$agentId]
    
    [PSCustomObject]@{
        "Agent ID"              = $agentId
        "Agent Name"            = $agent."Item name"
        "Environment"           = $agent.Environment
        "Environment ID"        = $agent."Environment ID"
        "Environment Type"      = $agent."Environment type"
        "Environment Region"    = $agent."Environment region"
        "Created On"            = $agent."Created on"
        "Modified On"           = $agent."Modified on"
        "Published On"          = $agent."Published on"
        "Owner"                 = $agent.Owner
        "Created In"            = $agent."Created in"
        "Billed Credits (MB)"   = if ($creditData) { $creditData.TotalBilledCredits } else { 0 }
        "Non-Billed Credits (MB)" = if ($creditData) { $creditData.TotalNonBilledCredits } else { 0 }
        "Total Credits (MB)"    = if ($creditData) { $creditData.TotalCredits } else { 0 }
        "Has Usage"             = if ($creditData) { "Yes" } else { "No" }
    }
}

Write-Host "   ✓ Merged complete`n" -ForegroundColor Green

# Export combined data
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputFile = Join-Path $scriptDir "CopilotAgents_Complete_${timestamp}.csv"

$mergedData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   MERGE SUMMARY                                                      ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

# Statistics
$withUsage = ($mergedData | Where-Object { $_."Has Usage" -eq "Yes" }).Count
$noUsage = ($mergedData | Where-Object { $_."Has Usage" -eq "No" }).Count
$totalBilled = ($mergedData | Measure-Object "Billed Credits (MB)" -Sum).Sum
$totalNonBilled = ($mergedData | Measure-Object "Non-Billed Credits (MB)" -Sum).Sum

Write-Host "📈 Statistics:" -ForegroundColor White
Write-Host "   Total Agents: $($mergedData.Count)" -ForegroundColor Cyan
Write-Host "   Agents with Usage: $withUsage" -ForegroundColor Green
Write-Host "   Agents without Usage: $noUsage" -ForegroundColor Yellow
Write-Host ""
Write-Host "💰 Total Credits:" -ForegroundColor White
Write-Host "   Billed: $([math]::Round($totalBilled, 2)) MB" -ForegroundColor Green
Write-Host "   Non-Billed: $([math]::Round($totalNonBilled, 2)) MB" -ForegroundColor Green
Write-Host "   Total: $([math]::Round($totalBilled + $totalNonBilled, 2)) MB" -ForegroundColor Cyan
Write-Host ""

# Show top 10 by usage
Write-Host "🏆 Top 10 Agents by Total Credits:" -ForegroundColor Yellow
$mergedData | 
    Where-Object { $_."Total Credits (MB)" -gt 0 } |
    Sort-Object { [double]$_."Total Credits (MB)" } -Descending | 
    Select-Object -First 10 |
    Format-Table -AutoSize -Property @(
        @{Label="Agent Name"; Expression={$_."Agent Name"}; Width=40}
        @{Label="Environment"; Expression={$_.Environment}; Width=20}
        @{Label="Billed (MB)"; Expression={$_."Billed Credits (MB)"}; Width=12}
        @{Label="Non-Billed (MB)"; Expression={$_."Non-Billed Credits (MB)"}; Width=15}
        @{Label="Total (MB)"; Expression={$_."Total Credits (MB)"}; Width=12}
    )

Write-Host "💾 Complete dataset saved: $(Split-Path $outputFile -Leaf)" -ForegroundColor Cyan
Write-Host "   All 115 agents with credits data (0 for unused agents)`n" -ForegroundColor Gray

Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ Merge completed successfully!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
