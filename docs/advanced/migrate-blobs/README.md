# Migrate Cloud Foundry blobs from an NFS blobstore to an Azure Storage blobstore

[goblob](https://github.com/pivotal-cf/goblob) is a tool for migrating Cloud Foundry blobs from one blobstore to another. You can refer to the following steps to migrate blobs from an NFS blobstore to an Azure Storage blobstore. But for a production environment, you need to ask for help from Pivotal support.

1. SSH into your NFS blobstore VM.

    ```
    bosh -e <alias> -d cf ssh singleton-blobstore
    ```

    All the following commands are running in your NFS blobstore VM.

1. Install [goblob](https://github.com/pivotal-cf/goblob).

    `goblob` supports migrating NFS blobstore to Azure blob store since this [PR](https://github.com/pivotal-cf/goblob/pull/5), you can follow this guide to install it from source.

    * Install git

        ```
        sudo apt-get install git
        ```

    * Install [go](https://golang.org/)

        ```
        wget https://dl.google.com/go/go1.11.linux-amd64.tar.gz
        sudo tar -C /usr/local -xzf go1.11.linux-amd64.tar.gz
        mkdir -p go/bin
        export PATH=$PATH:/usr/local/go/bin:~/go/bin
        export GOPATH=~/go
        ```

    * Install [glide](https://github.com/masterminds/glide)

        ```
        curl https://glide.sh/get | sh
        ```

    * Build and install goblob

        ```
        git clone https://github.com/pivotal-cf/goblob.git $GOPATH/src/github.com/pivotal-cf/goblob
        cd $GOPATH/src/github.com/pivotal-cf/goblob
        glide install
        GOARCH=amd64 GOOS=linux go install github.com/pivotal-cf/goblob/cmd/goblob
        ```

1. Migrate blobs

    Example:

    ```
    goblob migrate2azure --blobstore-path /var/vcap/store/shared \
    --azure-storage-account $storage_account_name \
    --azure-storage-account-key $storage_account_key \
    --cloud-name AzureCloud \
    --buildpacks-bucket-name cf-buildpacks \
    --droplets-bucket-name cf-droplets \
    --packages-bucket-name cf-packages \
    --resources-bucket-name cf-resources
    ```

1. You need to follow [Post-migration Tasks](https://github.com/pivotal-cf/goblob#post-migration-tasks) and [Removing NFS post-migration](https://github.com/pivotal-cf/goblob#removing-nfs-post-migration).
