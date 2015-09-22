#!/bin/bash
cd bosh
source /etc/profile.d/chruby.sh
chruby 2.1.2
cd bosh_cli
ls
version=`gem build bosh_cli.gemspec | grep 'File\: .*' | sed -n -e 's/.*\(bosh_cli.*.gem\)/\1/p'`
echo Installing BOSH CLI - $version
gem install $version