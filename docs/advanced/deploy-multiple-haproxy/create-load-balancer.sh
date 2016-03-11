#!/usr/bin/env bash

resourceGroupName="REPLACE-ME-WITH-YOUR-RESOURCE-GROUP-NAME" 
location="REPLACE-ME-WITH-THE-LOCATION-OF-YOUR-RESOURCE-GROUP"
virtualNetworkName="REPLACE-ME-WITH-VNET-NAME" # Default: boshvnet-crp
publicIPName="REPLACE-ME-WITH-THE-PUBLIC-IP-NAME-OF-CLOUDFOUNDRY" # Default: <YOUR-DEVBOX-NAME>-cf
loadBalancerName="haproxylb" # This will be used in your Cloud Foundry manifest
frontendIPName="fip"
backendPoolName="backendpool"

azure config mode arm

azure network lb create --resource-group $resourceGroupName --name $loadBalancerName --location $location

azure network lb frontend-ip create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $frontendIPName --public-ip-name $publicIPName

azure network lb address-pool create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $backendPoolName

azure network lb probe create --resource-group $resourceGroupName --lb-name $loadBalancerName --name healthprobe --protocol tcp --port 22 --interval 15 --count 4

tcpPorts="22 80 443 2222 4222 4443 6868 25250 25555 25777"
for tcpPort in $tcpPorts
do
azure network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruletcp$tcpPort" --protocol tcp --frontend-port $tcpPort --backend-port $tcpPort --frontend-ip-name $frontendIPName --backend-address-pool-name $backendPoolName
done

udpPorts="53 68"
for udpPort in $udpPorts
do
azure network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruleudp$udpPort" --protocol udp --frontend-port $udpPort --backend-port $udpPort --frontend-ip-name $frontendIPName --backend-address-pool-name $backendPoolName
done
