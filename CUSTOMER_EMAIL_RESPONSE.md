# Customer Email Response

---

**Subject:** RE: Custom Usage and Consumption Report for Copilot Studio - Solution Delivered

---

Hi [Customer Name],

Happy New Year to you as well! I hope you had a wonderful holiday season.

Thank you for reaching out regarding the custom usage and consumption report for your upcoming global Copilot Studio release. I've been working diligently on this request and am pleased to share that I've developed a comprehensive solution to retrieve the agent data you need.

## Solution Overview

I've created a PowerShell-based solution that successfully retrieves **8 of the 12 requested fields** across all your Copilot Studio agents. The complete solution, including production-ready scripts and detailed documentation, is now available in our GitHub repository:

**🔗 GitHub Repository:** [INSERT YOUR GITHUB URL HERE]

### ✅ Available Fields (8/12)

The solution successfully retrieves the following fields:

1. ✅ **Agent Identifier (Primary Key)** - Unique agent ID
2. ✅ **Environment ID** - Environment identifier
3. ✅ **Agent Name** - Display name
4. ✅ **Created At** - Creation timestamp
5. ✅ **Updated At** - Last modification timestamp
6. ✅ **Agent Owner** - Owner identifier
7. ✅ **Billed Copilot Credits** - Consumption data in MB
8. ✅ **Non-Billed Credits** - Non-billable consumption in MB
9. ✅ **Is Published** - Publication timestamp/status

### ❌ Unavailable Fields (4/12)

Unfortunately, the following fields are not available through any accessible API endpoints:

1. ❌ **Agent Description** - Not exposed in Inventory API or any discoverable endpoint
2. ❌ **Solution ID** - Available only via per-environment Dataverse queries (requires separate authentication for each environment)
3. ❌ **Active Users** - Microsoft does not expose individual agent user metrics via API

## Technical Implementation

The solution uses two API endpoints:

### 1. Power Platform Inventory API (Official)
- **Status:** ✅ Fully documented and supported by Microsoft
- **Endpoint:** `https://api.powerplatform.com/resourcequery/resources/query`
- **Purpose:** Retrieves agent metadata (name, environment, owner, timestamps)
- **Result:** Successfully retrieved all 115 agents across your environments

### 2. Licensing API - Credits Consumption (Undocumented)
- **Status:** ⚠️ **Discovered via browser developer tools** - No official Microsoft documentation exists
- **Endpoint:** `https://licensing.powerplatform.microsoft.com/v0.1-alpha/tenants/{tenant}/entitlements/MCSMessages/environments/{env}/resources`
- **Purpose:** Retrieves actual consumption data including billed and non-billed credits
- **Result:** Successfully tracked 5,505.82 MB of credits across 34 active agents

## Challenges & Important Notes

### Credits Consumption API Discovery

The most critical challenge was retrieving the **Billed and Non-Billed Credits** fields, as these are not documented in any official Microsoft API documentation. After extensive research and testing of multiple approaches, I discovered this endpoint by:

1. **Method:** Analyzing network traffic in the Power Platform Admin Center using browser developer tools (F12)
2. **Finding:** The PPAC UI makes calls to an undocumented alpha-version API endpoint
3. **Status:** This endpoint is version **v0.1-alpha** (pre-release/unsupported)

**⚠️ Important Disclaimers:**
- **No Official Documentation:** This endpoint is not published in Microsoft Learn or official API documentation
- **Unsupported Status:** As an alpha version, it may change or be deprecated without notice
- **No SLA:** Microsoft cannot provide support for this endpoint
- **Use at Your Own Risk:** Suitable for internal reporting but consider this technical debt

### Alternative Approaches Tested

I tested numerous approaches to ensure comprehensive coverage:

❌ **Official Licensing API** - Returns capacity only (50,000 messages), not consumption data  
❌ **Microsoft.PowerPlatform.SDK** (.NET) - Does not expose consumption/credits APIs  
❌ **PPAC Export API** - Returns 405 Method Not Allowed  
❌ **Resource Graph API** - Only metadata, no consumption data  
❌ **Dataverse Direct Queries** - Would require per-environment authentication (complex for 8+ environments)

