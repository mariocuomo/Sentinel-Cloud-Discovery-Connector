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

1. Azure Function authenticates to Microsoft Graph API (1)
2. Retrieves cloud app discovery data from MDA streams (1)
3. Processes and enriches data with app information (2)
4. Uploads data to Sentinel via Logs Ingestion API using DCR (2)
5. Updates Sentinel Watchlist with detailed app metadata (3)

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/generalschema.png"> </img>
</div>

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

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/sentinel-config.png"> </img>
</div>

If you want read more about this template, read [here](https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/README-SENTINEL-CONFIG.md).

**Note the outputs** from this deployment:
- `dceEndpoint` - Data Collection Endpoint URL
- `dcrImmutableId` - Data Collection Rule Immutable ID

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/dcr.png"> </img>
</div>
<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/dce.png"> </img>
</div>
<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/tables.png"> </img>
</div>
<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/watchlist.png"> </img>
</div>
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

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/expanded/img/parameters.png"> </img>
</div>

---

### Step 3: Deploy Function App

Upload all files to Azure Cloud Shell and ensure the folder structure matches the project exactly: `function-app/` at the root level containing `SyncCloudAppsToSentinel/` subfolder with `function.json` and `run.ps1`, along with `azuredeploy.json`, `azuredeploy.parameters.json`, `host.json`, `profile.ps1`, `requirements.psd1`, at the function-app level.

```
function-app/
├── SyncCloudAppsToSentinel/
│   ├── function.json
│   └── run.ps1
├── azuredeploy.json
├── azuredeploy.parameters.json
├── host.json
├── profile.ps1
└── requirements.psd1
```

Maintain this exact directory structure when deploying to preserve the Function App's configuration and ensure proper execution of the timer-triggered function.


At this point, **deploy ARM template**

```powershell
az deployment group create `
  --resource-group rg-cloudappsync `
  --template-file azuredeploy.json `
  --parameters azuredeploy.parameters.json
```


**Deploy the function**
```powershell
func azure functionapp publish func-cloudappsync
```









