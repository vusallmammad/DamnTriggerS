# Azure Functions profile.ps1
try {
    Connect-AzAccount -Identity -ErrorAction SilentlyContinue
    Write-Information "Successfully connected to Azure using Managed Identity"
} catch {
    Write-Error "Failed to connect to Azure: $_"
}