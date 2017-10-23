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

# copied from https://gallery.technet.microsoft.com/Generate-a-random-and-5c879ed5
function New-SWRandomPassword {
    <#
    .Synopsis
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .EXAMPLE
       New-SWRandomPassword
       C&3SX6Kn

       Will generate one password with a length between 8  and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -MinPasswordLength 8 -MaxPasswordLength 12 -Count 4
       7d&5cnaB
       !Bh776T"Fw
       9"C"RxKcY
       %mtM7#9LQ9h

       Will generate four passwords, each with a length of between 8 and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
       the string specified with the parameter FirstChar
    .OUTPUTS
       [String]
    .NOTES
       Written by Simon Wåhlin, blog.simonw.se
       I take no responsibility for any issues caused by this script.
    .FUNCTIONALITY
       Generates random passwords
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]$MinPasswordLength = 8,
        
        # Specifies maximum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({
                if($_ -ge $MinPasswordLength){$true}
                else{Throw 'Max value cannot be lesser than min value.'}})]
        [Alias('Max')]
        [int]$MaxPasswordLength = 12,

        # Specifies a fixed password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='FixedLength')]
        [ValidateRange(1,2147483647)]
        [int]$PasswordLength = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789', '!#%&_'),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String] $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]$Count = 1
    )
    Begin {
        Function Get-Seed{
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process {
        For($iteration = 1;$iteration -le $Count; $iteration++){
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputStrings

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinPasswordLength -eq $MaxPasswordLength) {
                    # If password length is set, use set length
                    $PasswordLength = $MinPasswordLength
                }
                else {
                    # Otherwise randomize password length
                    $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $PasswordLength) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
        }
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
$ClientSecret = New-SWRandomPassword -PasswordLength 20

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

