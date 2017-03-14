#!/bin/sh
#
# this script is modified from https://github.com/cf-platform-eng/bosh-azure-template/blob/master/create_azure_principal.sh,
# and makes the following assumptions
#   1. Azure CLI is installed on the machine when this script is runnning
#   2. User has set Azure CLI to arm mode, and logged in with work or school account
#   3. Current account has sufficient privileges to create AAD application and service principal
#
#   This script will return clientID, tenantID, client-secret that can be used to
#   populate cloud foundry on Azure.


set +e

echo "Check if Azure CLI has been installed..."
VERSION_CHECK=`azure -v | grep '[^0-9\.rc]'`
if [ -n "$VERSION_CHECK" ]; then
    echo "Azure CLI is not installed. Please install Azure CLI by following tutorial at https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/."
    exit 1
fi

echo "Set Azure CLI to arm mode..."
azure config mode arm

# check if user needs to login
LOGIN_CHECK=`azure resource list 2>&1 | grep error`
if [ -n "$LOGIN_CHECK" ]; then
    echo "You need login to continue..."
    echo "Which Azure environment do you want to login?"
    echo "1) AzureCloud (default)"
    echo "2) AzureChinaCloud"
    echo "3) AzureUSGovernment"
    echo "4) AzureGermanCloud"
    read -p "Please choose by entering 1, 2, 3 or 4: " ENV_OPT
    ENV="AzureCloud"
    if [ "$ENV_OPT" -eq 2 ]; then
      ENV="AzureChinaCloud"
    fi
    if [ "$ENV_OPT" -eq 3 ]; then
      ENV="AzureUSGovernment"
    fi
    if [ "$ENV_OPT" -eq 4 ]; then
      ENV="AzureGermanCloud"
    fi
    echo "Login to $ENV..."
    azure login --environment $ENV
fi

set -e

# get subscription count, let user choose one if there're multiple subcriptions
SUBSCRIPTION_COUNT=`azure account list | grep Enabled | awk '{print NR}' | tail -1`

if [ "$SUBSCRIPTION_COUNT" -gt 1 ]; then
  echo "There are $SUBSCRIPTION_COUNT subscriptions in your account:"
  azure account list
  read -p "Copy and paste the Id of the subscription that you want to create Service Principal with: " INPUT_ID
  SUBSCRIPTION_ID=`azure account list | grep Enabled | grep $INPUT_ID | awk -F '[[:space:]][[:space:]]+' '{ print $3 }'`
else
  SUBSCRIPTION_ID=`azure account list | grep Enabled | awk -F '[[:space:]][[:space:]]+' '{ print $3 }'`
fi

echo "Use subscription $SUBSCRIPTION_ID..."
azure account set $SUBSCRIPTION_ID

# get identifier for Service Principal
DEFAULT_IDENTIFIER=BOSHv`date +"%Y%m%d%M%S"`
IDENTIFIER="1"
while [ ${#IDENTIFIER} -gt 0 ] && [ ${#IDENTIFIER} -lt 8 ] || [ -n "`echo "$IDENTIFIER" | grep ' '`" ]; do
  read -p "Please input identifier for your Service Principal with (1) MINIMUM length of 8, (2) NO space [press Enter to use default identifier $DEFAULT_IDENTIFIER]: " IDENTIFIER
done
IDENTIFIER=${IDENTIFIER:-$DEFAULT_IDENTIFIER}

echo "Use $IDENTIFIER as identifier..."
BOSHNAME="${IDENTIFIER}"
IDURIS="http://${IDENTIFIER}"
HOMEPAGE="http://${IDENTIFIER}"
SPNAME="http://${IDENTIFIER}"

# create Service Principal
TENANT_ID=`azure account show | grep "Tenant ID" | awk '{print $NF}'`
CLIENT_SECRET=`openssl rand -base64 16 | tr -dc _A-z-a-z-0-9`

echo "Create Active Directory application..."
CLIENT_ID=`azure ad app create --name "$BOSHNAME" --password "$CLIENT_SECRET" --identifier-uris ""$IDURIS"" --home-page ""$HOMEPAGE"" | grep  "AppId:" | awk -F':' '{ print $3 } ' | tr -d ' '`

set +e

while true; do
    sleep 10
    APP_CHECK=`azure ad app show -a $CLIENT_ID 2>&1 | grep error`
    if [ -z "$APP_CHECK" ]; then
        break
    fi
done

set -e

echo "Create Service Principal..."
azure ad sp create --applicationId $CLIENT_ID

set +e

while true; do
    sleep 10
    SP_CHECK=`azure ad sp show --spn "$SPNAME"  2>&1 | grep error`
    if [ -z "$SP_CHECK" ]; then
        break
    fi
done

set -e

# let user choose what kind of role they need

echo "What kind of privileges do you want to assign to Service Principal?"
echo "1) Least privileges, includes Virtual Machine Contributor and Network Contributor (Default)"
echo "2) Full privileges, includes Contributor"
read -p "Please choose by entering 1 or 2: " PRIVILEGE

echo "Assign roles to Service Principal..."
if [ "$PRIVILEGE" -eq 2 ]; then
    azure role assignment create --roleName "Contributor" --spn "$SPNAME" --subscription $SUBSCRIPTION_ID
else
    azure role assignment create --roleName "Virtual Machine Contributor" --spn "$SPNAME" --subscription $SUBSCRIPTION_ID
    azure role assignment create --roleName "Network Contributor" --spn "$SPNAME" --subscription $SUBSCRIPTION_ID
fi

# output service principal
echo "Successfully created Service Principal."
echo "==============Created Serivce Principal=============="
echo "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
echo "TENANT_ID:       $TENANT_ID"
echo "CLIENT_ID:       $CLIENT_ID"
echo "CLIENT_SECRET:   $CLIENT_SECRET"
