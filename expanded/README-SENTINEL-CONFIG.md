# Sentinel Configuration - Azure Resource Manager Template

## Description

The `sentinel-config.json` file is an Azure Resource Manager (ARM) template that configures the infrastructure necessary to integrate Cloud App Discovery data with Microsoft Sentinel.

## Deployed Resources

This template creates and configures the following Azure resources:

### 1. **Data Collection Endpoint (DCE)**
- **Name**: `dce-cloudappdiscovery` (configurable)
- **Type**: `Microsoft.Insights/dataCollectionEndpoints`
- **Purpose**: Public endpoint for log ingestion to Azure Monitor

### 2. **Custom Log Analytics Tables**

#### CloudApps_CL
Table to store discovered cloud application data with the following fields:
- `TimeGenerated`: Event timestamp
- `streamId`: Data stream ID
- `id`: Unique application ID
- `displayName`: Application display name
- `tags`: Associated tags (comma-separated)
- `riskScore`: Risk score (integer)
- `lastSeenDateTime`: Last seen date and time
- `domains`: Associated domains (comma-separated)
- `category`: Application category
- `userCount`: Number of users
- `ipAddressCount`: Number of IP addresses
- `transactionCount`: Number of transactions
- `uploadNetworkTrafficInBytes`: Upload traffic in bytes
- `downloadNetworkTrafficInBytes`: Download traffic in bytes
- `deviceCount`: Number of devices

**Retention**: 90 days

#### CloudAppsUsers_CL
Table to store user-application relationships:
- `TimeGenerated`: Event timestamp
- `streamId`: Data stream ID
- `appId`: Application ID
- `appDisplayName`: Application display name
- `userIdentifier`: User identifier (email or UPN)

**Retention**: 90 days

### 3. **Data Collection Rule (DCR)**
- **Name**: `dcr-cloudappdiscovery` (configurable)
- **Type**: `Microsoft.Insights/dataCollectionRules`
- **Purpose**: Defines data flows and KQL transformations
- **Declared streams**:
  - `Custom-CloudApps`: For application data
  - `Custom-CloudAppsUsers`: For user-application data
- **Transformation**: Automatically adds `TimeGenerated = now()` to each record

### 4. **Sentinel Watchlist**
- **Name**: `CloudAppInfo` (configurable)
- **Type**: `Microsoft.SecurityInsights/watchlists`
- **Purpose**: Contains detailed information about cloud applications
- **Included data**:
  - Vendor and hosting information
  - Compliance (SOC, ISO, GDPR, HIPAA, PCI-DSS, FedRAMP, etc.)
  - Security features (MFA, encryption, audit trail)
  - GDPR attributes (user rights, data protection)
  - Breach information and certifications
- **Search key**: `id` (Application ID)
- **Pre-populated content**: Includes Microsoft Exchange Online as an example

## Input Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `workspaceName` | string | Log Analytics workspace (Sentinel) name | *Required* |
| `location` | string | Resource location | Resource Group location |
| `dceName` | string | Data Collection Endpoint name | `dce-cloudappdiscovery` |
| `dcrName` | string | Data Collection Rule name | `dcr-cloudappdiscovery` |
| `watchlistName` | string | Watchlist name | `CloudAppInfo` |

## Outputs

The template returns the following values after deployment:

| Output | Description |
|--------|-------------|
| `dceEndpoint` | Endpoint URL for log ingestion |
| `dcrImmutableId` | Immutable ID of the Data Collection Rule |
| `cloudAppsStream` | Stream name for apps (`Custom-CloudApps`) |
| `cloudAppsUsersStream` | Stream name for users (`Custom-CloudAppsUsers`) |
| `watchlistName` | Name of the created watchlist |
| `watchlistAlias` | Watchlist alias |

## Deployment

### Prerequisites
- Active Azure subscription
- Existing Resource Group
- Microsoft Sentinel workspace (Log Analytics) already created
- Sufficient permissions to create resources

### Azure CLI Command

```bash
az deployment group create \
  --resource-group <nome-resource-group> \
  --template-file sentinel-config.json \
  --parameters workspaceName=<nome-sentinel-workspace>
```

### PowerShell

```powershell
New-AzResourceGroupDeployment `
  -ResourceGroupName <nome-resource-group> `
  -TemplateFile sentinel-config.json `
  -workspaceName <nome-sentinel-workspace>
```

### With parameters file

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file sentinel-config.json \
  --parameters @sentinel-config.parameters.json
```

## Post-Deployment

After deployment, save the following values to configure the Azure Function:

1. **DCE Endpoint**: URL for sending logs
2. **DCR Immutable ID**: Data Collection Rule ID
3. **Stream Names**: Data stream names to use

These values will be required to configure the environment variables of the Azure Function that will send data to Sentinel.

## Notes

- Custom tables have a 90-day retention period
- The Data Collection Endpoint is configured with public access enabled
- The watchlist already includes a sample configuration for Microsoft Exchange Online
- KQL transformations automatically add the `TimeGenerated` timestamp
