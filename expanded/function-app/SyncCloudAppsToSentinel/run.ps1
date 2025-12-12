<#
.SYNOPSIS
    Azure Function to sync Cloud App Discovery data from MDA to Sentinel
.DESCRIPTION
    Timer-triggered function that retrieves data from Microsoft Defender for Cloud Apps
    and uploads it directly to Microsoft Sentinel custom tables via Data Collection Rules.
    Runs every hour.
#>

using namespace System.Net

param($Timer)

# Get configuration from environment variables
$TenantId = $env:TENANT_ID
$ClientId = $env:CLIENT_ID
$ClientSecret = $env:CLIENT_SECRET
$StreamIds = ($env:MDA_STREAM_IDS -split ',').Trim()
$Period = $env:MDA_PERIOD ?? "P90D"
$DceEndpoint = $env:DCE_ENDPOINT
$DcrImmutableId = $env:DCR_IMMUTABLE_ID
$WorkspaceId = $env:WORKSPACE_ID
$SubscriptionId = $env:SUBSCRIPTION_ID
$ResourceGroupName = $env:RESOURCE_GROUP_NAME
$WorkspaceName = $env:WORKSPACE_NAME
$WatchlistAlias = $env:WATCHLIST_ALIAS ?? "CloudAppInfo"

$MaxBatchSizeBytes = 1MB
$MaxBatchRecords = 1000

# Stream names for Sentinel tables
$Streams = @{
    "CloudApps"        = "Custom-CloudApps"
    "CloudAppsInfo"    = "Custom-CloudAppsInfo"
    "CloudAppsUsers"   = "Custom-CloudAppsUsers"
}

Write-Host "=== Cloud App Discovery Sync Function Started ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

# Function to get Microsoft Graph access token
function Get-GraphAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    Write-Host "Obtaining Graph API access token..." -ForegroundColor Cyan
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Host "Graph API token obtained" -ForegroundColor Green
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain Graph token: $($_.Exception.Message)"
        throw
    }
}

# Function to get Monitor Ingestion access token
function Get-MonitorAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    Write-Host "Obtaining Monitor Ingestion API access token..." -ForegroundColor Cyan
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        scope         = "https://monitor.azure.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Host "Monitor API token obtained" -ForegroundColor Green
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain Monitor token: $($_.Exception.Message)"
        throw
    }
}

# Function to get Azure Management access token for Sentinel operations
function Get-AzureManagementToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    Write-Host "Obtaining Azure Management API access token..." -ForegroundColor Cyan
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        scope         = "https://management.azure.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Host "Azure Management API token obtained" -ForegroundColor Green
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain Azure Management token: $($_.Exception.Message)"
        throw
    }
}

# Function to get Log Analytics access token for KQL queries
function Get-LogAnalyticsToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    Write-Host "Obtaining Log Analytics API access token..." -ForegroundColor Cyan
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        scope         = "https://api.loganalytics.io/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Host "Log Analytics API token obtained" -ForegroundColor Green
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain Log Analytics token: $($_.Exception.Message)"
        throw
    }
}

# Function to invoke Graph API with retry logic
function Invoke-GraphBetaApi {
    param(
        [string]$Uri,
        [string]$AccessToken,
        [string]$Method = "GET",
        [int]$MaxRetries = 5,
        [switch]$HandlePagination
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $allResults = @()
    $currentUri = $Uri
    
    do {
        $retryCount = 0
        $baseDelay = 2
        $response = $null
        
        while ($retryCount -le $MaxRetries) {
            try {
                $response = Invoke-RestMethod -Uri $currentUri -Method $Method -Headers $headers
                break
            }
            catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
                
                if ($statusCode -eq 429 -and $retryCount -lt $MaxRetries) {
                    $retryCount++
                    $delay = [Math]::Pow($baseDelay, $retryCount)
                    
                    $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                    if ($retryAfter) {
                        $delay = [int]$retryAfter
                    }
                    
                    Write-Warning "Rate limited (429). Retry $retryCount/$MaxRetries after $delay seconds..."
                    Start-Sleep -Seconds $delay
                }
                else {
                    Write-Warning "Error during API call: $currentUri - $($_.Exception.Message)"
                    return $null
                }
            }
        }
        
        if ($null -eq $response) {
            Write-Warning "Max retries reached for: $currentUri"
            return $null
        }
        
        if ($HandlePagination) {
            if ($response.value) {
                $allResults += $response.value
            }
            $currentUri = $response.'@odata.nextLink'
        }
        else {
            return $response
        }
        
    } while ($currentUri)
    
    if ($HandlePagination) {
        return @{ value = $allResults }
    }
}

