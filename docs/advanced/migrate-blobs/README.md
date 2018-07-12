# Migrate Cloud Foundry blobs from an NFS blobstore to an Azure Storage blobstore

[`goblob`](https://github.com/pivotal-cf/goblob) is a tool for migrating Cloud Foundry blobs from one blobstore to another. Presently it only supports migrating from an NFS blobstore to an S3-compatible one. [Minio Gateway](https://docs.minio.io/docs/minio-gateway-for-azure.html) adds S3 compatibility to Azure Blob Storage. With these two tools, you can refer to the following steps to migrate blobs from an NFS blobstore to an Azure Storage blobstore. But for a production environment, you need to ask for help from Pivotal support.

1. SSH into your NFS blobstore VM.

    ```
    bosh -e <alias> -d cf ssh singleton-blobstore
    ```

    All the following commands are running in your NFS blobstore VM.

1. Install [goblob](https://github.com/pivotal-cf/goblob).

    ```
    wget https://github.com/pivotal-cf/goblob/releases/download/v1.4.0/goblob-linux
    chmod +x goblob-linux
    sudo mv goblob-linux /usr/local/bin/goblob
    ```

1. Install [minio](https://github.com/minio/minio).

    ```
    wget https://dl.minio.io/server/minio/release/linux-amd64/minio
    chmod +x minio
    sudo mv minio /usr/local/bin/
    ```

1. Start Minio server in one terminal.

    ```
    export MINIO_ACCESS_KEY=<storage-account-name>
    export MINIO_SECRET_KEY=<storage-account-key>
    minio gateway azure
    ```

1. Migrate blobs in another terminal.

    ```
    goblob migrate --blobstore-path /var/vcap/store/shared --s3-accesskey=<storage-account-name> --s3-secretkey=<storage-account-key> --s3-endpoint=http://127.0.0.1:9000 --use-multipart-uploads
    ```

    If it fails to migrate several blobs, you can run the above command multiple times until all the blobs are migrated.

1. You need to follow [Post-migration Tasks](https://github.com/pivotal-cf/goblob#post-migration-tasks) and [Removing NFS post-migration](https://github.com/pivotal-cf/goblob#removing-nfs-post-migration).
