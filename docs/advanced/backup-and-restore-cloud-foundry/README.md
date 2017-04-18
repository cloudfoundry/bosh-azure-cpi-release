# Backup and restore Cloud Foundry

This topic describes the procedure for manually backing up each critical backend Cloud Foundry component. We recommend frequently backing up your installation settings before making any changes to your CF deployment, such as the BOSH Deployment Manifest.

To back up a deployment, you need to backup the BOSH Deployment Manifest, temporarily stop the Cloud Controller, create and export backup files for each critical backend component, and start the Cloud Controller.

To restore a deployment, you must temporarily stop the Cloud Controller, restore the state of each critical backend component from its backup file, and start the Cloud Controller.

## Back Up Critical Backend Components

Your CF deployment contains several critical data stores that must be present for a complete restore. This section describes the procedure for backing up the databases and the servers associated with your CF installation.

You must back up each of the following:

* Cloud Controller Database
* UAA Database
* Diego Database
* BlobStores

>**Note**: If you are running PostgreSQL and are on the default internal databases, follow the instructions below. If you are running your databases or filestores externally, disregard instructions for backing up the Cloud Controller, and UAA Databases, and ensure that you back up your external databases and filestores.

### Backup the BOSH Deployment Manifest

1. Run `bosh deployments` to get the deployment name. For example:

    ```
    $ bosh deployments
    Acting as user 'admin' on 'bosh'
    
    +-------------------+--------------------------+--------------------------------------------------+--------------+
    | Name              | Release(s)               | Stemcell(s)                                      | Cloud Config |
    +-------------------+--------------------------+--------------------------------------------------+--------------+
    | multiple-vm-azure | cf/250                   | bosh-azure-hyperv-ubuntu-trusty-go_agent/3363.14 | none         |
    |                   | cflinuxfs2-rootfs/1.44.0 |                                                  |              |
    |                   | diego/1.4.1              |                                                  |              |
    |                   | garden-runc/1.0.4        |                                                  |              |
    +-------------------+--------------------------+--------------------------------------------------+--------------+
    
    Deployments total: 1
    ```

1. Run `bosh download manifest multiple-vm-azure backup.yml` to backup the manifest.

### Stop Cloud Controller

