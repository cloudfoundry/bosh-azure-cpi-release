In this example, we create 2 routers (10.0.16.12 and 10.0.16.22).

1. Open the PowerShell command window and Log in.

  ```
  PS C:\> Login-AzureRmAccount
  PS C:\> get-AzureRmSubscription	# Get <GUID of your subscription> from the output. You may have multiple subscriptions, and please select the right one.
  PS C:\> Select-AzureRmSubscription -Subscriptionid <GUID of your subscription>
  ```

2. Download the PowerShell script [**New-AG.ps1**](./powershell/New-AG.ps1) to create the Application Gateway. Note AG supports multiple certificates, alternatively you can download this script [**New-AG-multi-certs.ps1**](./powershell/New-AG-multi-certs.ps1) for multiple certificate scenario.

3. Run the script and follow the prompts to specify the configurations.

  This script will create and configure a new Application Gateway with SSL offloading enabled. Note it may take around 15 to 30 minutes to finish.

  If the Application Gateway is created successfully, `New-AG.ps1` will output the public IP address of the AG.

  * Example of the expected inputs and outputs for a single certificate:

    ```
    Input your location (e.g. East Asia): East Asia
    Input your resource group name: testag
    Input your application gateway name: ApplicationGateway
    Will create the application gateway ApplicationGateway in your resrouce group testag
    Input your virtual network name [boshvnet-crp]:
    Input your subnet name for the application gateway [ApplicationGateway]: 
    Input your public IP name[publicIP01]: 
    Input the list of router IP addresses (split by ";"): 10.0.16.12;10.0.16.22
    Input your system domain[REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io]: 
    Input the path of the certificate: D:\domain1.pfx
    Input the password of the certificate: User@111
    Removing it if the application gateway exists
    Adding the subnet for the application gateway
    Creating public IP address for front end configuration
    Creating IP configuration
    Configuring the back end IP address pool
    Configuring a probe
    Configuring pool settings
    Creating the front end IP configuration
    Configuring the front end IP port (80 and 443)
    Configuring the certificate used for SSL connection
    Configuring the instance size of the AG
    Creating the application gateway
    Succeed to create the application gateway.
    The public IP of the application gateway is: <Public IP Address of Application Gateway>
    ```

  * Example of the expected inputs and outputs for multiple certificates:

    ```
    Input your location (e.g. East Asia): East Asia
    Input your resource group name: testag
    Input your application gateway name: ApplicationGateway
    Will create the application gateway ApplicationGateway in your resrouce group testag
    Input your virtual network name [boshvnet-crp]:
    Input your subnet name for the application gateway [ApplicationGateway]: 
    Input your public IP name[publicIP01]: 
    Input the list of router IP addresses (split by ";"): 10.0.16.12;10.0.16.22
    Input your system domain[REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io]: 
    Input the hostname, path and password of the certificates (Format: hostname1,path1,password1;hostname2,path2,password2;...): api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io,D:\domain1.pfx,Password1;game-2048.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io,D:\A.pfx,Password1;demo.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io,D:\B.pfx,Password2
    Removing it if the application gateway exists
    Adding the subnet for the application gateway
    Creating public IP address for front end configuration
    Creating IP configuration
    Configuring the back end IP address pool
    Configuring a probe
    Configuring pool settings
    Creating the front end IP configuration
    Configuring the front end IP port (80 and 443)
    Configuring the certificate used for SSL connection
    Configuring the instance size of the AG
    Creating the application gateway
    Succeed to create the application gateway.
    The public IP of the application gateway is: <Public IP Address of Application Gateway>
    ```