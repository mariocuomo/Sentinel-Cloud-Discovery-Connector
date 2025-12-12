<#
.SYNOPSIS
    Automated deployment wrapper script using config.ps1
.DESCRIPTION
    Executes Deploy-All.ps1 using parameters from config.ps1
.EXAMPLE
    .\Deploy.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Check if configuration file exists
$configFile = Join-Path $PSScriptRoot "config.ps1"

if (-not (Test-Path $configFile)) {
    Write-Host "File 'config.ps1' not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "INITIAL SETUP:" -ForegroundColor Yellow
    Write-Host "1. Copy 'config.example.ps1' to 'config.ps1'" -ForegroundColor White
    Write-Host "2. Edit 'config.ps1' with your parameters" -ForegroundColor White
    Write-Host "3. Run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "Quick command:" -ForegroundColor Cyan
    Write-Host "  Copy-Item config.example.ps1 config.ps1" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Load configuration
Write-Host "Loading configuration from config.ps1..." -ForegroundColor Cyan
. $configFile

# Verify required parameters
$requiredParams = @('ResourceGroupName', 'WorkspaceName', 'WorkspaceId', 'TenantId', 'ClientId', 'ClientSecret', 'MdaStreamIds')
$missingParams = @()

foreach ($param in $requiredParams) {
    if (-not (Get-Variable -Name $param -ErrorAction SilentlyContinue).Value) {
        $missingParams += $param
    }
}

if ($missingParams.Count -gt 0) {
    Write-Host "Required parameters missing in config.ps1:" -ForegroundColor Red
    $missingParams | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 1
}

# Build parameters for Deploy-All.ps1
$deployParams = @{
    ResourceGroupName = $ResourceGroupName
    WorkspaceName = $WorkspaceName
    WorkspaceId = $WorkspaceId
    TenantId = $TenantId
    ClientId = $ClientId
    ClientSecret = $ClientSecret
    MdaStreamIds = $MdaStreamIds
}

# Add optional parameters if present
if ($Location) { $deployParams['Location'] = $Location }
if ($MdaPeriod) { $deployParams['MdaPeriod'] = $MdaPeriod }
if ($TimerSchedule) { $deployParams['TimerSchedule'] = $TimerSchedule }
if ($FunctionAppName) { $deployParams['FunctionAppName'] = $FunctionAppName }

# Show summary
Write-Host ""
Write-Host "STARTING DEPLOYMENT" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green
Write-Host "Resource Group:  $ResourceGroupName" -ForegroundColor White
Write-Host "Location:        $Location" -ForegroundColor White
Write-Host "Workspace:       $WorkspaceName" -ForegroundColor White
Write-Host "Workspace ID:    $WorkspaceId" -ForegroundColor White
Write-Host "MDA Streams:     $MdaStreamIds" -ForegroundColor White
Write-Host ""

# Confirm
$confirmation = Read-Host "Proceed with deployment? (Y/N)"
if ($confirmation -ne 'S' -and $confirmation -ne 's' -and $confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Deployment cancelled" -ForegroundColor Yellow
    exit 0
}

# Execute deployment
$deployScript = Join-Path $PSScriptRoot "Deploy-All.ps1"
& $deployScript @deployParams
