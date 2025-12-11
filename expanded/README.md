# Cloud App Discovery to Sentinel Connector

An Azure Function-based connector that automatically syncs Cloud App Discovery data from Microsoft Defender for Cloud Apps (MDA) to Microsoft Sentinel custom tables and watchlist.

## Overview

This solution provides automated, scheduled ingestion of cloud application discovery data into Microsoft Sentinel, enabling security teams to:
- Monitor discovered cloud applications and their risk scores
- Track user activity across cloud applications
- Correlate cloud app usage with security incidents
- Create custom analytics rules and workbooks based on cloud discovery data

### Architecture

The connector consists of:
- **Azure Function App** with PowerShell runtime running on a timer trigger (default: hourly)
- **Data Collection Endpoint (DCE)** for secure ingestion into Sentinel
- **Data Collection Rule (DCR)** defining the schema and transformation logic
- **Custom Sentinel Tables**: `CloudApps_CL` and `CloudAppsUsers_CL`
- **Sentinel Watchlist** containing detailed cloud app information (compliance, security features, GDPR attributes)

### Data Flow

1. Azure Function authenticates to Microsoft Graph API
2. Retrieves cloud app discovery data from MDA streams
3. Processes and enriches data with app information
4. Uploads data to Sentinel via Logs Ingestion API using DCR
5. Updates Sentinel Watchlist with detailed app metadata

## Prerequisites

### Azure Resources
- Azure Subscription with Contributor access
- Microsoft Sentinel workspace (Log Analytics workspace)
- Microsoft Defender for Cloud Apps (MDA) with Cloud Discovery configured

### Required Tools
- Azure CLI or PowerShell
- Azure Functions Core Tools v4 
- PowerShell 7+ (for local development)

### Service Principal Requirements

Create an Entra ID App Registration with the following permissions:

**Microsoft Graph API**:
- `CloudApp-Discovery.Read.All` (Application permission)

**Azure RBAC Roles** (on the Log Analytics workspace):
- `Log Analytics Contributor` and `Monitoring Metrics Publisher`

Grant admin consent for all API permissions after creation.

## Deployment

### Step 1: Configure Sentinel Infrastructure

Deploy the Data Collection infrastructure to your Sentinel workspace


<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmariocuomo%2FSentinel-Cloud-Discovery-Connector%2Frefs%2Fheads%2Fmain%2Fexpanded%2Fsentinel-config.json" target="_blank">
<img src="https://aka.ms/deploytoazurebutton"/>
</a>

The `sentinel-config.json` ARM template deploys the following Microsoft Sentinel infrastructure components:
- 1 Data Collection Endpoint
- 1 Data Collection Rule
- 2 Log Analytics Workspace tables (`CloudApps_CL` and `CloudAppsUsers_CL`)
- 1 Sentinel watchlist (`CloudAppInfo`)


**Note the outputs** from this deployment:
- `dceEndpoint` - Data Collection Endpoint URL
- `dcrImmutableId` - Data Collection Rule Immutable ID

---


### Step 2: Configure Function App Parameters

Edit `function-app/azuredeploy.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "tenantId": { "value": "YOUR_TENANT_ID" },
    "clientId": { "value": "YOUR_CLIENT_ID" },
    "clientSecret": { "value": "YOUR_CLIENT_SECRET" },
    "mdaStreamIds": { "value": "streamId1,streamId2" },
    "dceEndpoint": { "value": "YOUR_DCE_ENDPOINT" },
    "dcrImmutableId": { "value": "YOUR_DCR_IMMUTABLE_ID" },
    "workspaceId": { "value": "YOUR_WORKSPACE_ID" },
    "workspaceName": { "value": "YOUR_WORKSPACE_NAME" }
  }
}
```

### Step 3: Deploy Function App

```powershell
# Create resource group for function app
az group create --name rg-cloudappsync --location westeurope

# Deploy ARM template
az deployment group create \
  --resource-group rg-cloudappsync \
  --template-file function-app/azuredeploy.json \
  --parameters function-app/azuredeploy.parameters.json

# Deploy function code
cd function-app
func azure functionapp publish <your-function-app-name>
```

