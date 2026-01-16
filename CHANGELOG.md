# Changelog

All notable changes to the Copilot Studio Agent Reporting Solution are documented here.

## [v1.1] - 2026-01-16

### Added
- **Certificate-Based Authentication**: Enterprise-grade authentication using X.509 certificates
  - Service principal support for automated scenarios
  - Non-interactive execution capability
  - Suitable for scheduled tasks and production environments
- **App Registration Support**: Integration with Azure AD App Registrations
- **Dual Authentication Mode**: Choose between certificate-based or device code flow
- **Comprehensive Setup Documentation**: [APP_REGISTRATION_SETUP.md](APP_REGISTRATION_SETUP.md)
  - Step-by-step App Registration configuration
  - Certificate creation and management guide
  - API permissions setup
  - Troubleshooting section
  - Security best practices

### Changed
- **Get-CompleteCopilotReport.ps1**: Updated to v1.1
  - Added `-UseCertificateAuth` switch parameter
  - Added `-AppId` parameter for App Registration client ID
  - Added `-CertificateThumbprint` parameter for certificate authentication
  - Refactored authentication functions:
    - `Get-CertificateToken`: Handles certificate-based authentication
    - `Get-DeviceCodeToken`: Handles interactive Device Code Flow
    - `Get-AuthToken`: Router function for authentication method selection
  - Enhanced parameter validation for certificate auth
  - Improved error messages and authentication flow indicators
- **README.md**: Updated for v1.1
  - Added authentication methods comparison
  - Certificate-based authentication usage examples
  - Enhanced quick start section
  - Added feature highlights for v1.1

### Backward Compatibility
- ✅ Fully backward compatible with v1.0
- Device Code Flow remains the default (no parameters needed)
- All existing scripts and workflows continue to function without changes

### Security Enhancements
- JWT assertion signing with certificate private key
- Secure certificate store integration (CurrentUser\My, LocalMachine\My)
- Client credentials flow with certificate authentication
- Enhanced token security for automated scenarios

---

## [v1.0] - 2026-01-16

### Added
- **Azure Resource Graph Integration**: Switched from Power Platform Inventory API
  - Direct KQL query support
  - Official Microsoft API with full documentation
  - More reliable than KQLOM JSON format
- **Single Comprehensive Script**: `Get-CompleteCopilotReport.ps1`
  - All-in-one solution combining inventory + credits + merge
  - Auto-authentication handling
  - Smart error handling
  - Comprehensive progress indicators
- **Complete Documentation Suite**:
  - README.md with technical details
  - EXECUTIVE_SUMMARY.md with results
  - GITHUB_CHECKLIST.md for implementation
  - LICENSE (MIT) with API disclaimers
  - .gitignore for security
- **Final Results**:
  - 115 agents tracked
  - 4,911.9 MB credits monitored
  - 8/12 fields successfully retrieved
  - ~2 minute execution time

### Fixed
- **Power Platform Inventory API Issue**: KQLOM format stopped working
  - Error: "KQLOM format is wrong or it cannot be null"
  - Solution: Migrated to Azure Resource Graph with direct KQL
  - Impact: More reliable, better documented, officially supported

### Removed
- Test files cleaned from repository
- CSV output files excluded via .gitignore
- Temporary testing scripts removed

### Performance
- Execution time: ~2 minutes for 115 agents across 8 environments
- Single authentication per API (2 total: Azure + Licensing)
- Efficient parallel environment processing

---

## [Pre-v1.0] - Initial Development

### Initial Implementation
- **Three-Script Workflow**:
  - Get-AllAgents-InventoryAPI-v2.ps1: Inventory retrieval
  - Get-CopilotCredits-v2.ps1: Credits consumption
  - Merge-InventoryAndCredits.ps1: Data consolidation
- **Power Platform Inventory API**: Initial implementation with KQLOM format
- **Licensing API Discovery**: Found via browser F12 tools
- **OAuth 2.0 Device Code Flow**: Interactive authentication

### Explored APIs
- Power Platform Inventory API (KQLOM format)
- Azure Resource Graph (successful pivot)
- Dataverse API (experimental for Solution ID)
- Power Platform Admin API (limited data)
- Various undocumented endpoints

---

## Versioning Scheme

**Format**: `vMAJOR.MINOR`

- **MAJOR**: Breaking changes, significant architecture updates
- **MINOR**: New features, enhancements, backward-compatible changes

**Branch Strategy**:
- `main`: Production releases
- `v1.0-stable`: Preserved v1.0 with Device Code authentication
- `v1.1-app-registration`: Active development for certificate authentication
- Feature branches as needed

---

## Upcoming Features (Roadmap)

### v1.2 (Planned)
- Azure Key Vault integration for certificate storage
- Enhanced logging and transcript support
- Email report delivery
- Dashboard visualization (Power BI integration)

### v2.0 (Future)
- Dataverse direct integration for Solution ID/Description
- Multi-tenant support
- Historical trend analysis
- REST API wrapper for external integrations

---

## Support

For issues, questions, or contributions:
1. Check [README.md](README.md) for usage instructions
2. Review [APP_REGISTRATION_SETUP.md](APP_REGISTRATION_SETUP.md) for certificate setup
3. See [EXECUTIVE_SUMMARY.md](EXECUTIVE_SUMMARY.md) for expected results
4. Consult troubleshooting sections in documentation

---

**Repository**: https://github.com/sayedpfe/AgentCustomReport  
**License**: MIT (see [LICENSE](LICENSE))
