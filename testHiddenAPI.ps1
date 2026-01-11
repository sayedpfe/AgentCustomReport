<#
.SYNOPSIS
    Export Copilot Studio usage report from Power Platform Admin Center API
.DESCRIPTION
    Tests the PPAC export API to retrieve Copilot Studio message consumption data
    including potential credits fields not available in other APIs.
#>

# --- CONFIG ---
$ppacBase   = "https://admin.powerplatform.microsoft.com"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$csvOutDir  = $scriptDir
$reportScope = "Tenant"  # Use "Tenant" for all environments, or "Environment" for specific env

# --- FUNCTIONS ---
function Get-AuthToken {
    Write-Host "`n🔐 Authenticating with Azure AD..." -ForegroundColor Cyan
    
    $clientId = "49676daf-ff23-4aac-adcc-55472d4e2ce0"  # Power Platform Admin CLI
    $scope = "https://admin.powerplatform.microsoft.com/.default"
    $deviceCodeUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode"
    $tokenUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

    # Request device code
    $deviceCodeBody = @{
        client_id = $clientId
        scope     = $scope
    }
    
    try {
        $deviceCodeResponse = Invoke-RestMethod -Method Post -Uri $deviceCodeUrl -Body $deviceCodeBody -ContentType "application/x-www-form-urlencoded"
        
        Write-Host "`n$($deviceCodeResponse.message)" -ForegroundColor Yellow
        Write-Host "`nWaiting for authentication..." -ForegroundColor Cyan
        
        # Poll for token
        $tokenBody = @{
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            client_id   = $clientId
            device_code = $deviceCodeResponse.device_code
        }
        
        $timeout = [DateTime]::Now.AddSeconds($deviceCodeResponse.expires_in)
        $interval = $deviceCodeResponse.interval
        
        while ([DateTime]::Now -lt $timeout) {
            Start-Sleep -Seconds $interval
            
            try {
                $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
                Write-Host "   ✓ Authentication successful`n" -ForegroundColor Green
                return $tokenResponse.access_token
            }
            catch {
                if ($_.Exception.Response.StatusCode -ne 400) {
                    throw
                }
            }
        }
        
        throw "Authentication timed out"
    }
    catch {
        Write-Host "   ❌ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# --- MAIN SCRIPT ---
Write-Host @"

╔══════════════════════════════════════════════════════════════════════╗
║   PPAC REPORT EXPORT TEST: Copilot Studio Usage                     ║
╚══════════════════════════════════════════════════════════════════════╝

"@

try {
    # Step 1: Authenticate
    $token = Get-AuthToken
    
    # Create output directory
    if (-not (Test-Path $csvOutDir)) {
        New-Item -ItemType Directory -Path $csvOutDir -Force | Out-Null
    }
    
    # Step 2: Create export job
    Write-Host "📤 Creating export job..." -ForegroundColor Cyan
    
    $createBody = @{
        reportName = "Copilot Studio - Message consumption"
        scope      = $reportScope
        period     = "Last30Days"
    }
    
    # Add environmentId only if scope is Environment
    if ($reportScope -eq "Environment") {
        Write-Host "   ⚠ Environment scope selected but no environment ID configured" -ForegroundColor Yellow
        Write-Host "   Switching to Tenant scope for all environments..." -ForegroundColor Yellow
        $createBody.scope = "Tenant"
    }
    
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
        "Accept"        = "application/json"
    }
    
    $createResp = Invoke-WebRequest `
        -UseBasicParsing `
        -Method POST `
        -Uri "$ppacBase/api/reports/export" `
        -Headers $headers `
        -Body ($createBody | ConvertTo-Json) `
        -ErrorAction Stop
    
    $jobResponse = ConvertFrom-Json $createResp.Content
    $jobId = $jobResponse.jobId
    
    if (-not $jobId) {
        throw "No job ID returned from export request"
    }
    
    Write-Host "   ✓ Export job started: $jobId" -ForegroundColor Green
    
    # Step 3: Poll until completed
    Write-Host "`n⏳ Polling job status..." -ForegroundColor Cyan
    $maxWait = 900
    $sleepSec = 5
    $elapsed = 0
    $status = "Pending"
    
    do {
        Start-Sleep -Seconds $sleepSec
        $elapsed += $sleepSec
        
        $statusResp = Invoke-WebRequest `
            -UseBasicParsing `
            -Method GET `
            -Uri "$ppacBase/api/reports/export/$jobId/status" `
            -Headers $headers `
            -ErrorAction Stop
        
        $statusData = ConvertFrom-Json $statusResp.Content
        $status = $statusData.status
        
        Write-Host "   Status: $status (elapsed ${elapsed}s)" -ForegroundColor Gray
        
    } while ($status -notin @("Completed", "Failed", "Error") -and $elapsed -lt $maxWait)
    
    if ($status -eq "Failed" -or $status -eq "Error") {
        throw "Export job failed with status: $status"
    }
    
    if ($status -ne "Completed") {
        throw "Export job timed out after ${maxWait}s"
    }
    
    Write-Host "   ✓ Export completed successfully" -ForegroundColor Green
    
    # Step 4: Download the CSV
    Write-Host "`n💾 Downloading report..." -ForegroundColor Cyan
    
    $downloadResp = Invoke-WebRequest `
        -UseBasicParsing `
        -Method GET `
        -Uri "$ppacBase/api/reports/export/$jobId/file" `
        -Headers $headers `
        -ErrorAction Stop
    
    $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $outFile = Join-Path $csvOutDir "CopilotStudio_MessageConsumption_${ts}.csv"
    [IO.File]::WriteAllBytes($outFile, $downloadResp.Content)
    
    Write-Host "   ✓ Report saved: $outFile" -ForegroundColor Green
    
    # Step 5: Analyze CSV content
    Write-Host "`n📊 Analyzing report content..." -ForegroundColor Cyan
    
    if (Test-Path $outFile) {
        $csvContent = Import-Csv $outFile
        $columnCount = ($csvContent | Get-Member -MemberType NoteProperty).Count
        $rowCount = ($csvContent | Measure-Object).Count
        
        Write-Host "   Rows: $rowCount" -ForegroundColor White
        Write-Host "   Columns: $columnCount" -ForegroundColor White
        Write-Host "`n   Column Names:" -ForegroundColor White
        
        ($csvContent | Get-Member -MemberType NoteProperty).Name | ForEach-Object {
            Write-Host "      - $_" -ForegroundColor Gray
        }
        
        # Check for credits-related columns
        $creditsColumns = ($csvContent | Get-Member -MemberType NoteProperty).Name | 
            Where-Object { $_ -match 'credit|billed|consumption|usage' }
        
        if ($creditsColumns) {
            Write-Host "`n   ✅ FOUND CREDITS-RELATED COLUMNS:" -ForegroundColor Green
            $creditsColumns | ForEach-Object {
                Write-Host "      🎯 $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "`n   ⚠ No obvious credits-related columns found" -ForegroundColor Yellow
        }
        
        # Show sample data
        if ($rowCount -gt 0) {
            Write-Host "`n   Sample Row (first 5 columns):" -ForegroundColor White
            $sampleRow = $csvContent | Select-Object -First 1
            ($sampleRow | Get-Member -MemberType NoteProperty | Select-Object -First 5).Name | ForEach-Object {
                Write-Host "      $_ = $($sampleRow.$_)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ Export completed successfully!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
}
catch {
    Write-Host "`n❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        Write-Host "   Status Description: $($_.Exception.Response.StatusDescription)" -ForegroundColor Red
    }
    Write-Host ""
    exit 1
}
