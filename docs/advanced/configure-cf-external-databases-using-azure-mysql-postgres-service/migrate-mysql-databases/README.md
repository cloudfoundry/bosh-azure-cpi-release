# Migrate Cloud Foundry MySQL databases to Azure Database for MySQL

On Cloud Foundry (CF), it is recommended to use PAAS service for the purpose of high availability. [Azure Database for MySQL](https://azure.microsoft.com/en-us/services/mysql/) is one of services that CF can levege for HA. 

For a new deployment, you can refer to this [guidance](../README.md) to use Azure Database for MySQL as external databases.
For an existed deployment, if you want to use Azure Database for MySQL, this document will provide a simple guildance to migrate the database.

**NOTE:** Be careful on operating databases, you should practise on a test environment before officially do the migration on your production environment.

In this guidance, we will use `mysqldump` and `mysql` command-lines to dump backup files from internal databases and then retore them to Azure Databases for MySQL.

1. Figure out databases to be migrated

    Check your CF manifest carefully, find out which databases are used. Write down database name, user, password for  step `Migrate databases`. If you are using Ops Manager, follow this [guid](https://docs.pivotal.io/pivotalcf/2-2/customizing/credentials.html) to get credentials.
    
    Here is a list sample of the databases used in CF.
    ```
        +----------------------+
        | Database             |
        +----------------------+
        | cloud_controller     |
        | diego                |
        | locket               |
        | network_connectivity |
        | network_policy       |
        | routing-api          |
        | uaa                  |
        +----------------------+
    ```

1. Prepare Azure Database for MySQL

    * Follow guidance on this [link](../README.md#prepare-azure-mysqlpostgres-database), please remember to turn on `Allow access to Azure services` and Disable `Enforce SSL connection in Azure MySQL`.
    * Follow guidance on this [link](../README.md#create-the-databases) to create releated databases.

1. Stop CC VMs

    * Turn off bosh resurrector (`bosh -e azure -d cf  update-resurrection off`)
    * On Azure portal, stop all the CC VM jobs (Cloud Controller, Cloud Controller Worker, and Clock Global). Note that your CF API services will stop being available at this point (running apps should continue to be available though)
    * `bosh cck` the cf deployment to check for any errors with the bosh state. It should ask you if you want to delete references to the missing CC jobs, which you want to do.

1. Migrate databases

    For each database, you need to dump the database and then restore it manually. For example, let us say the VM that hosts the databases is `10.0.0.7`, you can use the commands below to migrate `cloud_controller`:

    ```
    mysqldump -u cloud_controller -p cloud_controller -h 10.0.16.7 --single-transaction > cloud_controller.sql

    mysql -u username@example -p -h example.mysql.database.azure.com cloud_controller < cloud_controller.sql
    ```

    Do the same thing for other databases.
    
    You can also refer to this [document](https://docs.microsoft.com/en-us/azure/mysql/concepts-migrate-dump-restore) for detail guidance of migrating a database.

    > Migration Tool:
    >> To reduce typewriting in the migration, a tool is added to this directory. Please see [migrate-mysql-databases.rb](./migrate-mysql-databases.rb) and [manifest-example.yml](./manifest-example.yml).
    >>
    >>You can download the scripts, edit manifest accordingly, and run `ruby migrate-mysql-databases.rb manifest-example.yml` to get all your databases migrated. The tool will try to create the database if it does not exist, so it is not a must to create it manually in `Prepare Azure Database for MySQL` when using these scripts.

1. Re-deploy Cloud Foundry

    Once the database migration is done, you can change your Cloud Foundry to use the Azure Database you have created.

    Refer to [Deploy Cloud Foundry](../README.md#deploy-cloud-foundry) for how to deploy CF with external databases. 
    **Note:** In the guidance, with operation file `use-external-dbs.yml`, the database VM will be deleted. If you want to (and you should) keep the database VM for a while, remember to comment out the `Remove` sections: 
    ```
    ## Remove MySQL
    #- type: remove
    #path: /instance_groups/name=database
    #- type: remove
    #path: /releases/name=cf-mysql
    #
    ## Remove MySQL variables
    #- type: remove
    #path: /variables/name=cf_mysql_mysql_admin_password
    #- type: remove
    #path: /variables/name=cf_mysql_mysql_cluster_health_password
    #- type: remove
    #path: /variables/name=cf_mysql_mysql_galera_healthcheck_endpoint_password
    #- type: remove
    #path: /variables/name=cf_mysql_mysql_galera_healthcheck_password
    #- type: remove
    #path: /variables/name=cf_mysql_proxy_api_password
    #- type: remove
    #path: /variables/name=network_policy_database_password
    #- type: remove
    #path: /variables/name=network_connectivity_database_password
    #- type: remove
    #path: /variables/name=routing_api_database_password
    #- type: remove
    #path: /variables/name=locket_database_password
    ```

    After this deploy is finished, your CF API service availibility will resume.

1. Check Cloud Foundry and then turn on bosh resurrector accordingly
