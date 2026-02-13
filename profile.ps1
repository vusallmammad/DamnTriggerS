# Azure Functions profile.ps1
#
# This profile.ps1 file is loaded every time a PowerShell worker process is started.
# Please log any errors and information to the OUT stream.

# Authenticate to Azure
# This runs once when the function app starts
try {
    # Using Managed Identity - recommended for Azure Functions
    Connect-AzAccount -Identity -ErrorAction SilentlyContinue
    Write-Information "Successfully connected to Azure using Managed Identity"
} catch {
    Write-Error "Failed to connect to Azure: $_"
}