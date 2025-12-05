# Sentinel Cloud Discovery Connector v2

## Overview

This solution provides a custom Sentinel Codeless Connector Framework (CCF) data connector that enables ingestion of Cloud Discovery data from Microsoft Defender for Cloud Apps into Microsoft Sentinel. The connector leverages the Microsoft Graph API (beta) to retrieve cloud app usage data and streams it into a custom Log Analytics table.

**🆕 What's New in v2**: Multi-stream support allows you to connect to multiple Cloud Discovery streams simultaneously, enabling comprehensive visibility across different data sources (Defender for Endpoint, log collectors, etc.).

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/v2/connectorpage.png"> </img>
</div>

## Features

- **✨ Multi-Stream Support**: Connect to multiple Cloud Discovery streams simultaneously (NEW in v2)
- **Automated Data Ingestion**: Continuously pulls Cloud Discovery data from Defender for Cloud Apps
- **OAuth 2.0 Authentication**: Secure authentication using Enterprise App credentials
- **Customizable Lookback Period**: Support for 7, 30, or 90-day data ingestion windows per stream
- **Custom Log Analytics Table**: Data is stored in the `CloudDiscoveryData_CL` table
- **Stream Management**: Add, monitor, and delete individual stream connections from a centralized view

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
</div>

<br>

Generate a secret to be used later in the connector configuration.

<br>

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/secret.png"> </img>
</div>

### 2. Microsoft Sentinel Workspace

- An active Microsoft Sentinel workspace
- Workspace contributor permissions to deploy the connector

### 3. Cloud Discovery Stream IDs

Obtain the Stream IDs from the Microsoft Defender for Cloud Apps portal for each data source you want to connect:
1. Navigate to the Cloud Discovery report
2. Select a data source from the top-right dropdown
3. Copy the Stream ID from the URL
4. Repeat for additional streams (e.g., Defender for Endpoint, log collectors, etc.)

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/streamid.png"> </img>
</div>

## Multi-Stream Architecture

Version 2 of the connector introduces the ability to manage multiple Cloud Discovery streams:

- **Independent Stream Configuration**: Each stream has its own authentication credentials, Stream ID, and lookback period
- **Centralized Management**: All connected streams are visible in the Data Connectors Grid
- **Flexible Data Sources**: Connect to Defender for Endpoint, log collectors, or any other Cloud Discovery data source
- **Individual Stream Control**: Add or remove streams independently without affecting other connections

## API Information

- **Endpoint**: Microsoft Graph API (Beta)
- **API Version**: Beta
- **Authentication**: OAuth 2.0 with client credentials flow
- **Rate Limiting**: 1 query per second per stream (configured in the connector)
- **Query Window**: 5 minutes (configurable per stream)

## Installation

### Deploy the Solution

1. Deploy the ARM template [MainTemplate.json](https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/v2/MainTemplate.json) to your Azure subscription:
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

#### Adding Streams

1. **Step 1**: Ensure you have created the Enterprise App with the required API permissions

2. **Step 2**: Click **Add stream** button in the connector page

3. **Step 3**: Fill in the stream configuration form:
   - **Client ID**: Your Enterprise App's Client ID
   - **Client Secret**: Your Enterprise App's Client Secret
   - **Stream ID**: The Stream ID from Defender for Cloud Apps
   - **Lookback Period**: Select 7, 30, or 90 days

4. **Step 4**: Click **Connect** to activate the stream

5. **Repeat**: To add additional streams, click **Add stream** again and repeat the process with different Stream IDs

<div align="center">
  <img src="https://github.com/mariocuomo/Sentinel-Cloud-Discovery-Connector/blob/main/img/v2/stream.png"> </img>
</div>

## Data Collection

The connector polls the Microsoft Graph API every 5 minutes for each configured stream to retrieve new Cloud Discovery data. Each stream operates independently:

- **Query Frequency**: Every 5 minutes per stream
- **Lookback Period**: Configurable per stream (7, 30, or 90 days)
- **Data Destination**: All streams write to the same `CloudDiscoveryData_CL` table
- **Stream Identification**: Use the Stream ID to differentiate data sources in queries

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

### Compare data across multiple streams (v2 feature)
```kql
CloudDiscoveryData_CL
| where TimeGenerated > ago(24h)
| summarize 
    UniqueApps = dcount(displayName),
    TotalUsers = sum(userCount),
    TotalDevices = sum(deviceCount),
    TotalTrafficGB = (sum(uploadNetworkTrafficInBytes) + sum(downloadNetworkTrafficInBytes)) / 1024 / 1024 / 1024
| project UniqueApps, TotalUsers, TotalDevices, TotalTrafficGB
```

## Migration from v1 to v2

If you are upgrading from v1 to v2:

1. **Backup Current Configuration**: Note your existing Stream ID and credentials
2. **Deploy v2 Template**: Follow the installation steps above
3. **Reconfigure Streams**: Add your streams using the new multi-stream interface
4. **Verify Data Flow**: Ensure data is being ingested correctly
5. **Optional**: Add additional streams to expand your visibility

**Note**: The table schema remains unchanged between v1 and v2, ensuring compatibility with existing queries and workbooks.

## Troubleshooting

### No data appearing in the table
1. Verify the Enterprise App has the correct API permissions and admin consent is granted
2. Check that each Stream ID is correct
3. Verify the Client ID and Client Secret are valid for each stream
4. Review the Data Connector status in Microsoft Sentinel
5. Check the Data Connectors Grid for individual stream health

### Authentication errors
1. Ensure the Client Secret has not expired
2. Verify the application has CloudApp-Discovery.Read.All permission
3. Confirm admin consent has been granted for the API permission
4. Check if the credentials are correctly entered for each stream

### Stream-specific issues
1. Verify the Stream ID exists in Defender for Cloud Apps
2. Ensure the stream has data available for the selected lookback period
3. Check if the stream is actively receiving data in Defender for Cloud Apps portal
4. Review Azure Monitor logs for Data Collection Rule execution status

### Performance considerations
- Each stream creates an independent polling process
- Consider rate limiting when connecting multiple streams
- Monitor Data Collection Endpoint and Data Collection Rule metrics
- Adjust query windows if data volume is high

## Support & Version Information & License

- **Author**: Mario Cuomo
- **Version**: 2.0.0
- **Status**: Evaluation
- **License**: This solution is provided as-is under the terms specified in the solution package


