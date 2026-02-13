using namespace System.Net

# HTTP trigger function that receives form data and triggers the runbook
param($Request, $TriggerMetadata)

Write-Host "Country Change Request received"
Write-Host "Request Body: $($Request.Body | ConvertTo-Json)"

# Parse the incoming request
$userPrincipalName = $Request.Body.UserPrincipalName
$country = $Request.Body.Country

# Validate inputs
if (-not $userPrincipalName -or -not $country) {
    $statusCode = [HttpStatusCode]::BadRequest
    $body = @{
        message = "Missing required parameters: UserPrincipalName and Country"
        success = $false
    } | ConvertTo-Json
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Body       = $body
    })
    return
}

try {
    # Get function app environment variables
    $resourceGroupName = $env:RESOURCE_GROUP_NAME
    $automationAccountName = $env:AUTOMATION_ACCOUNT_NAME
    $runbookName = $env:RUNBOOK_NAME
    
    if (-not $resourceGroupName -or -not $automationAccountName -or -not $runbookName) {
        throw "Missing environment variables: RESOURCE_GROUP_NAME, AUTOMATION_ACCOUNT_NAME, or RUNBOOK_NAME"
    }

    Write-Host "Triggering runbook: $runbookName in $automationAccountName"
    
    # Start the runbook with parameters
    $runbookParams = @{
        UserPrincipalName = $userPrincipalName
        Country = $country
    }
    
    $runbookJob = Start-AzAutomationRunbook -ResourceGroupName $resourceGroupName `
                                            -AutomationAccountName $automationAccountName `
                                            -Name $runbookName `
                                            -Parameters $runbookParams
    
    $statusCode = [HttpStatusCode]::OK
    $body = @{
        message = "Runbook triggered successfully"
        success = $true
        jobId = $runbookJob.JobId
        userPrincipalName = $userPrincipalName
        country = $country
    } | ConvertTo-Json
    
    Write-Host "Runbook job created with ID: $($runbookJob.JobId)"
}
catch {
    Write-Error "Error triggering runbook: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
    $body = @{
        message = "Error processing request: $_"
        success = $false
    } | ConvertTo-Json
}

# Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = $body
})