#!/usr/bin/env bash

resourceGroupName="REPLACE-ME-WITH-YOUR-RESOURCE-GROUP-NAME" 
location="REPLACE-ME-WITH-THE-LOCATION-OF-YOUR-RESOURCE-GROUP"
publicIPName="REPLACE-ME-WITH-THE-PUBLIC-IP-NAME-OF-CLOUDFOUNDRY"
loadBalancerName="cf-ssh-lb"
frontendIPName="fip"
backendPoolName="backendpool"
idleTimeout=15
probeName="healthprobe"
probePort=2222

az network public-ip create --resource-group $resourceGroupName --name $publicIPName --allocation-method Static --location $location

az network lb create --resource-group $resourceGroupName --name $loadBalancerName --location $location --public-ip-address $publicIPName --frontend-ip-name $frontendIPName --backend-pool-name $backendPoolName

az network lb probe create --resource-group $resourceGroupName --lb-name $loadBalancerName --name $probeName --protocol tcp --port $probePort --interval 15 --threshold 4

tcpPorts="2222"
for tcpPort in $tcpPorts
do
  az network lb rule create --resource-group $resourceGroupName --lb-name $loadBalancerName --name "lbruletcp$tcpPort" --protocol tcp --frontend-port $tcpPort --backend-port $tcpPort --frontend-ip-name $frontendIPName --backend-pool-name $backendPoolName --idle-timeout $idleTimeout --probe-name $probeName
done
