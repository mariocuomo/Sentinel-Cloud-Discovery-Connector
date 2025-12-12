# ========================================
# Cloud App Discovery - Deployment Configuration
# ========================================
# Copy this file to 'config.ps1' and customize it with your values

# Azure Configuration
$ResourceGroupName = "<TO-INSERT>"
$Location = "<TO-INSERT>"
$WorkspaceName = "<TO-INSERT>"
$WorkspaceId = "<TO-INSERT>"

# Service Principal (Entra ID app)
# Requires: CloudApp-Discovery.Read.All permission
$TenantId = "<TO-INSERT>"
$ClientId = "<TO-INSERT>"
$ClientSecret = "<TO-INSERT>"

# Microsoft Defender for Cloud Apps (MDA)
$MdaStreamIds = "<TO-INSERT>"  # Comma-separated if multiple
$MdaPeriod = "P90D"  # P7D = 7 days, P30D = 30 days, P90D = 90 days

# Function App Schedule
$TimerSchedule = "0 */5 * * * *"  # CRON: every 5 minutes
# Other examples:
# "0 */6 * * * *"   = every 6 hours
# "0 0 */12 * * *" = every 12 hours
# "0 0 0 * * *"    = daily at midnight

# Custom Function App name (optional)
# If empty, will be auto-generated
$FunctionAppName = "func-cloudappsync"
