<#
.SYNOPSIS
    Automated deployment script for Cloud App Discovery Connector
.DESCRIPTION
    This script automates the entire deployment process:
    1. Deploy Sentinel infrastructure (DCE, DCR, Tables, Watchlist)
    2. Automatic extraction of outputs (DCE endpoint, DCR ID, Workspace ID)
    3. Deploy Azure Function App with automatically updated parameters
    4. Deploy Function App code
.PARAMETER ResourceGroupName
    Name of the resource group where resources will be deployed
.PARAMETER Location
    Azure region (default: westeurope)
.PARAMETER WorkspaceName
    Name of the Log Analytics/Sentinel workspace
.PARAMETER WorkspaceId
    Log Analytics Workspace ID (GUID)
.PARAMETER TenantId
    Azure AD Tenant ID
.PARAMETER ClientId
    Service Principal Client ID
.PARAMETER ClientSecret
    Service Principal Client Secret
.PARAMETER MdaStreamIds
    Comma-separated list of MDA Stream IDs (e.g., "id1,id2")
.PARAMETER MdaPeriod
    MDA aggregation period (default: P7D)
.PARAMETER TimerSchedule
    CRON expression for timer (default: "0 0 * * * *" = every hour)
.PARAMETER FunctionAppName
    Custom name for the Function App (optional)
.EXAMPLE
    .\Deploy-All.ps1 -ResourceGroupName "rg-cloudappdiscovery" -WorkspaceName "APT29LAW" -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz" -MdaStreamIds "66fbba6eea91c6fe8fc1b84b"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "westeurope",

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$MdaStreamIds,

    [Parameter(Mandatory = $false)]
    [string]$MdaPeriod = "P7D",

    [Parameter(Mandatory = $false)]
    [string]$TimerSchedule = "0 0 * * * *",

    [Parameter(Mandatory = $false)]
    [string]$FunctionAppName = ""
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host " $Message" -ForegroundColor Cyan
    Write-Host "===================================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Verify we're in the correct folder
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$functionAppPath = Join-Path $scriptPath "function-app"

if (-not (Test-Path $functionAppPath)) {
    Write-ErrorMsg "Folder 'function-app' not found. Make sure to run the script from the project root."
    exit 1
}

# Verify that Azure CLI is installed
try {
    $null = az --version
}
catch {
    Write-ErrorMsg "Azure CLI not found. Install Azure CLI from: https://aka.ms/installazurecliwindows"
    exit 1
}

# Login check
Write-Step "VERIFY AZURE LOGIN"
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Info "Logging in to Azure..."
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Success "Logged in as: $($account.user.name)"
Write-Info "Subscription: $($account.name) ($($account.id))"

# Verify/Create Resource Group
Write-Step "VERIFY RESOURCE GROUP"
$rg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
if (-not $rg) {
    Write-Info "Resource group '$ResourceGroupName' non esiste. Lo creo..."
    $rg = az group create --name $ResourceGroupName --location $Location | ConvertFrom-Json
    Write-Success "Resource group creato"
} else {
    Write-Success "Resource group '$ResourceGroupName' già esistente"
}

# ==========================================
# STEP 1: DEPLOY SENTINEL INFRASTRUCTURE
# ==========================================
Write-Step "STEP 1: DEPLOY SENTINEL INFRASTRUCTURE"
Write-Info "Deploying DCE, DCR, Custom Tables and Watchlist..."

$sentinelTemplatePath = Join-Path $functionAppPath "sentinel-config.json"
$deploymentName = "sentinel-infra-$(Get-Date -Format 'yyyyMMddHHmmss')"