# Function to convert data to Sentinel format
function Convert-ToSentinelRecord {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )
    
    process {
        $record = @{}
        
        # Remove @odata properties
        foreach ($prop in $InputObject.PSObject.Properties) {
            if ($prop.Name -match '^@odata') {
                continue
            }
            
            $value = $prop.Value
            
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace($value)) {
                continue
            }
            
            # Handle arrays
            if ($value -is [System.Array]) {
                $record[$prop.Name] = $value -join ', '
            }
            # Handle booleans - Convert to lowercase string for Sentinel compatibility
            elseif ($value -is [bool]) {
                $record[$prop.Name] = $value.ToString().ToLower()
            }
            # Handle numbers
            elseif ($value -is [int] -or $value -is [long] -or $value -is [double]) {
                $record[$prop.Name] = $value
            }
            # Handle datetime
            elseif ($value -is [DateTime]) {
                $record[$prop.Name] = $value.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }
            # Handle strings
            else {
                $record[$prop.Name] = $value.ToString()
            }
        }
        
        return $record
    }
}

# Function to split records into batches
function Split-IntoBatches {
    param(
        [array]$Records,
        [int]$MaxRecords,
        [int]$MaxSizeBytes
    )
    
    $batches = @()
    $currentBatch = @()
    $currentSize = 0
    
    foreach ($record in $Records) {
        $recordJson = $record | ConvertTo-Json -Compress -Depth 10
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson)
        
        if (($currentBatch.Count -ge $MaxRecords) -or 
            (($currentSize + $recordSize) -gt $MaxSizeBytes -and $currentBatch.Count -gt 0)) {
            
            $batches += ,@($currentBatch)
            $currentBatch = @()
            $currentSize = 0
        }
        
        $currentBatch += $record
        $currentSize += $recordSize
    }
    
    if ($currentBatch.Count -gt 0) {
        $batches += ,@($currentBatch)
    }
    
    return $batches
}

# Function to upload batch to Sentinel
function Send-LogsBatch {
    param(
        [array]$Batch,
        [string]$AccessToken,
        [string]$DceEndpoint,
        [string]$DcrImmutableId,
        [string]$StreamName,
        [int]$MaxRetries = 5
    )
    
    $uri = "$DceEndpoint/dataCollectionRules/$DcrImmutableId/streams/$StreamName`?api-version=2023-01-01"
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    if ($Batch.Count -eq 1) {
        $body = "[$($Batch[0] | ConvertTo-Json -Depth 10 -Compress)]"
    }
    else {
        $body = $Batch | ConvertTo-Json -Depth 10 -Compress
    }
    
    $retryCount = 0
    $baseDelay = 2
    
    while ($retryCount -le $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
            return $true
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            if (($statusCode -eq 429 -or $statusCode -ge 500) -and $retryCount -lt $MaxRetries) {
                $retryCount++
                $delay = [Math]::Pow($baseDelay, $retryCount)
                
                $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                if ($retryAfter) {
                    $delay = [int]$retryAfter
                }
                
                Write-Warning "Upload failed (Status: $statusCode). Retry $retryCount/$MaxRetries after $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Error "Upload failed: $($_.Exception.Message)"
                return $false
            }
        }
    }
    
    Write-Error "Max retries reached for batch upload"
    return $false
}

