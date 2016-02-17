# Push your first application to Cloud Foundry on Azure

>**NOTE:** You can choose to install Cloud Foundry command line interface (cf CLI) on Windows, Mac OS X or Linux. As an example, the following demo is pushed from the dev-box.

## 1 Configure CF Environment

1. Log on to your dev-box

2. Install CF CLI and the plugin

  ```
  wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
  sudo dpkg -i cf.deb
  ```

3. Configure your space

  Run `cat ~/settings | grep cf-ip` to get Cloud Foundry public IP.

  ```
  cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u admin -p c1oudc0w
  cf create-space azure
  cf target -o "default_organization" -s "azure"
  ```

## 2 Push Your First Application

1. Log on to your dev-box

2. Download a demo application

  ```
  sudo apt-get -y install git
  git clone https://github.com/bingosummer/2048
  ```

3. Push the application

  ```
  cd 2048
  cf push
  ```

4. Open `http://game-2048.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io/` in your favorite browser.
