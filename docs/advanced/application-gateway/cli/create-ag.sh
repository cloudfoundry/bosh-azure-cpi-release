while true; do
  read -p "Input your location (e.g. East Asia): " location
  if [ -z "$location" ]; then
    echo "Location can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input your resource group name: " rgName
  if [ -z "$rgName" ]; then
    echo "Resource group name can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input your application gateway name: " appgwName
  if [ -z "$appgwName" ]; then
    echo "Application gateway name can't be null"
  else
    break;
  fi
done

echo "Will create the application gateway" $appgwName "in your resrouce group" $rgName

read -p "Input your virtual network name [boshvnet-crp]: " vnetName
if [ -z "$vnetName" ]; then
  vnetName="boshvnet-crp"
fi

read -p "Input your subnet name for the application gateway [ApplicationGateway]: " subnetName
if [ -z "$subnetName" ]; then
  subnetName="ApplicationGateway"
fi

read -p "Input your public IP name[publicIP01]: " publicipName
if [ -z "$publicipName" ]; then
  publicipName="publicIP01"
fi

routerNumber=2

while true; do
  read -p "Input your system domain[REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io]: " systemDomain
  if [ -z "$systemDomain" ]; then
    echo "System domain can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input the path of the certificate: " certPath
  if [ -z "$certPath" ]; then
    echo "Certificate can't be null"
  else
    break;
  fi
done

while true; do
  read -p "Input the password of the certificate: " passwd
  if [ -z "$passwd" ]; then
    echo "password can't be null"
  else
    break;
  fi
done

# Remove it if the application gateway (AG) exists
echo "Removing it if the application gateway exists"
azure network application-gateway delete --resource-group $rgName --name $appgwName --quiet

# Create public-ip
echo "Creating public IP address for front end configuration"
azure network public-ip create --resource-group $rgName --name $publicipName --location $location --allocation-method Dynamic

# Create AG
azure network application-gateway create --resource-group $rgName --name $appgwName --location $location --vnet-name $vnetName --subnet-name $subnetName --http-settings-protocol http --http-settings-port 80 --http-settings-cookie-based-affinity Disabled --frontend-port 80 --public-ip-name $publicipName --http-listener-protocol http --routing-rule-type Basic --sku-name Standard_Small --sku-tier Standard --capacity $routerNumber

# Create probe
echo "Configuring a probe"
$hostName="login."$systemDomain
azure network application-gateway probe create --resource-group $rgName --gateway-name $appgwName --name 'Probe01' --protocol Http --host-name $hostName --path '/login' --interval 60 --timeout 60 --unhealthy-threshold 3 

# TODO
# Need to set the custom probe for the http settings via Azure Portal or Azure Powershell
# The next release of Azure CLI will supported setting the custom probe

# Create HTTPS frontend-port
azure network application-gateway frontend-port create --resource-group $rgName --gateway-name $appgwName --name frontendporthttps --port 443 --nowait
azure network application-gateway frontend-port create --resource-group $rgName --gateway-name $appgwName --name frontendportlogs --port 4443 --nowait

# Create AG ssl-cert
azure network application-gateway ssl-cert create --resource-group $rgName --gateway-name $appgwName --name 'cert01' --cert-file $certPath --cert-password $passwd --nowait

# Create the listener and rule for frontend point 443
azure network application-gateway http-listener create --resource-group $rgName --gateway-name $appgwName --name 'listener02' --frontend-ip-name $publicipName --frontend-port-name frontendporthttps --protocol https --ssl-cert 'cert01' --nowait
azure network application-gateway rule create --resource-group $rgName --gateway-name $appgwName --name 'rule02' --type Basic --http-settings-name 'httpSettings01' --http-listener-name 'listener02' --address-pool-name 'pool01' --nowait

# Create the listener and rule for frontend point 4443
azure network application-gateway http-listener create --resource-group $rgName --gateway-name $appgwName --name 'listener03' --frontend-ip-name $publicipName --frontend-port-name frontendportlogs --protocol https --ssl-cert 'cert01' --nowait
azure network application-gateway rule create --resource-group $rgName --gateway-name $appgwName --name 'rule03' --type Basic --http-settings-name 'httpSettings01' --http-listener-name 'listener03' --address-pool-name 'pool01' --nowait