# Function to query Log Analytics workspace
function Invoke-LogAnalyticsQuery {
    param(
        [string]$WorkspaceId,
        [string]$Query,
        [string]$AccessToken
    )
    
    $uri = "https://api.loganalytics.io/v1/workspaces/$WorkspaceId/query"
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $body = @{
        query = $Query
    } | ConvertTo-Json
    
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        return $response
    }
    catch {
        Write-Warning "Query failed: $($_.Exception.Message)"
        Write-Host "  Status Code: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
        Write-Host "  Error Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to check if app info exists in watchlist
function Test-AppInfoInWatchlist {
    param(
        [string]$AppId,
        [string]$WorkspaceId,
        [string]$WatchlistAlias,
        [string]$AccessToken
    )
    
    $query = "_GetWatchlist('$WatchlistAlias') | where id == '$AppId' | take 1"
    $result = Invoke-LogAnalyticsQuery -WorkspaceId $WorkspaceId -Query $query -AccessToken $AccessToken
    
    if ($null -eq $result -or $null -eq $result.tables -or $result.tables.Count -eq 0) {
        return $false
    }
    
    $rows = $result.tables[0].rows
    return ($null -ne $rows -and $rows.Count -gt 0)
}

# Function to add item to watchlist
function Add-WatchlistItem {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$WorkspaceName,
        [string]$WatchlistAlias,
        [object]$AppInfo,
        [string]$AccessToken,
        [int]$MaxRetries = 3
    )
    
    # Generate unique watchlist item ID
    $itemId = [guid]::NewGuid().ToString()
    
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/watchlists/$WatchlistAlias/watchlistItems/$itemId`?api-version=2023-02-01"
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    # Build itemsKeyValue from AppInfo
    $itemsKeyValue = @{}
    foreach ($prop in $AppInfo.PSObject.Properties) {
        if ($prop.Name -match '^@odata') {
            continue
        }
        
        $value = $prop.Value
        
        if ($null -eq $value) {
            $itemsKeyValue[$prop.Name] = ""
        }
        elseif ($value -is [bool]) {
            $itemsKeyValue[$prop.Name] = $value.ToString().ToLower()
        }
        elseif ($value -is [DateTime]) {
            $itemsKeyValue[$prop.Name] = $value.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        elseif ($value -is [System.Array]) {
            $itemsKeyValue[$prop.Name] = ($value -join ', ')
        }
        else {
            $itemsKeyValue[$prop.Name] = $value.ToString()
        }
    }
    
    $body = @{
        properties = @{
            itemsKeyValue = $itemsKeyValue
        }
    } | ConvertTo-Json -Depth 10
    
    $retryCount = 0
    while ($retryCount -le $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body
            return $true
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            if (($statusCode -eq 429 -or $statusCode -ge 500) -and $retryCount -lt $MaxRetries) {
                $retryCount++
                $delay = [Math]::Pow(2, $retryCount)
                Write-Warning "Watchlist item add failed (Status: $statusCode). Retry $retryCount/$MaxRetries after $delay seconds..."
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Warning "Failed to add item to watchlist: $($_.Exception.Message)"
                return $false
            }
        }
    }
    
    return $false
}

# Function to upload data to Sentinel
function Upload-ToSentinel {
    param(
        [array]$Records,
        [string]$StreamName,
        [string]$AccessToken,
        [string]$DceEndpoint,
        [string]$DcrImmutableId,
        [string]$DataType
    )
    
    if ($Records.Count -eq 0) {
        Write-Host "No $DataType records to upload" -ForegroundColor Yellow
        return @{ Success = 0; Failed = 0 }
    }
    
    Write-Host "Uploading $($Records.Count) $DataType records to stream: $StreamName" -ForegroundColor Cyan
    
    # Split into batches
    $batches = Split-IntoBatches -Records $Records -MaxRecords $MaxBatchRecords -MaxSizeBytes $MaxBatchSizeBytes
    Write-Host "  Split into $($batches.Count) batch(es)" -ForegroundColor Gray
    
    # Upload each batch
    $successCount = 0
    $failCount = 0
    
    for ($i = 0; $i -lt $batches.Count; $i++) {
        $batch = $batches[$i]
        Write-Host "  Uploading batch $($i + 1)/$($batches.Count) ($($batch.Count) records)..." -ForegroundColor Gray
        
        $success = Send-LogsBatch -Batch $batch -AccessToken $AccessToken -DceEndpoint $DceEndpoint `
            -DcrImmutableId $DcrImmutableId -StreamName $StreamName
        
        if ($success) {
            $successCount += $batch.Count
            Write-Host "    Batch $($i + 1) uploaded successfully" -ForegroundColor Green
        }
        else {
            $failCount += $batch.Count
            Write-Error "    Batch $($i + 1) failed"
        }
        
        if ($i -lt $batches.Count - 1) {
            Start-Sleep -Milliseconds 100
        }
    }
    
    Write-Host "  $DataType upload: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    
    return @{ Success = $successCount; Failed = $failCount }
}

