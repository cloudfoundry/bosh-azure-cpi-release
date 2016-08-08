# Update your Cloud Foundry to use Diego on Azure

Cloud Foundry has used two architectures for managing application containers: Droplet Execution Agents (DEA) and Diego.
With the DEA architecture, the Cloud Controller schedules and manages applications on the DEA nodes. 
In the Diego architecture, Diego components replace the DEAs and the Health Manager (HM9000), and assume application scheduling and management responsibility from the Cloud Controller.

This document describes the steps to update your Cloud Foundry to use Diego as default architecture on Azure.

>**NOTE:** If you have deployed your Cloud Foundry by following the latest [guidance](../../guidance.md) via ARM templates on Azure, you already have Diego as default architecture, and don't need to follow this guide.

## 1 Prerequisites

* A deployment of BOSH

  It is assumed that you have already deployed your **BOSH director VM** on Azure by following the [guidance](../../guidance.md) via ARM templates.

* Manifests

  It is assumed that you have manifests for Cloud Foundry which use DEA as default architecture. Prior to commit [604a163](https://github.com/Azure/azure-quickstart-templates/commit/604a1634126646ba83c9e98e6b50b10019183168), the templates use DEA as default architecture, you will learn how to switch to Diego-default in this guide. Here we take multiple-vm-cf.yml as an example.

## 2 Update manifest and deploy Cloud Foundry with Diego

1. Update manifest.

  * Change for DEA nodes

    * If you want to keep DEA nodes, just keep the original manifest as what it is and go ahead to `Change for Diego`

      _You may want to migrate DEA applications to Diego, please refer to [guide](https://docs.cloudfoundry.org/adminguide/apps-enable-diego.html) to do migration after the deployment is done._

    * If you want to remove DEA nodes, remove DEA and hm9000 related configuration out of the manifest

      * remove jobs.hm9000_z1 and jobs.runner_z1

        ```
        - name: hm9000_z1
          instances: 1
          resource_pool: resource_z1
          ...
        ```

        ```
        - name: runner_z1
          instances: 1
          resource_pool: resource_z1
          ...
        ```
      * remove properties.dea_next and properties.hm9000

        ```
        dea_next:
          advertise_interval_in_seconds: 5
          heartbeat_interval_in_seconds: 10
          memory_mb: 33996
          enable_ssl: true
          ...
        ```

        ```
        hm9000:
          url: https://hm9000.REPLACE_WITH_SYSTEM_DOMAIN
          port: 5155
          ...
        ```

  * Change for Diego

    >**NOTE:** The versions and job specs below could be different in your environment, depending on which version of cf-release / diego-release you are using and how you deploy your Cloud Foundry.

    * Add Diego related releases. Example:

      ```yaml
      releases:
      - {name: diego, version: 0.1476.0}
      - {name: garden-linux, version: 0.338.0}
      - {name: cflinuxfs2-rootfs , version: 1.16.0}
      ```

    * Add Diego related jobs. Example:

      ```yaml
      jobs:
      - name: database_z1
        instances: 1
        templates:
        - name: consul_agent
          release: cf
        - name: etcd
          release: cf
        - name: bbs
          release: diego
        - name: metron_agent
          release: cf
        persistent_disk: 20480
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: true
          max_in_flight: 1
        properties:
          consul:
            agent:
              services:
                etcd: {}
          metron_agent:
            zone: z1
      - name: brain_z1
        instances: 1
        templates:
        - name: consul_agent
          release: cf
        - name: auctioneer
          release: diego
        - name: converger
          release: diego
        - name: metron_agent
          release: cf
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: true
          max_in_flight: 1
        properties:
          metron_agent:
            zone: z1
      - name: cell_z1
        instances: 2
        templates:
        - name: consul_agent
          release: cf
        - name: rep
          release: diego
        - name: garden
          release: garden-linux
        - name: cflinuxfs2-rootfs-setup
          release: cflinuxfs2-rootfs
        - name: metron_agent
          release: cf
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: false
          max_in_flight: 1
        properties:
          metron_agent:
            zone: z1
          diego:
            rep:
              zone: z1
      - name: cc_bridge_z1
        instances: 1
        templates:
        - name: consul_agent
          release: cf
        - name: stager
          release: cf
        - name: nsync
          release: cf
        - name: tps
          release: cf
        - name: cc_uploader
          release: cf
        - name: metron_agent
          release: cf
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: false
          max_in_flight: 1
        properties:
          metron_agent:
            zone: z1
      - name: access_z1
        instances: 1
        templates:
        - name: consul_agent
          release: cf
        - name: ssh_proxy
          release: diego
        - name: metron_agent
          release: cf
        - name: file_server
          release: diego
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: false
          max_in_flight: 1
        properties:
          metron_agent:
            zone: z1
      - name: route_emitter_z1
        instances: 1
        templates:
        - name: consul_agent
          release: cf
        - name: route_emitter
          release: diego
        - name: metron_agent
          release: cf
        resource_pool: resource_z1
        networks:
          - name: cf_private
        update:
          serial: false
          max_in_flight: 1
        properties:
          metron_agent:
            zone: z1
      ```

  * Add diego properties. Example:

    ```yaml
    properties:
      capi:
        nsync:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          cc:
            base_url: https://api.REPLACE_WITH_SYSTEM_DOMAIN
            basic_auth_password: REPLACE_WITH_PASSWORD
        tps:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          cc:
            base_url: https://api.REPLACE_WITH_SYSTEM_DOMAIN
            basic_auth_password: REPLACE_WITH_PASSWORD
          traffic_controller_url: wss://doppler.REPLACE_WITH_SYSTEM_DOMAIN:443
        tps_listener:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          cc:
            base_url: https://api.REPLACE_WITH_SYSTEM_DOMAIN
            basic_auth_password: REPLACE_WITH_PASSWORD
        stager:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          cc:
            base_url: https://api.REPLACE_WITH_SYSTEM_DOMAIN
            basic_auth_password: REPLACE_WITH_PASSWORD
      diego:
        auctioneer:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
        bbs:
          active_key_label: active
          encryption_keys:
          - label: active
            passphrase: REPLACE_WITH_PASSWORD
          ca_cert: ""
          etcd:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          require_ssl: false
          server_cert: ""
          server_key: ""
        converger:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
        rep:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          preloaded_rootfses: ["cflinuxfs2:/var/vcap/packages/cflinuxfs2/rootfs"]
        route_emitter:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          nats:
            machines: [REPLACE_WITH_NATS_IP]
            password: REPLACE_WITH_PASSWORD
            port: 4222
            user: nats
        ssl:
          skip_cert_verify: true
        ssh_proxy:
          bbs:
            ca_cert: ""
            client_cert: ""
            client_key: ""
            require_ssl: false
          enable_cf_auth: true
          enable_diego_auth: false
          host_key: |
            REPLACE_WITH_SSH_HOST_KEY
          uaa_secret: REPLACE_WITH_PASSWORD
          uaa_token_url: https://uaa.REPLACE_WITH_SYSTEM_DOMAIN/oauth/token
    ```

    * Remember to change the REPLACE\_WITH* to proper values in your manifest

    * For production, you should use your certs and keys to set above ca_cert, client_cert and client_key. And You should set 'ssl.skip_cert_verify' to false and set 'require_ssl' to true.  For cert configuration, please refer to this [guide](https://github.com/cloudfoundry/diego-release/blob/develop/docs/tls-configuration.md); for additional changes when ssl is enabled, please refer to documents and job specs in [diego-release](https://github.com/cloudfoundry/diego-release/).

  * Add properties.hm9000.port. (In cf-release v238, even if hm9000 is not used, properties.hm9000.port is still requred.) Example:

    ```yaml
    properties:
      hm9000:
        port: 5525
    ```

  * Add (change) properties.cc.default_to_diego_backend as true. This value will make Diego as default backend.

    ```yaml
    properties:
      cc:
        default_to_diego_backend: true
    ```

1. Deploy

  * Log on to your dev-box and login to your BOSH director VM. Example:

    ```
    bosh target 10.0.0.4
    ```

  * Upload addition Diego releases besides cf-release and stemcell. Example:

    ```
    bosh upload stemcell https://bosh.io/d/stemcells/bosh-azure-hyperv-ubuntu-trusty-go_agent?v=3232.11 --sha1 575a284a3e314a5e1dc78fed8ff73e8a1da9b78b --skip-if-exists
    bosh upload release https://bosh.io/d/github.com/cloudfoundry/cf-release?v=238 --sha1 fa6d35300f4fcd74a75fd8c7138f592acfcb32b0 --skip-if-exists
    bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/diego-release?v=0.1476.0 --sha1 4b66fde250472e47eb2a0151bb676fc1be840f47 --skip-if-exists
    bosh upload release https://bosh.io/d/github.com/cloudfoundry-incubator/garden-linux-release?v=0.338.0 --sha1 432225d88edc9731be4453cb61eba33fa829ebdc --skip-if-exists
    bosh upload release https://bosh.io/d/github.com/cloudfoundry/cflinuxfs2-rootfs-release?v=1.16.0 --sha1 acfa1c4aad1fa9ef4623bf189cbab788a53f678e --skip-if-exists
    ```

  * deploy

    ```
    bosh deployment ~/example_manifests/multiple-vm-cf.yml
    bosh -n deploy
    ```


## 3 Push your first application to Diego

1. Log on to your dev-box

1. Install CF CLI and the plugin

    ```
    wget -O cf.deb http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.14.1/cf-cli-installer_6.14.1_x86-64.deb
    sudo dpkg -i cf.deb
    ```

1. Configure your space. Example:

    ```
    cf login -a https://api.REPLACE_WITH_CLOUD_FOUNDRY_PUBLIC_IP.xip.io --skip-ssl-validation -u admin -p REPLACE_WITH_PASSWORD
    cf create-org diego
    cf target -o diego
    cf create-space diego
    cf target -s diego
    ```

1. Download a demo application and extract it. Example:

    ```
    sudo apt-get -y install git
    git clone https://github.com/bingosummer/2048
    ```

1. Push the application. Example:

    ```
    cd 2048
    cf push
    ```

1. Check whether the application is running on Diego, you can ssh into the running container for a check.

    ```
    cf ssh game-2048
    ```