# Push your first application to Cloud Foundry on Azure

>**NOTE:** You can choose to install Cloud Foundry command line interface (cf CLI) on Windows, Mac OS X or Linux. As an example, the following demo is pushed from the dev-box.

1. Log on to your dev-box

1. Login Cloud Foundry

    ```
    ./login_cloud_foundry.sh
    ```

1. Create your space

    ```
    cf create-space azure
    cf target -s azure
    ```

1. Download a demo application

    ```
    git clone https://github.com/bingosummer/2048
    ```

1. Push the application

    ```
    cd 2048
    cf push
    ```

    You can get the url (like `http://game-2048.CLOUD_FOUNDRY_PUBLIC_IP.xip.io/`) of the application.

1. Open the url in your favorite browser.