try {
    $sentinelDeployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $sentinelTemplatePath `
        --parameters workspaceName="$WorkspaceName" location="$Location" `
        --name $deploymentName `
        --output json | ConvertFrom-Json

    Write-Success "Sentinel infrastructure deployed successfully"
} catch {
    Write-ErrorMsg "Error during Sentinel deployment: $_"
    exit 1
}

# Extract outputs
Write-Info "Extracting parameters from Sentinel deployment..."

$dceEndpoint = $sentinelDeployment.properties.outputs.dceEndpoint.value
$dcrImmutableId = $sentinelDeployment.properties.outputs.dcrImmutableId.value
$cloudAppsTableName = $sentinelDeployment.properties.outputs.cloudAppsTableName.value
$cloudAppsUsersTableName = $sentinelDeployment.properties.outputs.cloudAppsUsersTableName.value
$watchlistAlias = $sentinelDeployment.properties.outputs.watchlistAlias.value

Write-Success "Parameters extracted successfully:"
Write-Host "- DCE Endpoint: $dceEndpoint" -ForegroundColor White
Write-Host "- DCR Immutable ID: $dcrImmutableId" -ForegroundColor White
Write-Host "- Workspace ID: $WorkspaceId (from config)" -ForegroundColor White
Write-Host "- CloudApps Table: $cloudAppsTableName" -ForegroundColor White
Write-Host "- CloudAppsUsers Table: $cloudAppsUsersTableName" -ForegroundColor White
Write-Host "- Watchlist Alias: $watchlistAlias" -ForegroundColor White

# ==========================================
# ASSIGN RBAC ROLES TO SERVICE PRINCIPAL
# ==========================================
Write-Step "ASSIGNING RBAC ROLES"
Write-Info "Assigning required roles to Service Principal..."

# Get DCR Resource ID
$dcrResourceId = az monitor data-collection rule show `
    --name "dcr-cloudappdiscovery" `
    --resource-group $ResourceGroupName `
    --subscription $($account.id) `
    --query id `
    --output tsv

# Get Workspace Resource ID
$workspaceResourceId = az monitor log-analytics workspace show `
    --workspace-name $WorkspaceName `
    --resource-group $ResourceGroupName `
    --subscription $($account.id) `
    --query id `
    --output tsv

Write-Info "DCR Resource ID: $dcrResourceId"
Write-Info "Workspace Resource ID: $workspaceResourceId"

# Assign "Monitoring Metrics Publisher" role on DCR
Write-Info "Assigning 'Monitoring Metrics Publisher' role on DCR..."
try {
    $null = az role assignment create `
        --assignee $ClientId `
        --role "Monitoring Metrics Publisher" `
        --scope $dcrResourceId `
        --subscription $($account.id) `
        --output none 2>&1
    Write-Success "Role 'Monitoring Metrics Publisher' assigned on DCR"
} catch {
    Write-ErrorMsg "Warning: Could not assign Monitoring Metrics Publisher role: $_"
    Write-Info "You may need to assign this role manually in Azure Portal"
}

# Assign "Microsoft Sentinel Contributor" role on Log Analytics Workspace
Write-Info "Assigning 'Microsoft Sentinel Contributor' role on workspace..."
try {
    $null = az role assignment create `
        --assignee $ClientId `
        --role "Microsoft Sentinel Contributor" `
        --scope $workspaceResourceId `
        --subscription $($account.id) `
        --output none 2>&1
    Write-Success "Role 'Microsoft Sentinel Contributor' assigned on workspace"
} catch {
    Write-ErrorMsg "Warning: Could not assign Sentinel Contributor role: $_"
    Write-Info "You may need to assign this role manually in Azure Portal"
}

Write-Success "RBAC role assignments completed"

# ==========================================
# STEP 2: DEPLOY AZURE FUNCTION APP
# ==========================================
Write-Step "STEP 2: DEPLOY AZURE FUNCTION APP"

$functionTemplatePath = Join-Path $functionAppPath "azuredeploy.json"
$deploymentName = "function-app-$(Get-Date -Format 'yyyyMMddHHmmss')"

# Parameters for deployment
$parameters = @{
    tenantId = $TenantId
    clientId = $ClientId
    clientSecret = $ClientSecret
    mdaStreamIds = $MdaStreamIds
    mdaPeriod = $MdaPeriod
    dceEndpoint = $dceEndpoint
    dcrImmutableId = $dcrImmutableId
    workspaceId = $WorkspaceId
    workspaceName = $WorkspaceName
    watchlistAlias = $watchlistAlias
    timerSchedule = $TimerSchedule
    location = $Location
}

if ($FunctionAppName) {
    $parameters['functionAppName'] = $FunctionAppName
}

Write-Info "Deploying Function App with updated parameters..."

# Create parameter arguments array for Azure CLI
$paramArgs = @()
foreach ($key in $parameters.Keys) {
    $value = $parameters[$key]
    if ($key -eq 'clientSecret') {
        $paramArgs += "$key=`"$value`""
    } else {
        $paramArgs += "$key=$value"
    }
}