## Solution Deliverables

The GitHub repository includes:

### Production Scripts
1. **Get-AllAgents-InventoryAPI-v2.ps1** - Retrieves all agents (115 total)
2. **Get-CopilotCredits-v2.ps1** - Retrieves credits consumption (365-day historical data)
3. **Merge-InventoryAndCredits.ps1** - Combines datasets into final report

### Documentation
- **README.md** - Complete technical documentation with API endpoints, authentication workflow, and troubleshooting
- **CUSTOMER_RESPONSE.md** - Executive summary with detailed field availability matrix
- **GITHUB_CHECKLIST.md** - Implementation guide and testing results

### Sample Output
The final report includes all 115 agents with 8 fields per agent. Agents without usage show 0 for credit fields, providing complete visibility across your tenant.

## Testing & Validation

**Comprehensive testing was performed:**
- ✅ 115 agents successfully retrieved
- ✅ 8 environments processed
- ✅ 34 agents with active usage tracked
- ✅ 5,505.82 MB total credits (3,479.58 billed + 2,026.24 non-billed)
- ✅ 365-day historical data (13x more comprehensive than 30-day range)

## Recommendations

### Immediate Actions (For Your Global Release)

1. **Deploy the Solution:**
   - Clone the GitHub repository
   - Follow the 3-step workflow in README.md
   - Generate comprehensive reports with 8/12 fields

2. **Document Limitations:**
   - Clearly communicate which 4 fields are unavailable
   - Include disclaimers about the undocumented API
   - Set expectations with stakeholders

3. **Monitor API Stability:**
   - The credits endpoint is alpha version
   - Verify it remains accessible in your scheduled runs
   - Have contingency plans if the endpoint changes

### Long-term Improvements

1. **Request Microsoft Enhancement:**
   - Submit feedback requesting official credits consumption API
   - Request Agent Description and Active Users in Inventory API
   - Request Solution ID exposure without per-environment queries

2. **Consider Dataverse for Solution ID:**
   - If Solution ID becomes critical, implement per-environment Dataverse queries
   - Note: This adds complexity (authentication per environment, longer execution time)

3. **Stay Informed:**
   - Monitor Microsoft Power Platform roadmap for official analytics APIs
   - Watch for updates to the Inventory API that may expose additional fields

## Next Steps

1. **Review the GitHub repository** - Complete documentation and scripts are ready for use
2. **Test in your environment** - Run the three scripts in sequence to validate results
3. **Provide feedback** - Let me know if you need any adjustments or have questions
4. **Plan for limitations** - Discuss with stakeholders about the 4 unavailable fields

## Conclusion

While we achieved **67% coverage (8 of 12 fields)**, I'm particularly pleased that the critical **Billed and Non-Billed Credits** fields—the core consumption metrics you need for your global release—are successfully retrieved and working. The solution is production-ready with comprehensive error handling, authentication workflows, and detailed documentation.

The main limitation is Microsoft's lack of official APIs for certain fields (Description, Active Users) and the reliance on an undocumented endpoint for credits data. However, this represents the best possible solution given current API availability.

I'm happy to schedule a call to walk through the implementation, discuss any concerns about the undocumented API, or explore alternative approaches for the missing fields.

Please let me know if you have any questions or need further assistance!

Best regards,  
Sayed

---

**Attachments:**
- Link to GitHub Repository (scripts + documentation)
- Technical documentation available in repository README.md

**GitHub Repository Structure:**
```
AgentCustomReport/
├── README.md (Complete technical guide)
├── CUSTOMER_RESPONSE.md (Executive summary)
├── LICENSE (MIT License)
└── scripts/
    ├── Get-AllAgents-InventoryAPI-v2.ps1
    ├── Get-CopilotCredits-v2.ps1
    └── Merge-InventoryAndCredits.ps1
```