**Alternative**: Use VS Code Azure Functions extension:
- Right-click `function-app` folder → "Deploy to Function App..."

### Step 5: Verify Deployment

**Monitor function execution**:
```powershell
func azure functionapp logstream <your-function-app-name>
```

**Query Sentinel data** (wait ~1 hour for first run):
```kql
CloudApps_CL
| where TimeGenerated > ago(2h)
| order by TimeGenerated desc
| take 10
```

```kql
CloudAppsUsers_CL
| where TimeGenerated > ago(2h)
| summarize UserCount = dcount(userIdentifier) by appDisplayName
| order by UserCount desc
```

**Check Watchlist**:
```kql
_GetWatchlist('CloudAppInfo')
| take 10
```

## Configuration

### Environment Variables

The function app uses the following configuration (set automatically by ARM template):

| Variable | Description |
|----------|-------------|
| `TENANT_ID` | Azure AD Tenant ID |
| `CLIENT_ID` | Service Principal Client ID |
| `CLIENT_SECRET` | Service Principal Client Secret |
| `MDA_STREAM_IDS` | Comma-separated MDA Stream IDs |
| `MDA_PERIOD` | Data aggregation period (default: P90D) |
| `DCE_ENDPOINT` | Data Collection Endpoint URL |
| `DCR_IMMUTABLE_ID` | Data Collection Rule Immutable ID |
| `WORKSPACE_ID` | Log Analytics Workspace ID (GUID) |
| `WORKSPACE_NAME` | Log Analytics Workspace Name |
| `SUBSCRIPTION_ID` | Azure Subscription ID |
| `RESOURCE_GROUP_NAME` | Resource Group containing the workspace |
| `WATCHLIST_ALIAS` | Watchlist alias (default: CloudAppInfo) |
| `TIMER_SCHEDULE` | CRON expression (default: hourly) |

### Timer Schedule

Modify the CRON expression in `function.json` or via ARM template parameter:

- `0 0 * * * *` - Every hour (default)
- `0 0 */6 * * *` - Every 6 hours
- `0 0 0 * * *` - Daily at midnight

## Custom Tables Schema

### CloudApps_CL

| Column | Type | Description |
|--------|------|-------------|
| `TimeGenerated` | datetime | Ingestion timestamp |
| `streamId` | string | MDA Stream ID |
| `id` | string | Application ID |
| `displayName` | string | Application display name |
| `tags` | string | Tags (comma-separated) |
| `riskScore` | int | Risk score (0-10) |
| `lastSeenDateTime` | datetime | Last seen date/time |
| `domains` | string | Associated domains |
| `category` | string | Application category |
| `userCount` | int | Number of users |
| `ipAddressCount` | int | Number of IP addresses |
| `transactionCount` | long | Transaction count |
| `uploadNetworkTrafficInBytes` | long | Upload traffic |
| `downloadNetworkTrafficInBytes` | long | Download traffic |
| `deviceCount` | int | Number of devices |

### CloudAppsUsers_CL

| Column | Type | Description |
|--------|------|-------------|
| `TimeGenerated` | datetime | Ingestion timestamp |
| `streamId` | string | MDA Stream ID |
| `appId` | string | Application ID |
| `appDisplayName` | string | Application display name |
| `userIdentifier` | string | User email/UPN |

## Monitoring & Troubleshooting

### Health Checks

1. **Function App Health**:
   - Portal: Function App → Monitor → Metrics
   - Check `Function Execution Count` and `Function Execution Units`

2. **Application Insights**:
   - Portal: Application Insights → Live Metrics
   - Review traces and exceptions

3. **Sentinel Data Ingestion**:
   ```kql
   CloudApps_CL
   | summarize Count = count() by bin(TimeGenerated, 1h)
   | order by TimeGenerated desc
   | take 24
   ```

### Common Issues

**No data in Sentinel**:
- Verify DCE and DCR are deployed correctly
- Check service principal has `Monitoring Metrics Publisher` role on workspace
- Review function execution logs for errors

**Authentication failures**:
- Verify `TENANT_ID`, `CLIENT_ID`, `CLIENT_SECRET` are correct
- Ensure API permissions have admin consent
- Check credentials haven't expired

