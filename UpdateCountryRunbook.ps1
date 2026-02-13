param(
  [Parameter(Mandatory=$true)]
  [string]$UserPrincipalName,
  
  [Parameter(Mandatory=$true)]
  [string]$Country
)

Write-Output "Processing country change request for: $UserPrincipalName to $Country"

# 1) Import required module
try {
  Import-Module ActiveDirectory -ErrorAction Stop
  Write-Output "ActiveDirectory module imported successfully"
}
catch {
  throw "Failed to import ActiveDirectory module: $_"
}

# 2) Define country mapping
$CountryMap = @{
  "Azerbaijan" = @{ c="AZ"; co="Azerbaijan"; countryCode=31 }
  "Russia"     = @{ c="RU"; co="Russia"; countryCode=643 }
  "Germany"    = @{ c="DE"; co="Germany"; countryCode=276 }
  "United States" = @{ c="US"; co="United States"; countryCode=840 }
}

# 3) Validate country
if (-not $CountryMap.ContainsKey($Country)) {
  throw "Invalid country '$Country'. Allowed values: $($CountryMap.Keys -join ', ')"
}

$values = $CountryMap[$Country]

# 4) Find and update AD user
try {
  $user = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" `
                     -Properties c, co, countryCode `
                     -ErrorAction Stop
  
  if (-not $user) {
    throw "User not found with UPN: $UserPrincipalName"
  }
  
  Write-Output "Found user: $($user.Name)"
}
catch {
  throw "Error finding user: $_"
}

# 5) Update AD user attributes
try {
  Set-ADUser -Identity $user.DistinguishedName `
             -Replace @{
               c = $values.c
               co = $values.co
               countryCode = $values.countryCode
             } `
             -ErrorAction Stop
  
  Write-Output "Successfully updated AD user attributes for: $UserPrincipalName"
}
catch {
  throw "Error updating AD user: $_"
}

# 6) Trigger delta sync if available
try {
  if (Get-Command Start-ADSyncSyncCycle -ErrorAction SilentlyContinue) {
    Start-ADSyncSyncCycle -PolicyType Delta | Out-Null
    Write-Output "Delta sync cycle triggered successfully"
    $syncStatus = "delta"
  }
  else {
    Write-Output "Azure AD Connect sync not available on this system"
    $syncStatus = "not_available"
  }
}
catch {
  Write-Warning "Error triggering delta sync: $_"
  $syncStatus = "error"
}

# 7) Return success response
$result = @{
  status = "success"
  upn = $UserPrincipalName
  country = $Country
  countryCode = $values.c
  countryCodeNumeric = $values.countryCode
  sync = $syncStatus
  timestamp = (Get-Date).ToUniversalTime()
} | ConvertTo-Json

Write-Output $result