try {
    $functionDeployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $functionTemplatePath `
        --parameters @paramArgs `
        --name $deploymentName `
        --output json | ConvertFrom-Json

    Write-Success "Function App deployed successfully"
    
    $deployedFunctionAppName = $functionDeployment.properties.outputs.functionAppName.value
    $storageAccountName = $functionDeployment.properties.outputs.storageAccountName.value
    
    Write-Success "Created resources:"
    Write-Host "- Function App: $deployedFunctionAppName" -ForegroundColor White
    Write-Host "- Storage Account: $storageAccountName" -ForegroundColor White

} catch {
    Write-ErrorMsg "Error during Function App deployment: $_"
    exit 1
}

# ==========================================
# STEP 3: DEPLOY FUNCTION APP CODE
# ==========================================
Write-Step "STEP 3: DEPLOY FUNCTION APP CODE"

Write-Info "Preparing code for deployment..."

# Verify that func CLI is installed
try {
    $null = func --version
    Write-Success "Azure Functions Core Tools found"
} catch {
    Write-ErrorMsg "Azure Functions Core Tools not found."
    Write-Info "Install with: npm install -g azure-functions-core-tools@4"
    Write-Info "Or download from: https://aka.ms/func-cli"
    exit 1
}

# Deploy code
Write-Info "Deploying Function App code..."
Push-Location $functionAppPath

try {
    Write-Info "Running: func azure functionapp publish $deployedFunctionAppName --powershell"
    func azure functionapp publish $deployedFunctionAppName --powershell
    Write-Success "Code deployed successfully"
} catch {
    Write-ErrorMsg "Error during code deployment: $_"
    Pop-Location
    exit 1
} finally {
    Pop-Location
}

# ==========================================
# COMPLETION
# ==========================================
Write-Step "DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"

Write-Host @"

DEPLOYMENT SUMMARY
==================

Resource Group:     $ResourceGroupName
Location:           $Location

SENTINEL:
  Workspace:        $WorkspaceName
  Workspace ID:     $WorkspaceId
  DCE Endpoint:     $dceEndpoint
  DCR ID:           $dcrImmutableId
  Custom Tables:    $cloudAppsTableName, $cloudAppsUsersTableName
  Watchlist:        $watchlistAlias

FUNCTION APP:
  Name:             $deployedFunctionAppName
  Storage:          $storageAccountName
  Timer:            $TimerSchedule
  MDA Streams:      $MdaStreamIds
  MDA Period:       $MdaPeriod

RBAC ROLES ASSIGNED:
  - Monitoring Metrics Publisher (on DCR)
  - Microsoft Sentinel Contributor (on workspace)

NEXT STEPS:
1. Verify that the Service Principal has Microsoft Graph API permission:
   - CloudApp-Discovery.Read.All (Application permission)
   - Grant admin consent in Azure Portal

2. Test the Function manually in the Azure Portal

3. Monitor logs in Application Insights

4. Verify data in Sentinel:
   - Tables: $cloudAppsTableName, $cloudAppsUsersTableName
   - Watchlist: $watchlistAlias

"@ -ForegroundColor Green

Write-Success "All done!"
