# Sentinel Cloud Discovery Connector

#### NOTE
**Not still a suitable solution. Function Apps executions in Consumption Plan are limited for 10 minutes (at max). Not enough in a corporate environment.**


An automated Azure Function solution that synchronizes Cloud App Discovery data from Microsoft Defender for Cloud Apps (MDA) to Microsoft Sentinel custom tables using Data Collection Rules (DCR).

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/generalschema.png"> </img>
</div>

## Overview

This solution deploys an Azure Function App that periodically retrieves cloud application discovery data from Microsoft Defender for Cloud Apps and ingests it into Microsoft Sentinel. The data includes:

- **Cloud Applications**: App metadata, usage statistics, risk scores, and metrics
- **Cloud Apps Users**: User activity and engagement data
- **Cloud App Info Watchlist**: Extended compliance and security attributes (GDPR, certifications, etc.)

## Architecture

The solution consists of:

1. **Azure Function App** - Timer-triggered function (PowerShell) that runs on a schedule
2. **Data Collection Endpoint (DCE)** - Ingestion endpoint for Sentinel data
3. **Data Collection Rule (DCR)** - Routes data to custom tables
4. **Custom Tables** - Two tables in Log Analytics/Sentinel:
   - `CloudApps_CL` - Application data with usage metrics and risk scores
   - `CloudAppsUsers_CL` - User activity data
5. **Watchlist** - `CloudAppInfo` watchlist for compliance and security enrichment

## Prerequisites

### Azure Requirements

- **Azure Subscription** with contributor access
- **Microsoft Sentinel** workspace (Log Analytics)
- **Microsoft Defender for Cloud Apps** enabled
- **Azure PowerShell** or Azure CLI installed

### Service Principal Setup

Create an Entra ID App Registration with the following API permission:

- **CloudApp-Discovery.Read.All** (Microsoft Graph)

To create the service principal:

```powershell
# Connect to Azure
Connect-AzAccount

# Create the app registration
$app = New-AzADApplication -DisplayName "CloudAppDiscoveryConnector"

# Create service principal
$sp = New-AzADServicePrincipal -ApplicationId $app.AppId

# Create client secret (save this value!)
$secret = New-AzADAppCredential -ObjectId $app.Id

# Grant API permissions (requires admin consent in Azure Portal)
# Navigate to: Entra ID > App registrations > Your App > API permissions
# Add: Microsoft Graph > Application permissions > CloudApp-Discovery.Read.All
```

### Required Information

Before deployment, collect:

1. **Tenant ID** - Your Entra ID tenant
2. **Client ID** - Service Principal application ID
3. **Client Secret** - Service Principal secret
4. **Workspace ID** - Log Analytics workspace GUID
5. **Workspace Name** - Sentinel workspace name
6. **MDA Stream IDs** - Cloud Discovery stream IDs from MDA portal

## Installation

### Quick Start

1. **Clone or download** this repository

2. **Copy the configuration template:**
   ```powershell
   Copy-Item config.ps1 config.ps1
   ```

3. **Edit `config.ps1`** with your values:
   ```powershell
   # Azure Configuration
   $ResourceGroupName = "rg-cloudappdiscovery"
   $Location = "westeurope"
   $WorkspaceName = "MyWorkspace"
   $WorkspaceId = "your-workspace-guid"

   # Service Principal
   $TenantId = "your-tenant-id"
   $ClientId = "your-client-id"
   $ClientSecret = "your-client-secret"

   # Microsoft Defender for Cloud Apps
   $MdaStreamIds = "stream-id-1,stream-id-2"
   $MdaPeriod = "P90D"  # P7D, P30D, or P90D

   # Function Schedule (CRON expression)
   $TimerSchedule = "0 0 * * * *"  # Every hour
   ```

4. **Run the deployment:**
   ```powershell
   .\Deploy.ps1
   ```

   Or use the full deployment script directly:
   ```powershell
   .\Deploy-All.ps1 -ResourceGroupName "rg-cloudappdiscovery" `
                     -WorkspaceName "MyWorkspace" `
                     -WorkspaceId "your-workspace-guid" `
                     -TenantId "your-tenant-id" `
                     -ClientId "your-client-id" `
                     -ClientSecret "your-client-secret" `
                     -MdaStreamIds "stream-id"
   ```

### Deployment Steps

The automated deployment performs the following:

