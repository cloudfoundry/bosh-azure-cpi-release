# Configure Cloud Foundry external databases using Azure MySQL/Postgres Service

Cloud Foundry uses CCDB, UAADB and other databases to store system data. To achieve high availability and scalability, you can use Azure MySQL or Azure PostgreSQL service for them. This document guides you through the steps to create the Azure database services and configures Cloud Foundry to utilize these external services. These steps can be applied during the initial deployment, or on top of existing deployment. 

For basic Cloud Foundry deployment steps, please check the section [**Get Started**](../../guidance.md#get-started).
 
## Prepare Azure MySQL/Postgres Database

1. Create [Azure database for MySQL](https://docs.microsoft.com/en-us/azure/mysql/quickstart-create-mysql-server-database-using-azure-portal#create-an-azure-database-for-mysql-server) or [Azure database for Postgres](https://docs.microsoft.com/en-us/azure/postgresql/quickstart-create-server-database-portal#create-an-azure-database-for-postgresql-server).

1. Turn on `Allow access to Azure services`.

1. Disable `Enforce SSL connection in Azure MySQL` or `Enforce SSL connection in Azure Postgres`.

1. Get the connection information of [Azure MySQL](https://docs.microsoft.com/en-us/azure/mysql/quickstart-create-mysql-server-database-using-azure-portal#get-the-connection-information) or [Azure Postgres](https://docs.microsoft.com/en-us/azure/postgresql/quickstart-create-server-database-portal#get-the-connection-information).

## Create the Databases

1. Connect to the [Azure MySQL server](https://docs.microsoft.com/en-us/azure/mysql/quickstart-create-mysql-server-database-using-azure-portal#connect-to-mysql-by-using-the-mysql-command-line-tool) or [Azure Postgres Server](https://docs.microsoft.com/en-us/azure/postgresql/quickstart-create-server-database-portal#connect-to-the-postgresql-database-by-using-psql-in-cloud-shell).

1. Create the databases for each of the following Cloud Foundry components: `cc`, `bbs`, `uaa`, `routing_api`, `policy_server`, `silk_controller` and `locket`. You can find this list in the [external database ops file](https://raw.githubusercontent.com/cloudfoundry/cf-deployment/v1.16.0/operations/use-external-dbs.yml). Please note down the database names, which will be used when deploying Cloud Foundry.

1. For Azure Postgres Service only, you need to install the [`citext` extension](https://docs.microsoft.com/en-us/azure/postgresql/concepts-extensions) to each database, by running the `CREATE EXTENSION` command from psql tool. Below is an example for loading the extension for CCDB.

    ```
    external_cc_database=> CREATE EXTENSION citext;
    CREATE EXTENSION
    external_cc_database=> \dx
                                         List of installed extensions
            Name        | Version |   Schema   |                        Description
    --------------------+---------+------------+-----------------------------------------------------------
     citext             | 1.3     | public     | data type for case-insensitive character strings
     pg_buffercache     | 1.2     | public     | examine the shared buffer cache
     pg_stat_statements | 1.4     | public     | track execution statistics of all SQL statements executed
     pgioc              | 1.0     | public     | Collector for IO related counters
     plpgsql            | 1.0     | pg_catalog | PL/pgSQL procedural language
    (5 rows)
    ```

## Deploy Cloud Foundry

1. Download the ops file of using external databases.

    ```
    wget https://raw.githubusercontent.com/cloudfoundry/cf-deployment/v1.16.0/operations/use-external-dbs.yml
    ```

1. Deploy cf-deployment with the external databases.

    Add the following lines to your `bosh -d cf deploy` command:

    ```
    -o use-external-dbs.yml \
    -v external_database_type=mysql \
    -v external_database_port=3306 \
    -v external_uaa_database_name=<external-uaa-database-name> \
    -v external_uaa_database_address=<fully-qualified-domain-name> \
    -v external_uaa_database_username="<user@server-name>" \
    -v external_uaa_database_password="<server-admin-password>" \
    -v external_cc_database_name=<external-cc-database-name> \
    -v external_cc_database_address=<fully-qualified-domain-name> \
    -v external_cc_database_username="<user%40server-name>" \
    -v external_cc_database_password="<server-admin-password>" \
    -v external_bbs_database_name=<external-bbs-database-name> \
    -v external_bbs_database_address=<fully-qualified-domain-name> \
    -v external_bbs_database_username="<user@server-name>" \
    -v external_bbs_database_password="<server-admin-password>" \
    -v external_routing_api_database_name=<external-routing-api-database-name> \
    -v external_routing_api_database_address=<fully-qualified-domain-name> \
    -v external_routing_api_database_username="<user@server-name>" \
    -v external_routing_api_database_password="<server-admin-password>" \
    -v external_policy_server_database_name=<external-policy-server-database-name> \
    -v external_policy_server_database_address=<fully-qualified-domain-name> \
    -v external_policy_server_database_username="<user@server-name>" \
    -v external_policy_server_database_password="<server-admin-password>" \
    -v external_silk_controller_database_name=<external-silk-controller-database-name> \
    -v external_silk_controller_database_address=<fully-qualified-domain-name> \
    -v external_silk_controller_database_username="<user@server-name>" \
    -v external_silk_controller_database_password="<server-admin-password>" \
    -v external_locket_database_name=<external-locket-database-name> \
    -v external_locket_database_address=<fully-qualified-domain-name> \
    -v external_locket_database_username="<user@server-name>" \
    -v external_locket_database_password="<server-admin-password>"
    ```

    For example, if `<server-name>` is `mydemoserver`, then `<fully-qualified-domain-name>` will be `mydemoserver.mysql.database.azure.com` for Azure MySQL.

    Known issue: In `<external-cc-database-username>`, `@` has to be encoded to `%40` so that the job `cloud_controller_ng` can connect to Azure database. After the [issue](https://github.com/cloudfoundry/capi-release/issues/79) is resolved, `<user@server-name>` can be used.

    If the Cloud Foundry deployment succeeds, then the external databases are connected to Cloud Foundry and working. You can run your Cloud Foundry smoke test now.
