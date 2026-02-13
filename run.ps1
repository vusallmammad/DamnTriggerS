using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "Country Change Request received"

$userPrincipalName = $Request.Body.UserPrincipalName
$country = $Request.Body.Country

if (-not $userPrincipalName -or -not $country) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = @{ message = "Missing parameters"; success = $false } | ConvertTo-Json
    })
    return
}

try {
    $resourceGroupName = $env:RESOURCE_GROUP_NAME
    $automationAccountName = $env:AUTOMATION_ACCOUNT_NAME
    $runbookName = $env:RUNBOOK_NAME
    $hybridWorkerGroupName = $env:HYBRID_WORKER_GROUP_NAME
    
    Write-Host "Triggering runbook: $runbookName"
    
    $runbookParams = @{
        UserPrincipalName = $userPrincipalName
        Country = $country
    }
    
    $runbookJob = Start-AzAutomationRunbook -ResourceGroupName $resourceGroupName `
                                            -AutomationAccountName $automationAccountName `
                                            -Name $runbookName `
                                            -Parameters $runbookParams `
                                            -RunOn $hybridWorkerGroupName
    
    Write-Host "Runbook job created: $($runbookJob.JobId)"
    
    $statusCode = [HttpStatusCode]::OK
    $body = @{
        message = "Country update initiated"
        success = $true
        jobId = $runbookJob.JobId
    } | ConvertTo-Json
}
catch {
    Write-Error "Error: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
    $body = @{
        message = "Error: $_"
        success = $false
    } | ConvertTo-Json
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
})