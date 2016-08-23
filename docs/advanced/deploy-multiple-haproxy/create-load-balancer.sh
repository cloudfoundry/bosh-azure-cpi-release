#!/usr/bin/env bash

resourceGroupName="REPLACE-ME-WITH-YOUR-RESOURCE-GROUP-NAME" 
location="REPLACE-ME-WITH-THE-LOCATION-OF-YOUR-RESOURCE-GROUP"
publicIPName="REPLACE-ME-WITH-THE-PUBLIC-IP-NAME-OF-CLOUDFOUNDRY" # Default: <YOUR-DEVBOX-NAME>-cf
loadBalancerName="haproxylb" # This will be used in your Cloud Foundry manifest
frontendIPName="fip"
backendPoolName="backendpool"
idleTimeout=15 # Minutes. Match the default timeout in HAPROXY
probeName="healthprobe"
probePort=443 # You can change to 80 if 443 is disabled in your deployment

azure config mode arm

azure network lb create --resource-group $resourceGroupName --name $loadBalancerName --location $location

azure network lb frontend-ip create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $frontendIPName --public-ip-name $publicIPName

azure network lb address-pool create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $backendPoolName

azure network lb probe create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $probeName --protocol tcp --port $probePort --interval 15 --count 4

tcpPorts="22 80 443 2222 4222 4443 6868 25250 25555 25777"
for tcpPort in $tcpPorts
do
  azure network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruletcp$tcpPort" --protocol tcp --frontend-port $tcpPort --backend-port $tcpPort --frontend-ip-name $frontendIPName --backend-address-pool-name $backendPoolName --idle-timeout $idleTimeout --probe-name $probeName
done

udpPorts="53 68"
for udpPort in $udpPorts
do
  azure network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruleudp$udpPort" --protocol udp --frontend-port $udpPort --backend-port $udpPort --frontend-ip-name $frontendIPName --backend-address-pool-name $backendPoolName --idle-timeout $idleTimeout --probe-name $probeName
done