**Rate limiting (429 errors)**:
- Function implements exponential backoff and retry logic
- Consider reducing sync frequency if issue persists

**Partial data**:
- Check MDA Stream IDs are valid and accessible
- Verify MDA data is available for the specified period

### Logs and Diagnostics

**View function logs**:
```powershell
# Real-time streaming
func azure functionapp logstream <function-app-name>
```

**Query Application Insights**:
```kql
traces
| where timestamp > ago(1h)
| where operation_Name == "SyncCloudAppsToSentinel"
| order by timestamp desc
```

**Check DCR ingestion errors**:
```kql
LAQueryLogs
| where TimeGenerated > ago(1h)
| where QueryText contains "CloudApps_CL"
```

## Ad-hoc Scripts

The `adhoc/` folder contains utility scripts for testing and manual operations:

### Get-CloudAppDiscovery.ps1
Retrieves cloud app discovery data from MDA and exports to CSV files.

**Usage**:
```powershell
cd adhoc
.\Get-CloudAppDiscovery.ps1
```

**Outputs**:
- `CloudApps_<timestamp>.csv` - Application metrics
- `CloudAppsInfo_<timestamp>.csv` - Detailed app information
- `CloudAppsUsers_<timestamp>.csv` - User associations

### Upload-ToSentinel.ps1
Manually uploads CSV files to Sentinel custom tables (useful for testing).

**Usage**:
```powershell
cd adhoc
.\Upload-ToSentinel.ps1
```

## Security Considerations

- **Credentials**: Client secrets are stored in Azure Key Vault references (recommended) or Function App configuration (encrypted at rest)
- **Network Security**: DCE supports network ACLs (currently set to `Enabled` for public access)
- **RBAC**: Service principal follows least-privilege principle with only required permissions
- **Data Encryption**: All data in transit uses TLS 1.2+, data at rest encrypted by Azure Storage

## Cost Estimation

Approximate monthly costs (based on default configuration):

- **Function App**: ~$0 (Consumption plan with low execution count)
- **Storage Account**: ~$1-5 (minimal data)
- **Application Insights**: ~$2-10 (based on telemetry volume)
- **Sentinel Ingestion**: Variable (based on data volume, typically ~$0.50-2/GB)

**Total estimated cost**: $5-20/month depending on data volume and execution frequency.

## Workbook and Analytics

### Workbook Deployment

Deploy the included Sentinel workbook for visualization:

```powershell
# Deploy workbook
az deployment group create \
  --resource-group <your-sentinel-rg> \
  --template-file adhoc/workbook-cloudappdiscovery.json \
  --parameters workspaceName="<your-workspace-name>"
```

### Sample KQL Queries

**Top risky applications**:
```kql
CloudApps_CL
| where TimeGenerated > ago(24h)
| summarize arg_max(TimeGenerated, *) by id
| where riskScore >= 7
| project displayName, riskScore, category, userCount, domains
| order by riskScore desc
```

**User activity across cloud apps**:
```kql
CloudAppsUsers_CL
| where TimeGenerated > ago(7d)
| summarize AppCount = dcount(appId) by userIdentifier
| where AppCount > 5
| order by AppCount desc
```

**Traffic analysis**:
```kql
CloudApps_CL
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, *) by id
| extend TotalTrafficGB = (uploadNetworkTrafficInBytes + downloadNetworkTrafficInBytes) / 1073741824.0
| project displayName, TotalTrafficGB, userCount, transactionCount
| order by TotalTrafficGB desc
```

## Contributing

Contributions are welcome! Please submit issues or pull requests for:
- Bug fixes
- Feature enhancements
- Documentation improvements
- Additional analytics queries

## License

This project is provided as-is under the MIT License.

## References

- [Microsoft Defender for Cloud Apps API](https://learn.microsoft.com/en-us/defender-cloud-apps/api-introduction)
- [Azure Monitor Logs Ingestion API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview)
- [Microsoft Sentinel Watchlists](https://learn.microsoft.com/en-us/azure/sentinel/watchlists)
- [Azure Functions PowerShell Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell)

## Support

For issues, questions, or feature requests, please open an issue in this repository.

