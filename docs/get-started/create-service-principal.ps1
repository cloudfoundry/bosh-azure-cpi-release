#
# this script is modified from https://github.com/cf-platform-eng/bosh-azure-template/blob/master/create_azure_principal.sh,
# and makes the following assumptions
#   1. Azure CLI is installed on the machine when this script is runnning
#   2. User has set Azure CLI to arm mode, and logged in with work or school account
#   3. Current account has sufficient privileges to create AAD application and service principal
#
#   This script will return clientID, tenantID, client-secret that can be used to
#   populate cloud foundry on Azure.


# function to wrap native command for error handling
function Invoke-NativeCommand {
  $command = $args[0]
  $arguments = $args[1..($args.Length)]
  & $command @arguments
  if (!$?) {
    Write-Error "Exit code $LastExitCode while running $command $arguments"
  }
}

# equals 'set +e'
$ErrorActionPreference = "Continue"

Write-Host "Check if Azure CLI has been installed..."
$VersionCheck = (azure -v | ?{ $_ -match "[^0-9\.rc]" })
if ($VersionCheck)
{
  Write-Host "Azure CLI is not installed. Please install Azure CLI by following tutorial at https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/."
  exit 1
}

Write-Host "Set Azure CLI to arm mode..."
azure config mode arm

# check if user needs to login
$LoginCheck=(azure resource list 2>&1 | ?{ $_ -match "error" })
if ($LoginCheck) {
  Write-Host "You need login to continue..."
  Write-Host "Which Azure environment do you want to login?"
  Write-Host "1) AzureCloud (default)"
  Write-Host "2) AzureChinaCloud"
  Write-Host "3) AzureUSGovernment"
  Write-Host "4) AzureGermanCloud"
  $EnvOpt = Read-Host "Please choose by entering 1, 2, 3 or 4: "
  $Env = "AzureCloud"
  if ("$EnvOpt" -eq 2) {
    $Env = "AzureChinaCloud"
  }
  if ("$EnvOpt" -eq 3) {
    $Env = "AzureUSGovernment"
  }
  if ("$EnvOpt" -eq 4) {
    $Env = "AzureGermanCloud"
  }
  Write-Host "Login to $Env..."
  azure login --environment $Env
}

# equlas 'set -e'
$ErrorActionPreference = "Stop"

# get subscription info, let user choose one if there're multiple subcriptions
$SubscriptionCount = (Invoke-NativeCommand azure account list | ?{ $_ -match "Enable" }).count

if ($SubscriptionCount -gt 1)
{
    Write-Host "There are $SubscriptionCount subscriptions in your account:"
    azure account list
    $InputId = Read-Host "Copy and paste the Id of the subscription that you want to create Service Principal with"
    $SubscriptionId = (Invoke-NativeCommand azure account list | ?{ $_ -match "Enable" } | ?{ $_ -match $InputId } | %{ ($_ -split "  +")[2] })
}
else
{
    $SubscriptionId = (Invoke-NativeCommand azure account list | ?{ $_ -match "Enable" } | %{ ($_ -split "  +")[2] })
}

Write-Host "Use subscription $SubscriptionId..."
Invoke-NativeCommand azure account set $SubscriptionId

# get identifier for Service Principal
$DefaultIdentifier = "BOSHv" + [guid]::NewGuid()
$Identifier = "1"
while (("$Identifier".length -gt 0) -and ("$Identifier".length -lt 8) -or ("$Identifier".contains(" "))) {
    $Identifier = Read-Host "Please input identifier for your Service Principal with (1) MINIMUM length of 8, (2) NO space [press Enter to use default identifier $DefaultIdentifier]"
}
$Identifier = if ($Identifier) { $Identifier } else { $DefaultIdentifier }

Write-Host "Use $Identifier as identifier..."
$BoshName = $Identifier
$IdUris = "http://" + $Identifier
$HomePage = "http://" + $Identifier
$SpName = "http://" + $Identifier

$TenantId = (Invoke-NativeCommand azure account show | ?{ $_ -match "Tenant ID" } | %{ ($_ -split " ")[-1] })
$ClientSecret = ("Pwd" + [guid]::NewGuid()).SubString(0, 11)

Write-Host "Create Active Directory application..."
$ClientId = (Invoke-NativeCommand azure ad app create --name $BoshName --password $ClientSecret --identifier-uris $IdUris --home-page $HomePage | ?{ $_ -match "AppId:" } | %{ ($_ -split " ")[-1] })

$ErrorActionPreference = "Continue"

while ($true) {
    Start-Sleep 10
    $AppCheck = (azure ad app show -a $ClientId 2>&1 | ?{ $_ -match "error" })
    if (-Not $AppCheck) {
      break
    } 
}

$ErrorActionPreference = "Stop"

Write-Host "Create Service Principal..."
Invoke-NativeCommand azure ad sp create --applicationId $ClientId

$ErrorActionPreference = "Continue"

while ($true) {
    Start-Sleep 10
    $SpCheck = (azure ad sp show --spn "$SPNAME" 2>&1 | ?{ $_ -match "error" })
    if (-Not $SpCheck) {
      break
    }
}

$ErrorActionPreference = "Stop"

# let user choose what kind of role they need
Write-Host "What kind of privileges do you want to assign to Service Principal?"
Write-Host "1) Least privileges, includes Virtual Machine Contributor and Network Contributor (Default)"
Write-Host "2) Full privileges, includes Contributor"
$Privilege = Read-Host "Please choose by entering 1 or 2"

Write-Host "Assign roles to Service Principal..."
if ($Privilege -eq 2) {
    Invoke-NativeCommand azure role assignment create --roleName "Contributor" --spn $SpName --subscription $SubscriptionId
}
else {
    Invoke-NativeCommand azure role assignment create --roleName "Virtual Machine Contributor" --spn $SpName --subscription $SubscriptionId
    Invoke-NativeCommand azure role assignment create --roleName "Network Contributor" --spn $SpName --subscription $SubscriptionId
}

Write-Host "Successfully created Service Principal."
Write-Host "==============Created Serivce Principal=============="
Write-Host "SUBSCRIPTION_ID:" $SubscriptionId
Write-Host "CLIENT_ID:      " $ClientId
Write-Host "TENANT_ID:      " $TenantId
Write-Host "CLIENT_SECRET:  " $ClientSecret