1. Run `bosh vms` to view a list of VMs in your CF deployment.

    ```
    $ bosh vms
    Acting as user 'admin' on 'bosh'
    Deployment `multiple-vm-azure'

    Director task 116

    Task 116 done

    +---------------------------------------------------------------------------+---------+-----+-----------+--------------+
    | VM                                                                        | State   | AZ  | VM Type   | IPs          |
    +---------------------------------------------------------------------------+---------+-----+-----------+--------------+
    | api_worker_z1/0 (58394684-5108-4f03-ada8-8e7c98728843)                    | running | n/a | small_z1  | 10.0.16.105  |
    | api_z1/0 (4ae21c91-4421-489d-a696-5a46106d54cc)                           | running | n/a | medium_z1 | 10.0.16.103  |
    | clock_global/0 (6b0922a2-704c-4040-85f0-12db46b02175)                     | running | n/a | small_z1  | 10.0.16.104  |
    | consul_z1/0 (69bf3102-3c3c-48e0-b5ce-6e5e9ebe86a8)                        | running | n/a | small_z1  | 10.0.16.16   |
    | doppler_z1/0 (68e0b486-f09b-4ff2-b076-d42e1b7ec327)                       | running | n/a | small_z1  | 10.0.16.107  |
    | etcd_z1/0 (f6e7d97d-e648-4ffe-8bb9-6e0cd734e969)                          | running | n/a | small_z1  | 10.0.16.12   |
    | ha_proxy_z1/0 (da19821d-c794-494f-b98e-605d745704c0)                      | running | n/a | router_z1 | 10.0.16.4    |
    |                                                                           |         |     |           | xx.xx.xx.xxx |
    | hm9000_z1/0 (9757bbd1-7b59-4eca-8e73-fdaeb9c1c435)                        | running | n/a | medium_z1 | 10.0.16.109  |
    | loggregator_trafficcontroller_z1/0 (fcba75b4-9fa9-47c3-8602-c6f53e6455bf) | running | n/a | small_z1  | 10.0.16.108  |
    | nats_z1/0 (e63841d4-a5d9-4f46-a8a6-9a8b17ead139)                          | running | n/a | small_z1  | 10.0.16.6    |
    | postgres_z1/0 (3dc6f251-48b5-4405-8571-06296e1f8e56)                      | running | n/a | medium_z1 | 10.0.16.8    |
    | router_z1/0 (ad880188-b9a0-4014-8f73-9d425ba415b5)                        | running | n/a | router_z1 | 10.0.16.9    |
    | runner_z1/0 (58592865-98da-4b27-9efc-5b9ec2146574)                        | running | n/a | runner_z1 | 10.0.16.106  |
    | stats_z1/0 (cbc3b521-5ae3-4427-a127-cbc0e7362c48)                         | running | n/a | small_z1  | 10.0.16.101  |
    | uaa_z1/0 (25078966-091a-4bae-ad10-ae7e09d463a4)                           | running | n/a | medium_z1 | 10.0.16.102  |
    +---------------------------------------------------------------------------+---------+-----+-----------+--------------+

    VMs total: 15
    ```

1. Run `bosh stop SELECTED-VM` for each Cloud Controller VM. For example, stop the `api_z1/0` and `api_worker_z1/0` VMs.

    ```
    $ bosh stop api_z1 --force
    $ bosh stop api_worker_z1 --force
    ```

Do not stop the `postgres_z1/0` VM, which is the backend database for Cloud Controller if you opted to use PostgreSQL in your database deployment.

### Back Up the Cloud Controller Database

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Run `pg_dump` to export the database:

    ```
    $ pg_dump -h localhost -U $USERNAME -p $PORT $DBNAME > /tmp/ccdb.sql
    ```
  
    You can find `$USERNAME`, `$PORT` and `$DBNAME` in the manifest. For example:
  
    ```
    $ pg_dump -h localhost -U ccadmin -p 5524 ccdb > /tmp/ccdb.sql
    ```
  
    By default, `pg_dump` is not installed. You need to install it using `sudo apt-get install postgresql-client`. If the versions of postgresql client and server don't match, you need to upgrade the version.
  
    For example, if the postgresql server version is `9.4` and the client version is `9.3`, you need to upgrade the client version to `9.4` using the following commands.
  
    ```
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" >> /etc/apt/sources.list.d/postgresql.list'
    sudo apt-get update
    sudo apt-get install postgresql-client-9.4
    ```

1. Exit from the `postgres_z1/0` VM.

1. Run bosh scp to copy the exported database to your BOSH client.

    ```
    $ bosh scp --download postgres_z1/0 /tmp/ccdb.sql .
    ```

    >NOTE: The database backup file is saved as `ccdb.sql.postgres_z1.0`.

### Back Up the UAA Database

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Run `pg_dump` to export the database:

    ```
    $ pg_dump -h localhost -U $USERNAME -p $PORT $DBNAME > /tmp/uaadb.sql
    ```

    You can find `$USERNAME`, `$PORT` and `$DBNAME` in the manifest. For example:

    ```
    $ pg_dump -h localhost -U uaaadmin -p 5524 uaadb > /tmp/uaa.sql
    ```

1. Exit from the `postgres_z1/0` VM.

1. Run `bosh scp` to copy the exported database to your BOSH client.

    ```
    $ bosh scp --download postgres_z1/0 /tmp/uaa.sql .
    ```

### Back Up the Diego Database

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Run `pg_dump` to export the database:

    ```
    $ pg_dump -h localhost -U $USERNAME -p $PORT $DBNAME > /tmp/diego.sql
    ```

    You can find `$USERNAME`, `$PORT` and `$DBNAME` in the manifest. For example:

    ```
    $ pg_dump -h localhost -U diego -p 5524 diego > /tmp/diego.sql
    ```

1. Exit from the `postgres_z1/0` VM.

1. Run `bosh scp` to copy the exported database to your BOSH client.

    ```
    $ bosh scp --download postgres_z1/0 /tmp/diego.sql .
    ```

### Back Up your blobstores

By default, [fog with azure storage](https://docs.cloudfoundry.org/deploying/common/cc-blobstore-config.html#fog-azure) is configured in the manifest as the blobstore.

You need to backup the blobs in the Azure storage account. Depending on where you want to backup your blobs, there are two options available:

* Backing up blobs locally

  If you wish to backup your data locally in your infrastructure, you could write your own application using either Storage Client Library(e.g. [Azure Storage Client Library for Ruby](https://github.com/Azure/azure-storage-ruby)) or consuming [REST API](https://docs.microsoft.com/en-us/rest/api/storageservices/fileservices/blob-service-rest-api).

* Backing up data in the cloud

  You can use [Asynchronous Copy Blob functionality](http://blogs.msdn.com/b/windowsazurestorage/archive/2012/06/12/introducing-asynchronous-cross-account-copy-blob.aspx) which will essentially allow you to copy data from one storage account to another storage account without downloading the data locally.

### Start Cloud Controller

Run `bosh start --force`.

## Restore Critical Backend Components

Your deployment contains several critical data stores that must be present for a complete restore. This section describes the procedure for restoring the databases and servers associated with your CF installation.

You must restore each of the following:

* Cloud Controller Database
* UAA Database
* Diego Database
* BlobStores

>**Note**: If you are running PostgreSQL and are on the default internal databases, follow the instructions below. If you are running your databases or filestores externally, disregard instructions for restoring the Cloud Controller and UAA Databases.

### Stop Cloud Controller

Same as the steps in the section of "Backup Critical Backend Components".

### Restore the Cloud Controller Database

1. Use `bosh scp --upload` to send the Cloud Controller Database backup file to the `postgres_z1/0` VM.

    ```
    $ bosh scp --upload postgres_z1/0 ccdb.sql.postgres_z1.0 /tmp/
    ```

    >NOTE: `ccdb.sql.postgres_z1.0` is the database backup file.

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Login the database with the psql client.

    ```
    psql -h localhost -U vcap -p 5524 ccdb
    ```

1. Drop the database schema and create a new one to replace it.

    ```
    ccdb=# drop schema public cascade;
    ccdb=# create schema public;
    ```

1. Restore the database from the backup file.

    ```
    $ psql -h localhost -U vcap -p 5524 ccdb < /tmp/ccdb.sql.postgres_z1.0
    ```

1. Exit from the `postgres_z1/0` VM.

### Restore UAA Database

1. Use `bosh scp --upload` to send the UAA Database backup file to the `postgres_z1/0` VM.

    ```
    $ bosh scp --upload postgres_z1/0 uaadb.sql.postgres_z1.0 /tmp/
    ```

    >NOTE: `uaa.sql.postgres_z1.0` is the database backup file.

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Login the database with the psql client.

    ```
    psql -h localhost -U vcap -p 5524 uaadb
    ```
  
1. Drop the database schema and create a new one to replace it.

    ```
    uaadb=# drop schema public cascade;
    uaadb=# create schema public;
    ```

1. Restore the database from the backup file.

    ```
    $ psql -h localhost -U vcap -p 5524 uaadb < /tmp/uaadb.sql.postgres_z1.0
  
    ```

1. Exit from the `postgres_z1/0` VM.

### Restore Diego Database

1. Use `bosh scp --upload` to send the Diego Database backup file to the `postgres_z1/0` VM.

    ```
    $ bosh scp --upload postgres_z1/0 diego.sql.postgres_z1.0 /tmp/
    ```

    >NOTE: `diego.sql.postgres_z1.0` is the database backup file.

1. Use `bosh ssh` to SSH into the `postgres_z1/0` VM.

1. Login the database with the psql client.

    ```
    psql -h localhost -U vcap -p 5524 diego
    ```

1. Drop the database schema and create a new one to replace it.

    ```
    diego=# drop schema public cascade;
    diego=# create schema public;
    ```

1. Restore the database from the backup file.

    ```
    $ psql -h localhost -U vcap -p 5524 diego < /tmp/diego.sql.postgres_z1.0
    ```

1. Exit from the `postgres_z1/0` VM.

### Restore BlobStores

Copy the blobs from the backup storage account or your local machine to your original storage account.

### Start Cloud Controller

Run `bosh start --force`.
