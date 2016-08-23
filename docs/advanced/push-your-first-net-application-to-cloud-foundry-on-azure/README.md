# Push your first .NET application to cloud foundry on Azure

This guide references [INSTALL.md](https://github.com/cloudfoundry-incubator/diego-windows-release/blob/master/docs/INSTALL.md)

## 1 Prerequisites

* A deployment of Diego

  You have a deployment of Cloud Foundry with Diego enabled. If you have followed the latest [guidance](../../guidance.md) via ARM templates on Azure, you already have Diego enabled by default.

* A new subnet for Windows Servers

  1. Sign in to Azure portal.
  2. Find your resource group which was created for your cloud foundry.
  3. Find the virtual network in above resource group.
  4. Create a new subnet

    - Name: **Windows**, CIDR: **10.0.48.0/20**

    ![create-new-subnet](./create-new-subnet.png "create-new-subnet")

## 2 Update Cloud Foundry

1. Update your cloud foundry manifest ~/example_manifests/single-vm-cf.yml or ~/example_manifests/multiple-vm-cf.yml.

  ```
    jobs:
    - name: api_z1
      properties:
        nfs_server:
          allow_from_entries: [10.0.16.0/20]
    =>
    jobs:
    - name: api_z1
      properties:
        nfs_server:
          allow_from_entries: [10.0.16.0/20, 10.0.48.0/20]
  ```

  ```
    properties:
      nfs_server:
        allow_from_entries: [10.0.16.0/20]
    =>
    properties:
      nfs_server:
        allow_from_entries: [10.0.16.0/20, 10.0.48.0/20]
  ```

2. Set BOSH deployment to cloud foundry

  ```
  bosh deployment ~/example_manifests/single-vm-cf.yml
  ```

  or

  ```
  bosh deployment ~/example_manifests/multiple-vm-cf.yml
  ```

3. Update your cloud foundry.

  ```
  bosh -n deploy
  ```

## 3 Add Windows stack

### 3.1 Prepare Windows Virtual Machine

1. Sign in to the Azure portal.

2. On the Hub menu, click **New** > **Virtual Machines** > **Windows Server 2012 R2 Datacenter**.

  ![select-windows-server-2k12R2](./windows-stack-select-windows-server-2k12R2.png "select-windows-server-2k12R2")

3. On the **Windows Server 2012 R2 Datacenter** page, under **Select a deployment model**, select **Resource Manager**. Click **Create**.

  ![windows-stack-select-resource-manager](./windows-stack-select-resource-manager.png "windows-stack-select-resource-manager")

4. On the **Create virtual machine** blade, click **Basics**. Select **VM disk type**, enter a **Name** you want for the virtual machine, the administrative **User name**, and a strong **Password**. Please select the **subscription** which you used to deploy cloud foundry. And specify the existing **Resource group** which was created for your cloud foundry and the same **Location** as that for your default storage account.

  ![windows-stack-basics](./windows-stack-basics.png "windows-stack-basics")

  >**NOTE:** **User name** refers to the administrative account that you'll use to manage the server. Create a password that's hard for others to guess but that you can remember. **You'll need the user name and password to log on to the virtual machine.**

5. Click **Size** and select an appropriate virtual machine size for your needs. For example, Standard D1. Each size specifies the number of compute cores, memory, and other features, such as support for Premium Storage, which will affect the price. Azure recommends certain sizes automatically depending on the image you choose.

  ![windows-stack-size](./windows-stack-size.png "windows-stack-size")

  >**NOTE:** Premium storage is available for DS-series virtual machines in certain regions. Premium storage is the best storage option for data intensive workloads such as a database. For details, see [Premium Storage: High-Performance Storage for Azure Virtual Machine Workloads](https://azure.microsoft.com/en-us/documentation/articles/storage-premium-storage-preview-portal/).

6. Click **Settings** to see storage and networking settings for the new virtual machine. Please select the default **Storage account** for your cloud foundry. And please specify the **Virtual network** for your cloud foundry and select Windows as your **Subnet**.

  ![windows-stack-settings](./windows-stack-settings.png "windows-stack-settings")

7. Click **Summary** to review your configuration choices. When you're done reviewing or updating the settings, click **OK**.

  ![windows-stack-summary](./windows-stack-summary.png "windows-stack-summary")

8. While Azure creates the virtual machine, you can track the progress in **Notifications**, in the Hub menu. After Azure creates the virtual machine, you'll see it on your Startboard unless you cleared **Pin to Startboard** in the **Create virtual machine** blade.

9. After you create the virtual machine, you need to log on to it.

  >**NOTE:** For requirements and troubleshooting tips, see [Connect to an Azure virtual machine with RDP or SSH](https://msdn.microsoft.com/library/azure/dn535788.aspx).

10. If you haven't already done so, sign in to the Azure portal.

11. Click your virtual machine on the Startboard. If you need to find it, click **Browse All** > **Recent** or **Browse All** > **Virtual machines**. Then, select your virtual machine from the list.

12. On the virtual machine blade, click **Connect**.

  ![windows-stack-connect](./windows-stack-connect.png "windows-stack-connect")

13. Click **Open** to use the Remote Desktop Protocol file that's automatically created for the Windows Server virtual machine.

14. Click **Connect**.

15. Type the user name and password you set when you created the virtual machine, and then click **OK**.

16. Click **Yes** to verify the identity of the virtual machine.

17. Disable **IE Enhanced Security Configuration**

  Microsoft disabled file downloads by default in Windows Server as part of its security policy. To allow file downloads in Internet Explorer, follow these steps.

  1. By default, Server Manager is opened when you remote to the server.
  2. Select **Local Server** and click IE Enhanced Security Configuration **on**.

  ![windows-stack-disable-ie-enhanced-security-1.PNG](./windows-stack-disable-ie-enhanced-security-1.PNG "windows-stack-disable-ie-enhanced-security-1")

  3. Select **Off** for both Administrators and Users. Click **OK**.

  ![windows-stack-disable-ie-enhanced-security-2.PNG](./windows-stack-disable-ie-enhanced-security-2.PNG "windows-stack-disable-ie-enhanced-security-2")

### 3.2 Deploy Diego Windows on the VM

1. Find compatible releases version.

  [diego-windows-release](https://github.com/cloudfoundry/diego-windows-release/releases) and [garden-windows-release](https://github.com/cloudfoundry/garden-windows-release/releases) are required to deploy a Windows Diego.

  Read release notes carefully and find the compatible version of `diego-windows-release` and `garden-windows-release`, please be noted that they also need to be compatible with diego ([diego-release](https://github.com/cloudfoundry/diego-release/releases)) version that you have deployed in [Prerequisites](#1-prerequisites).

  For example, release note of [diego-windows-release](https://github.com/cloudfoundry/diego-windows-release/releases) v0.400:

  ```
  Built using cloudfoundry/diego-release@23caa9d; Compatible with garden-windows v0.149
  ```

  This means `diego-windows-release v0.400` is compatible with `garden-windows` v0.149 and `diego-release@23caa9d` (which is released as `diego-release` v0.1476.0). If your deployments in [Prerequisites](#1-prerequisites) is using `diego-release` v0.1476.0, these release versions work for you.

2. Download releases and tools.

  Once you have determined the release versions, go ahead to download releases and tools from the release link of `diego-windows-release` and `garden-windows`.

  * from `garden-windows`, downloads
    - setup.ps1
    - GardenWindows.msi
  * from `diego-windows-release`, downloads
    - generate.exe
    - DiegoWindows.msi

3. Right click **setup.ps1** and click **Run with PowerShell**.

4. In command line run **generate.exe** with the following argument template to generate **install.bat** in current directory.

  ```
  generate.exe -outputDir=[the directory where the script will output its files]
               -boshUrl=[the URL for your BOSH director, with credentials]
               -machineIp=[(optional) IP address of this cell. Auto-discovered if ommitted]
  ```

  For example:

  ```
  generate.exe -outputDir=.\ -boshUrl=https://admin:password@10.0.0.4:25555 -machineIp=10.0.48.4
  ```

  You can get user and password from `jobs.properties.director.user_management` of your bosh deployment yaml file (e.g. `bosh.yml`).

  >**Note:** Parameters for generate.exe might change for different releases, you can use run `generate.exe /?` to get help.

5. Run the **install.bat** script as Administrator in the output directory "**.\**". This will install both of the MSIs with all of the arguments they require.

  >**Note:** `GardenWindows.msi` and `DiegoWindows.msi` must be in the same directory with `install.bat`, if `-outputDir` in previous step specifies a different directory, you need to copy/move `GardenWindows.msi` and `DiegoWindows.msi` to that direcotry before running `install.bat`

## 4 Configure CF Environment

1. Log on to your dev-box

2. Install CF client

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  sudo dpkg -i cf.deb
  ```

3. Configure your space

  ```
  cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u admin -p c1oudc0w
  cf create-org diego
  cf target -o diego
  cf create-space diego
  cf target -s diego
  ```

## 5 Push your first .NET application

1. Log on to your dev-box

2. Download the .NET application DiegoMVC and extract it

  ```
  sudo apt-get install -y unzip
  wget https://github.com/ruurdk/DiegoMVC/raw/master/DiegoMVC_Compiled.zip
  unzip DiegoMVC_Compiled.zip
  ```

3. Push DiegoMVC

  ```
  cd DiegoMVC
  cf push diegoMVC -m 1g -s windows2012R2 -b https://github.com/ryandotsmith/null-buildpack.git --no-start -p ./
  cf start diegoMVC
  ```

## 6 Verify your deployment completed successfully

1. Open your web browser, type http://diegomvc.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io/. Now you can see your .NET Page.

  ![diegomvc](./diegomvc.png "diegomvc")

## 7 Known Issues

1. You may hit below error when executing 'cf start diegoMVC'. Just retry it.

  ```
  $ cf start diegoMVC
  Could not fetch instance count: Server error, status code: 503, error code: 220002, message: Instances information unavailable: getaddrinfo: No address associated with hostname
  ```