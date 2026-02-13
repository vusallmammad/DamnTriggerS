using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "Country Change Request received"
Write-Host "Request Body: $($Request.Body | ConvertTo-Json)"

# 1) Parse the incoming request
$userPrincipalName = $Request.Body.UserPrincipalName
$country = $Request.Body.Country

# 2) Validate inputs
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

# 3) Define country mapping
$CountryMap = @{
    "Azerbaijan" = @{ c="AZ"; co="Azerbaijan"; countryCode=31 }
    "Russia"     = @{ c="RU"; co="Russia"; countryCode=643 }
    "Germany"    = @{ c="DE"; co="Germany"; countryCode=276 }
    "United States" = @{ c="US"; co="United States"; countryCode=840 }
}

# 4) Validate country
if (-not $CountryMap.ContainsKey($country)) {
    $statusCode = [HttpStatusCode]::BadRequest
    $body = @{
        message = "Invalid country '$country'. Allowed values: $($CountryMap.Keys -join ', ')"
        success = $false
    } | ConvertTo-Json
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Body       = $body
    })
    return
}

try {
    # 5) Get environment variables for Automation Account
    $resourceGroupName = $env:RESOURCE_GROUP_NAME
    $automationAccountName = $env:AUTOMATION_ACCOUNT_NAME
    $runbookName = $env:RUNBOOK_NAME
    $hybridWorkerGroupName = $env:HYBRID_WORKER_GROUP_NAME
    
    if (-not $resourceGroupName -or -not $automationAccountName -or -not $runbookName) {
        throw "Missing environment variables: RESOURCE_GROUP_NAME, AUTOMATION_ACCOUNT_NAME, or RUNBOOK_NAME"
    }

    Write-Host "Triggering runbook: $runbookName on Hybrid Worker Group: $hybridWorkerGroupName"
    
    # 6) Start the runbook on Hybrid Runbook Worker
    $runbookParams = @{
        UserPrincipalName = $userPrincipalName
        Country = $country
    }
    
    $runbookJob = Start-AzAutomationRunbook -ResourceGroupName $resourceGroupName `
                                            -AutomationAccountName $automationAccountName `
                                            -Name $runbookName `
                                            -Parameters $runbookParams `
                                            -RunOn $hybridWorkerGroupName
    
    Write-Host "Runbook job created with ID: $($runbookJob.JobId)"
    
    # 7) Wait for job completion (optional - set timeout)
    $timeout = 0
    $maxTimeout = 300  # 5 minutes
    
    while ($runbookJob.RuntimeJobStatus -eq "Running" -and $timeout -lt $maxTimeout) {
        Start-Sleep -Seconds 2
        $runbookJob = Get-AzAutomationJob -ResourceGroupName $resourceGroupName `
                                          -AutomationAccountName $automationAccountName `
                                          -Id $runbookJob.JobId
        $timeout += 2
    }
    
    # 8) Get job output
    $jobOutput = Get-AzAutomationJobOutput -ResourceGroupName $resourceGroupName `
                                           -AutomationAccountName $automationAccountName `
                                           -Id $runbookJob.JobId -Stream Output
    
    if ($runbookJob.RuntimeJobStatus -eq "Completed") {
        $statusCode = [HttpStatusCode]::OK
        $body = @{
            message = "Country updated successfully"
            success = $true
            upn = $userPrincipalName
            country = $country
            jobId = $runbookJob.JobId
            jobStatus = $runbookJob.RuntimeJobStatus
            timestamp = (Get-Date).ToUniversalTime()
        } | ConvertTo-Json
    }
    else {
        throw "Runbook job failed with status: $($runbookJob.RuntimeJobStatus)"
    }
}
catch {
    Write-Error "Error processing request: $_"
    $statusCode = [HttpStatusCode]::InternalServerError
    $body = @{
        message = "Error processing request: $_"
        success = $false
        upn = $userPrincipalName
        country = $country
    } | ConvertTo-Json
}

# 9) Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = $body
})