1. ✅ Creates resource group (if doesn't exist)
2. ✅ Deploys Sentinel infrastructure:
   - Data Collection Endpoint (DCE)
   - Data Collection Rule (DCR)
   - Custom tables in Log Analytics
   - CloudAppInfo watchlist
3. ✅ Extracts deployment outputs automatically
4. ✅ Deploys Azure Function App
5. ✅ Configures application settings
6. ✅ Deploys function code

## Configuration

### Timer Schedule

The function runs on a timer schedule defined by a CRON expression. Default is daily at midnight.

**CRON Expression Format:** `{second} {minute} {hour} {day} {month} {day-of-week}`

Examples:
- `0 0 * * * *` - Every hour
- `0 */6 * * * *` - Every 6 hours
- `0 0 */12 * * *` - Every 12 hours
- `0 0 0 * * *` - Daily at midnight

### MDA Period

The data aggregation period for Cloud Discovery:
- `P7D` - Last 7 days (default)
- `P30D` - Last 30 days
- `P90D` - Last 90 days 


### Custom Tables

Data is ingested into these tables:

| Table | Description |
|-------|-------------|
| `CloudApps_CL` | Application data including display name, risk score, category, user count, transaction count, upload/download traffic, domains, and device count |
| `CloudAppsUsers_CL` | User activity data including user identifier (email/UPN), app ID, and app display name |

Additionally, a **watchlist** named `CloudAppInfo` is created containing extended compliance and security attributes (GDPR compliance, certifications, encryption details, etc.) that can be joined with the tables for enrichment.

## Usage

### Querying Data

Use KQL queries in Microsoft Sentinel to analyze the data:

```kql
// View all cloud apps discovered with traffic
CloudApps_CL
| summarize TotalUpload = sum(uploadNetworkTrafficInBytes), 
            TotalDownload = sum(downloadNetworkTrafficInBytes),
            TotalUsers = sum(userCount)
            by displayName, category
| extend TotalTrafficMB = (TotalUpload + TotalDownload) / 1024 / 1024
| order by TotalTrafficMB desc

// Apps with high risk scores
CloudApps_CL
| where riskScore >= 7
| project displayName, riskScore, category, userCount, transactionCount, lastSeenDateTime
| order by riskScore desc

// Most active users per app
CloudAppsUsers_CL
| summarize AppsUsed = dcount(appId) by userIdentifier
| top 10 by AppsUsed desc

// Join with watchlist for compliance info
CloudApps_CL
| join kind=leftouter (
    _GetWatchlist('CloudAppInfo')
    | project id, isGdprCompliant=isGdprRightToAccess, isHipaaCompliant, isSoc2Compliant
) on $left.id == $right.id
| project displayName, riskScore, category, isGdprCompliant, isHipaaCompliant, isSoc2Compliant
```

### Monitoring

Monitor the function execution:

1. Navigate to **Function App** in Azure Portal
2. Go to **Functions** > **SyncCloudAppsToSentinel**
3. Select **Monitor** tab
4. Review execution logs and metrics

### Manual Execution

To manually trigger the function:

```powershell
# Using Azure CLI
az functionapp function invoke --name <function-app-name> `
                                --resource-group <resource-group> `
                                --function-name SyncCloudAppsToSentinel
```

Or use the **Test/Run** button in the Azure Portal.

## Troubleshooting

### Common Issues

**Issue: "CloudApp-Discovery.Read.All permission not granted"**
- Solution: Grant admin consent for the API permission in Azure Portal

**Issue: "Failed to obtain access token"**
- Verify tenant ID, client ID, and client secret are correct
- Check service principal hasn't expired

**Issue: "No data in Sentinel tables"**
- Verify MDA Stream IDs are correct
- Check function execution logs for errors
- Ensure DCE and DCR are properly configured

**Issue: "Function timeout"**
- Adjust function timeout in `host.json` (default: 10 minutes)
- Consider reducing MDA period or batch size

### Logs

View detailed logs in:
- **Application Insights** (linked to Function App)
- **Log Analytics** workspace
- **Function App** > Monitor section

```kql
// Query function logs in Log Analytics
FunctionAppLogs
| where FunctionName == "SyncCloudAppsToSentinel"
| order by TimeGenerated desc
```

## Project Structure

```
├── config.ps1                        # Configuration file (user-created)
├── Deploy.ps1                        # Simple deployment wrapper
├── Deploy-All.ps1                    # Full automated deployment script
├── function-app/
│   ├── azuredeploy.json             # Function App ARM template
│   ├── sentinel-config.json         # Sentinel infrastructure ARM template
│   ├── host.json                    # Function App host configuration
│   ├── profile.ps1                  # PowerShell profile
│   ├── requirements.psd1            # PowerShell module dependencies
│   └── SyncCloudAppsToSentinel/
│       ├── function.json            # Function binding configuration
│       └── run.ps1                  # Main function code
└── README.md                        # This file
```

## Security Considerations

- **Client Secret**: Store securely; consider using Azure Key Vault
- **Managed Identity**: Future enhancement to eliminate client secrets
- **RBAC**: Grant minimal required permissions
- **Network**: Consider private endpoints for production deployments

## Maintenance

### Updating the Function

To update function code after deployment:

```powershell
# Navigate to function-app directory
cd function-app

# Deploy updated code
func azure functionapp publish <function-app-name>
```

### Rotating Secrets

When rotating the service principal secret:

1. Create new secret in Entra ID
2. Update Function App application settings:
   ```powershell
   az functionapp config appsettings set --name <function-app-name> `
                                          --resource-group <resource-group> `
                                          --settings CLIENT_SECRET="new-secret"
   ```

## Limitations

- Maximum batch size: 1 MB per API call
- Maximum records per batch: 1,000
- Function timeout: 10 minutes (configurable)
- DCR ingestion limits apply


## Version History

- **v1.0** - Initial release
  - Basic MDA to Sentinel sync
  - Automated deployment scripts
  - Two custom tables (CloudApps, CloudAppsUsers)
  - CloudAppInfo watchlist for compliance enrichment

## Support

For issues or questions:
- Check the troubleshooting section
- Review function execution logs
- Open an issue in the repository

## Version History

- **v1.0** - Initial release
  - Basic MDA to Sentinel sync
  - Automated deployment scripts
  - Two custom tables support
  - One Sentinel latchlist

---

**Last Updated:** December 2025








