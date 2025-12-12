# ========================================
# Cloud App Discovery - Deployment Configuration
# ========================================
# Copy this file to 'config.ps1' and customize it with your values

# Azure Configuration
$ResourceGroupName = "<YOUR-INFO>"
$Location = "<YOUR-INFO>"
$WorkspaceName = "<YOUR-INFO>"
$WorkspaceId = "<YOUR-INFO>"

# Service Principal (Entra ID App Registration)
# Requires: CloudApp-Discovery.Read.All permission
$TenantId = "<YOUR-INFO>"
$ClientId = "<YOUR-INFO>"
$ClientSecret = "<YOUR-INFO>v"

# Microsoft Defender for Cloud Apps (MDA)
$MdaStreamIds = "<YOUR-INFO>, <YOUR-INFO>"  # Comma-separated if multiple
$MdaPeriod = "P90D"  # P7D = 7 days, P30D = 30 days, P90D = 90 days

# Function App Schedule
$TimerSchedule = "0 */5 * * * *"  # CRON: every hour (0 min, 0 hour, every day)
# Other examples:
# "0 */6 * * * *"   = every 6 hours
# "0 0 */12 * * *" = every 12 hours
# "0 0 0 * * *"    = daily at midnight

# Custom Function App name (optional)
# If empty, will be auto-generated
$FunctionAppName = "func-cloudappsync"
