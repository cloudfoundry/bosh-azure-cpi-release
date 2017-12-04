## Development

### Before you start:

# Install GO (used by the vendoring direnv):
Please install [GO](https://golang.org/dl/).

  ```bash
  mkdir ~/workspace ~/go
  cd ~/workspace
  wget https://storage.googleapis.com/golang/go1.9.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf go1.9.linux-amd64.tar.gz
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
  echo 'export GOPATH=$HOME/go' >> ~/.bashrc
  exec $SHELL
  ```

# Install direnv
Please install [direnv](https://github.com/direnv/direnv#from-source).

  ```bash
  mkdir -p $GOPATH/src/github.com/direnv
  git clone https://github.com/direnv/direnv.git $GOPATH/src/github.com/direnv/direnv
  pushd $GOPATH/src/github.com/direnv/direnv
    make
    sudo make install
  popd
  echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
  exec $SHELL
  ```

  **NOTE**: You may need to use `direnv allow .` in the root directory of `bosh-azure-cpi-release`.

# Install ruby
Please make sure you have installed ruby 2.4.2 before you start. Below commands are tested in Ubuntu 14.04 LTS.

  ```bash
  # Install ruby 2.4.2 with chruby
  sudo apt-get update
  sudo apt-get install -y git gcc make libssl-dev libreadline-dev zlib1g-dev

  cd ~/workspace
  wget -O chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
  tar -xzvf chruby-0.3.9.tar.gz
  pushd chruby-0.3.9/
    sudo make install
    echo 'source /usr/local/share/chruby/chruby.sh' >> ~/.bashrc
  popd
  exec $SHELL

  wget -O ruby-install-0.6.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.6.1.tar.gz
  tar -xzvf ruby-install-0.6.1.tar.gz
  pushd ruby-install-0.6.1/
    sudo make install
  popd

  ruby-install ruby 2.4.2
  exec $SHELL
  chruby 2.4.2
  ruby -v
  ```

### Install Ruby gem Bundler (used by the vendoring script):

  ```bash
  chruby 2.4.2
  ruby -v

  gem install bundler
  ```

### Run vendoring script

With bundler installed, switch to `./src/bosh_azure_cpi` and run:

  ```bash
  chruby 2.4.2
  ruby -v

  # Assume that you have cloned https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git into ~/workspace/bosh-azure-cpi-release
  cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi
  ./vendor_gems
  ```

### Run unittests script

  ```bash
  cd ~/workspace/bosh-azure-cpi-release/src/bosh_azure_cpi
  ./bin/test-unit
  ```

### Create the BOSH release:

  ```bash
  chruby 2.4.2
  ruby -v

  gem install bosh_cli
  # Assume that you have cloned https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git into ~/workspace/bosh-azure-cpi-release
  cd ~/workspace/bosh-azure-cpi-release
  bosh create release --force --with-tarball --name bosh-azure-cpi
  ```

The release is now ready for use. If everything works, commit the changes including the updated gems.

At the end of the CLI output there will be "Release tarball" path.

## Test Interfaces
After you change the CPI code, you can use `bosh_azure_console` to test your changes. Below commands are tested in Ubuntu 14.04 LTS.

  ```bash
  cd ~/workspace
  chruby 2.4.2
  ruby -v

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
  sed -i -e '23s/^/#/' ~/.gem/ruby/2.4.2/gems/bosh-registry-1.3262.24.0/lib/bosh/registry.rb

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
  cpi.azure_client2.get_resource_group
  cpi.disk_manager2.has_disk?('bosh-disk-a')
  ```

Below is an example you can type in `bosh_azure_console` to test fake light stemcells.

  ```ruby
  begin
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
    stemcell_id = cpi.create_stemcell('', stemcell_properties)
    agent_id = 'abel-test-light-stemcell'
    resource_pool = JSON('{"instance_type":"Standard_F1"}')
    networks = JSON('{"private":{"cloud_properties":{"subnet_name":"Bosh","virtual_network_name":"boshvnet-crp"},"default":["dns","gateway"],"dns":["168.63.129.16","8.8.8.8"],"gateway":"10.0.0.1","ip":"10.0.0.4","netmask":"255.255.255.0","type":"manual"}}')
    instance_id = cpi.create_vm(agent_id, stemcell_id, resource_pool, networks)
    cpi.delete_vm(instance_id)
  ensure
    cpi.delete_stemcell(stemcell_id)
  end
  ```
