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

# 3) Define country mapping (same as runbook)
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

$values = $CountryMap[$country]

try {
    # 5) Import Active Directory module
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "ActiveDirectory module imported successfully"
    
    # 6) Find AD user
    $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" `
                       -Properties c, co, countryCode `
                       -ErrorAction Stop
    
    if (-not $user) {
        throw "User not found with UPN: $userPrincipalName"
    }
    
    Write-Host "Found user: $($user.Name)"
    
    # 7) Update AD user attributes
    Set-ADUser -Identity $user.DistinguishedName `
               -Replace @{
                   c = $values.c
                   co = $values.co
                   countryCode = $values.countryCode
               } `
               -ErrorAction Stop
    
    Write-Host "Successfully updated AD user attributes for: $userPrincipalName"
    
    # 8) Trigger delta sync if available
    $syncStatus = "not_available"
    if (Get-Command Start-ADSyncSyncCycle -ErrorAction SilentlyContinue) {
        try {
            Start-ADSyncSyncCycle -PolicyType Delta | Out-Null
            Write-Host "Delta sync cycle triggered successfully"
            $syncStatus = "delta"
        }
        catch {
            Write-Warning "Error triggering delta sync: $_"
            $syncStatus = "error"
        }
    }
    
    # 9) Return success response
    $statusCode = [HttpStatusCode]::OK
    $body = @{
        message = "Country updated successfully"
        success = $true
        upn = $userPrincipalName
        country = $country
        countryCode = $values.c
        countryCodeNumeric = $values.countryCode
        sync = $syncStatus
        timestamp = (Get-Date).ToUniversalTime()
    } | ConvertTo-Json
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

# 10) Return response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body       = $body
})