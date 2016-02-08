$location=Read-Host -Prompt "Input your location (e.g. East Asia)"
$rgName=Read-Host -Prompt "Input your resource group name"
$appgwName=Read-Host -Prompt "Input your application gateway name"

If ($location -eq "" -or $rgName -eq "" -or $appgwName -eq "") {
    Write-Host "location, resource group name and application gateway name can't be empty. Will exit!"
    Return
}
Write-Host "Will create the application gateway", $appgwName, "in your resrouce group", $rgName

$vnetName=Read-Host -Prompt "Input your virtual network name [boshvnet-crp]"
if ($vnetName -eq "") {
    $vnetName="boshvnet-crp"
}
$subnetName=Read-Host -Prompt "Input your subnet name for the application gateway [ApplicationGateway]"
if ($subnetName -eq "") {
    $subnetName="ApplicationGateway"
}

$publicipName=Read-Host -Prompt "Input your public IP name[publicIP01]"
if ($publicipName -eq "") {
    $publicipName="publicIP01"
}

$routerIPList = Read-Host -Prompt 'Input the list of router IP addresses (split by ";")'
$routerIPs = $routerIPList -split ";"
$routerNumber = $routerIPs.Length

$systemDomain = Read-Host -Prompt "Input your system domain"
$certInfoList = Read-Host -Prompt "Input the hostname, path and password of the certificates (Format: hostname1,path1,password1;hostname2,path2,password2;...)"

# Remove it if the application gateway (AG) exists
Write-Host "Removing it if the application gateway exists"
Remove-AzureRmApplicationGateway -Name $appgwName -ResourceGroupName $rgName -Force

# Add the subnet for AG
Write-Host "Adding the subnet for the application gateway"
$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet

# Create public IP address for front end configuration
Write-Host "Creating public IP address for front end configuration"
$publicip = New-AzureRmPublicIpAddress -ResourceGroupName $rgName -name $publicipName -location $location -AllocationMethod Dynamic -Force

# When AG starts, it will pick up an IP address from the subnet configured and 
# route network traffic to the IP addresses in the back end IP pool
Write-Host "Creating IP configuration"
$gipconfig = New-AzureRmApplicationGatewayIPConfiguration -Name gatewayIP01 -Subnet $subnet

# Configure the back end IP address pool named with routers' IP addresses
# which can be found in your Cloud Foundry manifest
Write-Host "Configuring the back end IP address pool"
$pool = New-AzureRmApplicationGatewayBackendAddressPool -Name pool01 -BackendIPAddresses $routerIPs

# Configure a probe which will detect whether backend servers are healthy.
# It detects "login.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io/login" every 60 seconds.
Write-Host "Configuring a probe"
$hostName="login."+$systemDomain
$probe=New-AzureRmApplicationGatewayProbeConfig -Name Probe01 -Protocol Http -HostName $hostName -Path "/login" -Interval 60 -Timeout 60 -UnhealthyThreshold 3

# Configure AG settings to load balance network traffic in the back end pool
Write-Host "Configuring pool settings"
$poolSetting = New-AzureRmApplicationGatewayBackendHttpSettings -Name poolsetting01 -Port 80 -Protocol Http -CookieBasedAffinity Disabled -RequestTimeout 60 -Probe $probe

# Create the front end IP configuration and associates the public IP address with the front end IP configuration.
Write-Host "Creating the front end IP configuration"
$fipconfig = New-AzureRmApplicationGatewayFrontendIPConfig -Name fipconfig01 -PublicIPAddress $publicip

# Configure the front end IP port (80 and 443) in this case for the public IP endpoint
Write-Host "Configuring the front end IP port (80 and 443)"
$fp_http = New-AzureRmApplicationGatewayFrontendPort -Name frontendporthttp -Port 80
$fp_https = New-AzureRmApplicationGatewayFrontendPort -Name frontendporthttps -Port 443
$fps = $fp_http,$fp_https

$certs = @()
$listeners = @()
$rules = @()

$listener0 = New-AzureRmApplicationGatewayHttpListener -Name listener0 -Protocol Http -FrontendIPConfiguration $fipconfig -FrontendPort $fp_http
$rule0 = New-AzureRmApplicationGatewayRequestRoutingRule -Name rule0 -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener0 -BackendAddressPool $pool
$listeners += $listener0
$rules += $rule0

# Configure the certificate used for SSL connection.
# The certificate needs to be in .pfx format and password between 4 to 12 characters.
Write-Host "Configuring the certificate used for SSL connection"
$i = 1
$certInfors = $certInfoList -split ";"
foreach ($certInfo in $certInfors) {
    $hostName, $certPath, $passwd = $certInfo -split ","
    $cert = New-AzureRmApplicationGatewaySslCertificate -Name "cert$i" -CertificateFile $certPath -Password $passwd
    $listener = New-AzureRmApplicationGatewayHttpListener -Name "listener$i" -Protocol Https -FrontendIPConfiguration $fipconfig -FrontendPort $fp_https -SslCertificate $cert -HostName $hostName -RequireServerNameIndication true 
    $rule = New-AzureRmApplicationGatewayRequestRoutingRule -Name "rule$i" -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener -BackendAddressPool $pool
    $certs += $cert
    $listeners += $listener
    $rules += $rule
    $i += 1
}

# Configure the instance size of the AG
Write-Host "Configuring the instance size of the AG"
$sku = New-AzureRmApplicationGatewaySku -Name Standard_Small -Tier Standard -Capacity $routerNumber

# Create an AG with all configuration items from the steps above
Write-Host "Creating the application gateway"
$appgw = New-AzureRmApplicationGateway -Name $appgwName -ResourceGroupName $rgName -Location $location -BackendAddressPools $pool -BackendHttpSettingsCollection $poolSetting -FrontendIpConfigurations $fipconfig  -GatewayIpConfigurations $gipconfig -FrontendPorts $fps -HttpListeners $listeners -RequestRoutingRules $rules -Sku $sku -SslCertificates $certs -Probes $probe

$publicip = Get-AzureRmPublicIpAddress -ResourceGroupName $rgName -name $publicipName
if ($publicip.IpAddress -ne "Not Assigned") {
  Write-Host "Succeed to create the application gateway."
  Write-Host "The public IP of the application gateway is:", $publicip.IpAddress
} else {
  Write-Host "Fail to create the application gateway"
}
