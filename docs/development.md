## Development

### Before you start:

Please make sure you have installed ruby 2.1.0+ before you start. In the beginning of section `Test Interfaces` you will see how to install specific version of ruby with `rubyenv`. _FYI, the latest stable version of ruby is 2.4.1_

ruby2.0 is also required in the setup procedure. If you are using bosh devbox deployed with template in this [guidance](./get-started/via-arm-templates/deploy-bosh-via-arm-templates.md) or guidance from `bosh.io` [here](https://bosh.io/docs/init-azure.html), you should have ruby 2.0 installed already. Otherwise, please install it by:

```
sudo apt-get install -y ruby2.0
```


### Install Ruby gem Bundler (used by the vendoring script):

```
gem install bundler
```

### Run vendoring script

With bundler installed, switch to ./src/bosh_azure_cpi and run:

```
./vendor_gems
```

### Create the BOSH release:

_Please make sure you have ruby 2.0 installed before continue._

```
bosh create release --force --with-tarball --name bosh-azure-cpi
```

The release is now ready for use. If everything works, commit the changes including the updated gems.

At the end of the CLI output there will be "Release tarball" path.

## Test Interfaces
After you change the CPI code, you can use `bosh_azure_console` to test your changes. Below commands are tested in Ubuntu 14.04 LTS.

```
# Install ruby 2.4.1 with rubyenv
sudo apt-get update
sudo apt-get install -y git gcc make libssl-dev libreadline-dev zlib1g-dev

cd
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
exec $SHELL

git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc
exec $SHELL

rbenv install 2.4.1
rbenv global 2.4.1
ruby -v

# Install postgres which bosh-registry depends on
sudo apt-get install -y postgresql postgresql-contrib libpq-dev g++ libmysqlclient-dev libsqlite3-dev

# Create database and user
cat > create_db.sql <<EOS
CREATE USER test WITH PASSWORD 'test';
CREATE DATABASE testdb;
GRANT ALL PRIVILEGES ON DATABASE testdb to test;
EOS
sudo su postgres
psql -f create_db.sql
exit

# Install bosh-registry which CPI depends on
gem install bundle bosh-registry pg --no-ri --no-rdoc

# Workaround for the issue https://github.com/cloudfoundry/bosh/issues/1621
sed -i -e '23s/^/#/' ~/.rbenv/versions/2.4.1/lib/ruby/gems/2.4.0/gems/bosh-registry-1.3262.24.0/lib/bosh/registry.rb

cat > ~/registry.cfg <<EOS
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
bosh-registry-migrate -c ~/registry.cfg

# Assume that you have cloned https://github.com/cloudfoundry-incubator/bosh-azure-cpi-release.git into ~/bosh-azure-cpi-release
cd ~/bosh-azure-cpi-release/src/bosh_azure_cpi
bundle install

# Please replace xxx with your credentials.
cat > ~/cpi.cfg <<EOS
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

```
bosh-registry -c ~/registry.cfg
```

Console 2:

```
cd ~/bosh-azure-cpi-release/src/bosh_azure_cpi/bin
./bosh_azure_console -c ~/cpi.cfg
```

Examples:

```
cpi.azure_client2.get_resource_group
cpi.disk_manager2.has_disk?('bosh-disk-a')
```

Below is an example you can type in `bosh_azure_console` to test fake light stemcells.

```
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
