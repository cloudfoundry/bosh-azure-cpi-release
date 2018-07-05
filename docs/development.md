# Development

>NOTE: Below commands are tested in Ubuntu 16.04 LTS.

## Prepare the development environment

1. Install dependencies

    ```bash
    sudo apt-get update
    sudo apt-get install -y git gcc make libssl-dev libreadline-dev zlib1g-dev
    ```

1. Create the workspace directory

    ```bash
    mkdir ~/workspace
    ```

1. Install GO (used by the vendoring direnv):

    Please install [GO](https://golang.org/dl/).

    ```bash
    cd ~/workspace
    wget https://dl.google.com/go/go1.9.3.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.9.3.linux-amd64.tar.gz
    rm go1.9.3.linux-amd64.tar.gz
    mkdir ~/go
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    echo 'export GOPATH=$HOME/go' >> ~/.profile
    source ~/.profile
    ```

1. Install direnv

    Please install [direnv](https://github.com/direnv/direnv#from-source).

    ```bash
    mkdir -p $GOPATH/src/github.com/direnv
    git clone https://github.com/direnv/direnv.git $GOPATH/src/github.com/direnv/direnv
    pushd $GOPATH/src/github.com/direnv/direnv
      make
      sudo make install
    popd
    echo 'eval "$(direnv hook bash)"' >> ~/.profile
    source ~/.profile
    ```

1. Install ruby

    Please make sure you have installed ruby `2.4.4` before you start.

    ```bash
    cd ~/workspace
    wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz
    pushd chruby-0.3.9/
      sudo make install
      echo 'source /usr/local/share/chruby/chruby.sh' >> ~/.profile
    popd
    source ~/.profile

    wget -O ruby-install-0.6.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.6.1.tar.gz
    tar -xzvf ruby-install-0.6.1.tar.gz
    pushd ruby-install-0.6.1/
      sudo make install
    popd

    ruby-install ruby 2.4.4
    echo 'chruby 2.4.4' >> ~/.profile
    source ~/.profile
    ruby -v
    ```

1. Install bundler (used by the vendoring script)

    ```bash
    gem install bundler
    ```

1. Clone Azure CPI repository

    ```bash
    cd ~/workspace
    git clone https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release
    cd bosh-azure-cpi-release/
    direnv allow
    ```

1. Run vendoring script

    With bundler installed, switch to `./src/bosh_azure_cpi` and run:

    ```bash
    cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi
    ./vendor_gems
    ```

Your development environment is prepared successfully.

## Run Tests

### Unit tests

The [unit tests](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/tree/master/src/bosh_azure_cpi/spec/unit) are **REQUIRED** before you submit a PR. When submitting a PR, you need to provide the test coverage and make sure that the coverage doesn't decrease.

```bash
cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi
./bin/test-unit
```

If unit tests are passed, you can create a dev release and deploy it for tests.

### CI Pipeline

You can setup a [CI pipeline](../ci/) to run the [integration tests](https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release/tree/master/src/bosh_azure_cpi/spec/integration) and [BATs](https://github.com/cloudfoundry/bosh-acceptance-tests/tree/gocli-bats). It's optional for submitting a PR and required for publishing a new CPI release.

### Test CPI methods

You can use `bosh_azure_console` to test your code changes quickly.

  ```bash
  cd ~/workspace

  # Install postgres which bosh-registry depends on
  sudo apt-get install -y postgresql postgresql-contrib libpq-dev g++ libmysqlclient-dev libsqlite3-dev

  # Create database and user
  cat > ~/workspace/create_db.sql <<EOS
  CREATE USER test WITH PASSWORD 'test';
  CREATE DATABASE testdb;
  GRANT ALL PRIVILEGES ON DATABASE testdb to test;
  EOS
  sudo su postgres
  psql -f create_db.sql
  exit

  # Install bosh-registry which CPI depends on
  gem install bundle --no-ri --no-rdoc
  gem install bosh-registry --version 1.3262.24.0 --no-ri --no-rdoc
  gem install pg --version 0.20.0 --no-ri --no-rdoc

  # Workaround for the issue https://github.com/cloudfoundry/bosh/issues/1621
  sed -i -e '23s/^/#/' ~/.gem/ruby/2.4.4/gems/bosh-registry-1.3262.24.0/lib/bosh/registry.rb

  cat > ~/workspace/registry.cfg <<EOS
  ---
  loglevel: debug

  http:
    port: 25695
    user: admin
    password: admin

  db:
    adapter: postgres
    max_connections: 32
    pool_timeout: 10
    host: 127.0.0.1
    database: testdb
    user: test
    password: test
  EOS

  # Prepare database for bosh-registry
  bosh-registry-migrate -c ~/workspace/registry.cfg

  # Assume that you have cloned https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git into ~/workspace/bosh-azure-cpi-release
  cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi
  bundle install

  # Please replace xxx with your credentials.
  cat > ~/workspace/cpi.cfg <<EOS
  ---
  azure:
    environment: AzureCloud
    subscription_id: xxx
    storage_account_name: xxx
    resource_group_name: xxx
    tenant_id: xxx
    client_id: xxx
    client_secret: 'xxx'
    ssh_user: vcap
    ssh_public_key: ssh-rsa xxx
    default_security_group: nsg-bosh
    debug_mode: false
    use_managed_disks: false
  registry:
    endpoint: http://127.0.0.1:25695
    user: admin
    password: admin
  EOS
  ```

You can use `tmux` to create two consoles. Start `bosh-registry` in one console and `bosh_azure_console` in another console.

Console 1:

  ```bash
  bosh-registry -c ~/workspace/registry.cfg
  ```

Console 2:

  ```bash
  cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi/bin
  ./bosh_azure_console -c ~/workspace/cpi.cfg
  ```

Examples:

  ```ruby
  # Test the mehodes in azure_client2.rb
  cpi.azure_client2.get_resource_group('fake-resource-group-name')

  # Test disk_manager2.rb
  cpi.disk_manager2.has_disk?('fake-resource-group-name', 'bosh-disk-a')

  # Test the CPI method create_stemcell
  stemcell_properties = {
    "name" => "fake-name",
    "version" => "fake-version",
    "infrastructure" => "azure",
    "hypervisor" => "hyperv",
    "disk" => "30720",
    "disk_format" => "vhd",
    "container_format" => "bare",
    "os_type" => "linux",
    "os_distro" => "ubuntu",
    "architecture" => "x86_64",
    "image" => {"publisher"=>"Canonical", "offer"=>"UbuntuServer", "sku"=>"16.04-LTS", "version"=>"16.04.201611220"}
  }
  cpi.create_stemcell('', stemcell_properties)

  # Test create_vm with a valid stemcell_id
  agent_id = "<GUID>"
  stemcell_id = "<a-valid-stemcell-id>"
  resource_pool = JSON('{"instance_type":"Standard_F1"}')
  networks = JSON('{"private":{"cloud_properties":{"subnet_name":"Bosh","virtual_network_name":"boshvnet-crp"},"default":["dns","gateway"],"dns":["168.63.129.16","8.8.8.8"],"gateway":"10.0.0.1","ip":"10.0.0.42","netmask":"255.255.255.0","type":"manual"}}')
  instance_id = cpi.create_vm(agent_id, stemcell_id, resource_pool, networks)
  ```

## Create a dev release

Follow the [guidance](http://bosh.io/docs/cli-v2.html) to install the latest version of BOSH CLI v2.

**NOTE**: BOSH CLI `v2.0.36+` is required for [`bosh vendor-package`](https://bosh.io/docs/package-vendoring.html).

```bash
cd ~/workspace/bosh-azure-cpi-release
cpi_dev_version=35.0.1.dev
bosh create-release --name=bosh-azure-cpi --version=${cpi_dev_version} --tarball=/tmp/bosh-azure-cpi-release-${cpi_dev_version}.tgz
```

The release is now ready for use. If everything works, commit the changes including the updated gems.
