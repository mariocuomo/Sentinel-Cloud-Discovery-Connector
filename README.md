# Sentinel Cloud Discovery Connector

## Overview

This solution provides a custom Sentinel Codeless Connector Framework (CCF) data connector that enables ingestion of Cloud Discovery data from Microsoft Defender for Cloud Apps into Microsoft Sentinel. The connector leverages the Microsoft Graph API (beta) to retrieve cloud app usage data and streams it into a custom Log Analytics table.

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/connectorpage.png"> </img>
</div>

## Features

- **Automated Data Ingestion**: Continuously pulls Cloud Discovery data from Defender for Cloud Apps
- **OAuth 2.0 Authentication**: Secure authentication using Enterprise App credentials
- **Customizable Lookback Period**: Support for 7, 30, or 90-day data ingestion windows
- **Custom Log Analytics Table**: Data is stored in the `CloudDiscoveryData_CL` table

## Data Schema

The connector ingests the following data fields into the `CloudDiscoveryData_CL` table:

<div align="center">


| Field Name | Type | Description |
|------------|------|-------------|
| TimeGenerated | datetime | Timestamp when the record was generated |
| id | string | Unique identifier for the cloud app |
| displayName | string | Display name of the cloud application |
| tags | dynamic | Associated tags for the application |
| riskScore | int | Risk score assigned to the application |
| lastSeenDateTime | datetime | Last time the application was observed |
| domains | dynamic | Domains associated with the application |
| category | string | Application category |
| userCount | int | Number of users accessing the application |
| ipAddressCount | int | Number of unique IP addresses |
| transactionCount | int | Total number of transactions |
| uploadNetworkTrafficInBytes | long | Upload traffic volume in bytes |
| downloadNetworkTrafficInBytes | long | Download traffic volume in bytes |
| deviceCount | int | Number of devices accessing the application |

<img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/tableschema.png"> </img>

</div>


## Prerequisites

### 1. Enterprise Application in Entra ID

Create an Enterprise Application (App Registration) in Microsoft Entra ID with the following configuration:

- **Required API Permission**: `CloudApp-Discovery.Read.All` (Application permission type)
- **Grant Admin Consent**: Required for the application to access Cloud Discovery data

Follow the [Microsoft Documentation](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/add-application-portal) for detailed guidance on creating an Enterprise App.

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/apipermission.png"> </img>
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/secret.png"> </img>
</div>

### 2. Microsoft Sentinel Workspace

- An active Microsoft Sentinel workspace
- Workspace contributor permissions to deploy the connector

### 3. Cloud Discovery Stream ID

Obtain the Stream ID from the Microsoft Defender for Cloud Apps portal:
1. Navigate to the Cloud Discovery report
2. Select a data source from the top-right dropdown
3. Copy the Stream ID from the URL

## Current Limitations

⚠️ **Single Stream Connection**: The current version of the connector supports connection to only one Cloud Discovery stream at a time. The primary use case is for the **Defender for Endpoint** stream.

## API Information

- **Endpoint**: Microsoft Graph API (Beta)
- **API Version**: Beta
- **Authentication**: OAuth 2.0 with client credentials flow
- **Rate Limiting**: 1 query per second (configured in the connector)

## Installation

### Deploy the Solution

1. Deploy the ARM template (`MainTemplate.json`) to your Azure subscription:
   - Navigate to your resource group in the Azure Portal
   - Click **Create** > **Template deployment (deploy using custom templates)**
   - Upload the `MainTemplate.json` file
   - Fill in the required parameters:
     - Workspace name
     - Workspace location
     - Resource group name
     - Subscription ID

2. After deployment, navigate to Microsoft Sentinel > Data connectors

3. Search for "MDA Cloud Discovery" and open the connector page

### Configure the Connector

1. **Step 1**: Ensure you have created the Enterprise App with the required API permissions

2. **Step 2**: Enter the Stream ID and select the lookback period:
   - Stream ID: The ID obtained from Defender for Cloud Apps
   - Lookback period: Choose 7, 30, or 90 days

3. **Step 3**: Enter your Enterprise App credentials:
   - Client ID
   - Client Secret
   - Click **Connect**

## Data Collection

The connector polls the Microsoft Graph API every 5 minutes to retrieve new Cloud Discovery data. The query window is configurable and supports the following lookback periods:

- 7 days
- 30 days
- 90 days

Data is ingested into the `CloudDiscoveryData_CL` table and is immediately available for querying in Microsoft Sentinel.

## Sample Queries

### Get the latest 10 Cloud Discovery events
```kql
CloudDiscoveryData_CL
| take 10
```

### View applications by risk score
```kql
CloudDiscoveryData_CL
| where TimeGenerated > ago(7d)
| summarize LastSeen = max(lastSeenDateTime) by displayName, riskScore
| sort by riskScore desc
```

### Analyze traffic by application
```kql
CloudDiscoveryData_CL
| where TimeGenerated > ago(7d)
| summarize 
    TotalUploadMB = sum(uploadNetworkTrafficInBytes) / 1024 / 1024,
    TotalDownloadMB = sum(downloadNetworkTrafficInBytes) / 1024 / 1024,
    Users = max(userCount)
    by displayName
| sort by TotalDownloadMB desc
```

### Monitor high-risk applications
```kql
CloudDiscoveryData_CL
| where TimeGenerated > ago(7d)
| where riskScore >= 7
| summarize Users = max(userCount), Devices = max(deviceCount) by displayName, riskScore, category
| sort by riskScore desc, Users desc
```

## Troubleshooting
### No data appearing in the table
1. Verify the Enterprise App has the correct API permissions and admin consent is granted
2. Check that the Stream ID is correct
3. Verify the Client ID and Client Secret are valid
4. Review the Data Connector status in Microsoft Sentinel

### Authentication errors
1. Ensure the Client Secret has not expired
2. Verify the application has CloudApp-Discovery.Read.All permission
3. Confirm admin consent has been granted for the API permission

## Support & Version Information & License
- Author: Mario Cuomo
- Status: Production
- This solution is provided as-is under the terms specified in the solution package.
Codeless Connector Framework Documentation
Microsoft Defender for Cloud Apps