# Main execution
try {
    # Validate configuration
    if ([string]::IsNullOrEmpty($TenantId) -or [string]::IsNullOrEmpty($ClientId) -or 
        [string]::IsNullOrEmpty($ClientSecret) -or [string]::IsNullOrEmpty($DceEndpoint) -or 
        [string]::IsNullOrEmpty($DcrImmutableId)) {
        throw "Missing required environment variables. Please check configuration."
    }
    
    if ([string]::IsNullOrEmpty($WorkspaceId) -or [string]::IsNullOrEmpty($SubscriptionId) -or
        [string]::IsNullOrEmpty($ResourceGroupName) -or [string]::IsNullOrEmpty($WorkspaceName)) {
        throw "Missing required watchlist configuration. Please check WORKSPACE_ID, SUBSCRIPTION_ID, RESOURCE_GROUP_NAME, and WORKSPACE_NAME."
    }
    
    # Get access tokens
    $graphToken = Get-GraphAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $monitorToken = Get-MonitorAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $azureToken = Get-AzureManagementToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $logAnalyticsToken = Get-LogAnalyticsToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    
    # Collections for all data
    $allApps = @()
    $allAppUsers = @()
    
    # Counters for watchlist operations
    $watchlistAdded = 0
    $watchlistSkipped = 0
    $watchlistFailed = 0
    
    # Process each Stream ID
    foreach ($streamId in $StreamIds) {
        Write-Host "`nProcessing Stream ID: $streamId" -ForegroundColor Yellow
        
        # Get aggregated apps
        $appsUri = "https://graph.microsoft.com/beta/security/dataDiscovery/cloudAppDiscovery/uploadedStreams/$streamId/microsoft.graph.security.aggregatedAppsDetails(period=duration'$Period')"
        Write-Host "  Retrieving aggregated apps..." -ForegroundColor Cyan
        
        $appsResponse = Invoke-GraphBetaApi -Uri $appsUri -AccessToken $graphToken -HandlePagination
        
        if ($null -eq $appsResponse -or $null -eq $appsResponse.value -or $appsResponse.value.Count -eq 0) {
            Write-Warning "  No apps found for this Stream ID"
            continue
        }

        $appCount = $appsResponse.value.Count
        Write-Host "  Found $appCount apps" -ForegroundColor Green
        
        # Process each app
        $counter = 0
        foreach ($app in $appsResponse.value) {
            $counter++
            Write-Host "    [$counter/$appCount] Processing: $($app.displayName)" -ForegroundColor Gray
            
            # Add stream reference
            $app | Add-Member -MemberType NoteProperty -Name "streamId" -Value $streamId -Force
            $allApps += $app
            
            # Get app info and add to watchlist if not already present
            $appInfoUri = "https://graph.microsoft.com/beta/security/dataDiscovery/cloudAppDiscovery/uploadedStreams/$streamId/microsoft.graph.security.aggregatedAppsDetails(period=duration'$Period')/$($app.id)/appInfo"
            $appInfoResponse = Invoke-GraphBetaApi -Uri $appInfoUri -AccessToken $graphToken
            
            if ($null -ne $appInfoResponse) {
                $appInfoResponse | Add-Member -MemberType NoteProperty -Name "streamId" -Value $streamId -Force
                $appInfoResponse | Add-Member -MemberType NoteProperty -Name "appId" -Value $app.id -Force
                $appInfoResponse | Add-Member -MemberType NoteProperty -Name "appDisplayName" -Value $app.displayName -Force
                
                # Check if already in watchlist
                Write-Host "      Checking watchlist for app: $($app.id)" -ForegroundColor Gray
                $existsInWatchlist = Test-AppInfoInWatchlist -AppId $appInfoResponse.id -WorkspaceId $WorkspaceId `
                    -WatchlistAlias $WatchlistAlias -AccessToken $logAnalyticsToken
                
                if ($existsInWatchlist) {
                    Write-Host "      App info already in watchlist, skipping" -ForegroundColor Yellow
                    $watchlistSkipped++
                }
                else {
                    Write-Host "      Adding app info to watchlist" -ForegroundColor Cyan
                    $success = Add-WatchlistItem -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
                        -WorkspaceName $WorkspaceName -WatchlistAlias $WatchlistAlias `
                        -AppInfo $appInfoResponse -AccessToken $azureToken
                    
                    if ($success) {
                        Write-Host "      Successfully added to watchlist" -ForegroundColor Green
                        $watchlistAdded++
                    }
                    else {
                        Write-Warning "      Failed to add to watchlist"
                        $watchlistFailed++
                    }
                }
            }
            
            # Get app users
            $appUsersUri = "https://graph.microsoft.com/beta/security/dataDiscovery/cloudAppDiscovery/uploadedStreams/$streamId/microsoft.graph.security.aggregatedAppsDetails(period=duration'$Period')/$($app.id)/users"
            $appUsersResponse = Invoke-GraphBetaApi -Uri $appUsersUri -AccessToken $graphToken -HandlePagination
            
            if ($null -ne $appUsersResponse -and $null -ne $appUsersResponse.value) {
                foreach ($user in $appUsersResponse.value) {
                    $user | Add-Member -MemberType NoteProperty -Name "streamId" -Value $streamId -Force
                    $user | Add-Member -MemberType NoteProperty -Name "appId" -Value $app.id -Force
                    $user | Add-Member -MemberType NoteProperty -Name "appDisplayName" -Value $app.displayName -Force
                    $allAppUsers += $user
                }
            }
            
            Start-Sleep -Milliseconds 50
        }
    }
    
    Write-Host "\n=== Data Collection Complete ===" -ForegroundColor Cyan
    Write-Host "Total Apps: $($allApps.Count)" -ForegroundColor Green
    Write-Host "Watchlist - Added: $watchlistAdded, Skipped: $watchlistSkipped, Failed: $watchlistFailed" -ForegroundColor $(if ($watchlistFailed -eq 0) { "Green" } else { "Yellow" })
    Write-Host "Total App Users: $($allAppUsers.Count)" -ForegroundColor Green
    
    # Convert and upload to Sentinel
    Write-Host "`n=== Uploading to Sentinel ===" -ForegroundColor Cyan
    
    $totalSuccess = 0
    $totalFailed = 0
    
    # Upload Apps
    if ($allApps.Count -gt 0) {
        $appsRecords = $allApps | ForEach-Object { Convert-ToSentinelRecord $_ }
        $result = Upload-ToSentinel -Records $appsRecords -StreamName $Streams["CloudApps"] `
            -AccessToken $monitorToken -DceEndpoint $DceEndpoint -DcrImmutableId $DcrImmutableId -DataType "Apps"
        $totalSuccess += $result.Success
        $totalFailed += $result.Failed
    }
    
    # App Info is now managed via Watchlist (see watchlist counters above)
    
    # Upload App Users
    if ($allAppUsers.Count -gt 0) {
        $appUsersRecords = $allAppUsers | ForEach-Object { Convert-ToSentinelRecord $_ }
        $result = Upload-ToSentinel -Records $appUsersRecords -StreamName $Streams["CloudAppsUsers"] `
            -AccessToken $monitorToken -DceEndpoint $DceEndpoint -DcrImmutableId $DcrImmutableId -DataType "AppUsers"
        $totalSuccess += $result.Success
        $totalFailed += $result.Failed
    }
    
    Write-Host "`n=== Sync Complete ===" -ForegroundColor Green
    Write-Host "Total records uploaded: $totalSuccess" -ForegroundColor Green
    Write-Host "Total records failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
    Write-Host "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
}
catch {
    Write-Error "Function execution failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    throw
}
finally {
    # Clear sensitive data
    $graphToken = $null
    $monitorToken = $null
    $azureToken = $null
    $logAnalyticsToken = $null
    $ClientSecret = $null
}
