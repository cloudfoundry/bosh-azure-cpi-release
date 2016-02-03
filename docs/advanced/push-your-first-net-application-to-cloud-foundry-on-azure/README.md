# Push your first .NET application to cloud foundry on Azure #
This guide references [INSTALL.md](https://github.com/cloudfoundry-incubator/diego-windows-release/blob/master/docs/INSTALL.md)

## Before you begin ##
You have deployed your **BOSH director VM** on Azure by following this [guide](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/blob/master/docs/guidance.md).

## Create two new subnets for Diego and Windows Servers ##
1. Sign in to Azure portal.
2. Find your resource group which was created for your cloud foundry.
3. Find the virtual network **boshvnet-crp** in above resource group.
4. Create below two subnets
    - Name: **Diego**, CIDR: **10.0.32.0/20**
    - Name: **Windows**, CIDR: **10.0.48.0/20**

![create-two-subnets](./create-two-subnets.png "create-two-subnets")

## Deploy you cloud foundry on Azure ##
1. Log on to your dev-box.
2. Download multiple-vm-cf-224-diego.yml

  ```
  wget -O ~/multiple-vm-cf-224-diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/example_manifests/multiple-vm-cf-224-diego.yml
  ```
3. Login to your BOSH director VM

  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin.
  ```
  _**Note:** If you have used ‘bosh logout’, you should use ‘bosh login admin admin’ to log in._
4. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=224
  bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3169
  ```
5. Update **BOSH-DIRECTOR-UUID** in **~/multiple-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/BOSH-DIRECTOR-UUID/$(bosh status --uuid)/" ~/multiple-vm-cf-224-diego.yml
  ```
6. Update CF **RESERVED-IP** in **~/multiple-vm-cf-224-diego.yml**

  ```
  sed -i -e "s/RESERVED-IP/$(cat ~/settings |grep cf-ip| sed 's/.*: "\(.*\)",/\1/')/" ~/multiple-vm-cf-224-diego.yml
  ```
7. Update **SSL-CERT-AND-KEY** in **~/multiple-vm-cf-224-diego.yml**
   You should use your certificate and key. If you do not want to use yours, please use below command to generate a new one and update SSL-CERT-AND-KEY in ~/multiple-vm-cf-224-diego.yml automatically.

  ```
  openssl genrsa -out ~/haproxy.key 2048 &&
  echo -e "\n\n\n\n\n\n\n" | openssl req -new -x509 -days 365 -key ~/haproxy.key -out ~/haproxy_cert.pem &&
  cat ~/haproxy_cert.pem ~/haproxy.key > ~/haproxy.ssl &&
  awk -vr="$(sed -e '2,$s/^/        /' ~/haproxy.ssl)" '(sub("SSL-CERT-AND-KEY",r))1' ~/multiple-vm-cf-224-diego.yml > tmp &&
  mv -f tmp ~/multiple-vm-cf-224-diego.yml
  ```
8. Set BOSH deployment

  ```
  bosh deployment ~/multiple-vm-cf-224-diego.yml
  ```
9. Deploy cloud foundry

  ```
  bosh -n deploy
  ```

## Deploy Diego on Azure ##
1. Log on to your dev-box
2. Download diego.yml

  ```
  wget -O ~/diego.yml https://raw.githubusercontent.com/cloudfoundry-incubator/bosh-azure-cpi-release/master/docs/example_manifests/diego.yml
  ```
3. Upload releases

  ```
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/garden-linux-release?v=0.330.0
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/etcd-release?v=20
  bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/diego-release?v=0.1444.0
  ```
4. Update **BOSH-DIRECTOR-UUID** in **~/diego.yml**

  ```
  sed -i -e "s/BOSH-DIRECTOR-UUID/$(bosh status --uuid)/" ~/diego.yml
  ```
5. Set BOSH deployment

 ```
 bosh deployment ~/diego.yml
 ```
6. Deploy Diego

  ```
  bosh -n deploy
  ```

## Add Windows stack ##
1. Sign in to the Azure portal.
2. On the Hub menu, click **New** > **Compute** > **Windows Server 2012 R2 Datacenter**.

  ![select-windows-server-2k12R2](./windows-stack-select-windows-server-2k12R2.png "select-windows-server-2k12R2")

3. On the **Windows Server 2012 R2 Datacenter** page, under **Select a deployment model**, select **Resource Manager**. Click **Create**.

  ![windows-stack-select-resource-manager](./windows-stack-select-resource-manager.png "windows-stack-select-resource-manager")

4. On the **Create virtual machine** blade, click **Basics**. Enter a **Name** you want for the virtual machine, the administrative **User name**, and a strong **Password**. Please select the **subscription** which you used to deploy cloud foundry. And specify the existing **Resource group** which was created for your cloud foundry and the same **Location** as that for your default storage account.

  ![windows-stack-basics](./windows-stack-basics.png "windows-stack-basics")
  _**NOTE:** **User name** refers to the administrative account that you'll use to manage the server. Create a password that's hard for others to guess but that you can remember. **You'll need the user name and password to log on to the virtual machine.**_

5. Click **Size** and select an appropriate virtual machine size for your needs. For example, Standard D1. Each size specifies the number of compute cores, memory, and other features, such as support for Premium Storage, which will affect the price. Azure recommends certain sizes automatically depending on the image you choose.

  ![windows-stack-size](./windows-stack-size.png "windows-stack-size")
  _**NOTE:** Premium storage is available for DS-series virtual machines in certain regions. Premium storage is the best storage option for data intensive workloads such as a database. For details, see [Premium Storage: High-Performance Storage for Azure Virtual Machine Workloads](https://azure.microsoft.com/en-us/documentation/articles/storage-premium-storage-preview-portal/)._

6. Click **Settings** to see storage and networking settings for the new virtual machine. Please select the default **Storage account** for your cloud foundry. And please specify the **Virtual network** for your cloud foundry and select Windows as your **Subnet**.

  ![windows-stack-settings](./windows-stack-settings.png "windows-stack-settings")
7. Click **Summary** to review your configuration choices. When you're done reviewing or updating the settings, click **OK**.

  ![windows-stack-summary](./windows-stack-summary.png "windows-stack-summary")
8. While Azure creates the virtual machine, you can track the progress in **Notifications**, in the Hub menu. After Azure creates the virtual machine, you'll see it on your Startboard unless you cleared **Pin to Startboard** in the **Create virtual machine** blade.
9. After you create the virtual machine, you need to log on to it.

  _**NOTE:** For requirements and troubleshooting tips, see [Connect to an Azure virtual machine with RDP or SSH](https://msdn.microsoft.com/library/azure/dn535788.aspx)._
10. If you haven't already done so, sign in to the Azure portal.
11. Click your virtual machine on the Startboard. If you need to find it, click **Browse All** > **Recent** or **Browse All** > **Virtual machines**. Then, select your virtual machine from the list.
12. On the virtual machine blade, click **Connect**.

  ![windows-stack-connect](./windows-stack-connect.png "windows-stack-connect")
13. Click **Open** to use the Remote Desktop Protocol file that's automatically created for the Windows Server virtual machine.
14. Click **Connect**.
15. Type the user name and password you set when you created the virtual machine, and then click **OK**.
16. Click **Yes** to verify the identity of the virtual machine.
17. Download [all-in-one](http://cloudfoundry.blob.core.windows.net/windowsstack/all-in-one.zip) and extract it. 
18. Run **all-in-one\setup.ps1**.
19. In command line run **all-in-one\generate.exe** with the following argument template:

  ```
  generate.exe -outputDir=[the directory where the script will output its files]
               -windowsUsername=[the username of an administrator user for Containerizer to run as]
               -windowsPassword=[the password for the same user] 
               -boshUrl=[the URL for your BOSH director, with credentials]
               -machineIp=[(optional) IP address of this cell. Auto-discovered if ommitted]
  ```
  For example:

  ```
  generate.exe -outputDir=.\diego -windowsUsername=AzureAdmin -windowsPassword="MyPass123” -boshUrl=https://admin:admin@10.0.0.4:25555 -machineIp=10.0.48.4
  ```
20. Run the **install.bat** script in the output directory “**.\diego**”. This will install both of the MSIs with all of the arguments they require.

## Configure CF Environment ##
1. Log on to your dev-box
2. Install CF client

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  cf install-plugin Diego-Enabler -r CF-Community
  ```
3. Configure your space

  ```
  cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation -u admin -p c1oudc0w
  cf enable-feature-flag diego_docker
  cf create-org diego
  cf target -o diego
  cf create-space diego
  cf target -s diego
  ```

## Push your first .NET application ##
1. Log on to your dev-box
2. Download the .NET application DiegoMVC and extract it

  ```
  wget https://github.com/ruurdk/DiegoMVC/raw/master/DiegoMVC_Compiled.zip
  unzip DiegoMVC_Compiled.zip
  ```
3. Push DiegoMVC

  ```
  cd DiegoMVC
  cf push diegoMVC -m 1g -s windows2012R2 -b https://github.com/ryandotsmith/null-buildpack.git --no-start -p ./
  cf enable-diego diegoMVC
  cf start diegoMVC
  ```
  _**NOTE:**
  If you have not login to CF, you should use “cf login -a https://api.cf.azurelovecf.com --skip-ssl-validation -u admin -p c1oudc0w” to login and select diego as your orgazination._

## Verify your deployment completed successfully ##
1. If you are using dev-box as your DNS server, you should configure hosts in your local machine.
  - For Linux:

    1. Execute “sudo vi /etc/hosts” and add below lines. Please replace cf-ip with the public IP address which you can find by the command “**cat ~/settings | grep cf-ip**” in your dev-box.

    ```
    cf-ip api.cf.azurelovecf.com
    cf-ip uaa.cf.azurelovecf.com
    cf-ip login.cf.azurelovecf.com
    cf-ip loggregator.cf.azurelovecf.com
    cf-ip diegomvc.cf.azurelovecf.com
    ```
  - For Windows:

    1. Run Notepad as Administrator

    2. Open “C:\Windows\System32\drivers\Etc\hosts” in Notepad and add below lines. Please replace cf-ip with the public IP address which you can find by the command “**cat ~/settings | grep cf-ip**” in your dev-box.

    ```
    cf-ip api.cf.azurelovecf.com
    cf-ip uaa.cf.azurelovecf.com
    cf-ip login.cf.azurelovecf.com
    cf-ip loggregator.cf.azurelovecf.com
    cf-ip diegomvc.cf.azurelovecf.com
    ```
2. Open your web browser, type [http://diegomvc.cf.azurelovecf.com/](http://diegomvc.cf.azurelovecf.com/). Now you can see your .NET Page.

  ![diegomvc](./diegomvc.png "diegomvc")
