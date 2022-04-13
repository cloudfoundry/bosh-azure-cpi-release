FROM ubuntu:focal

ENV bosh_cli_version 6.4.15
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update && apt-get install -y locales && locale-gen en_US.UTF-8
RUN update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

RUN apt-get install -y \
    sudo \
    apt-utils \
    git curl wget tar make jq uuid-runtime \
    sqlite3 libsqlite3-dev \
    build-essential \
    libxslt-dev libxml2-dev libyaml-dev  \
    ruby azure-cli && \
    apt-get clean

# ruby-install
RUN mkdir /tmp/ruby-install && \
    cd /tmp/ruby-install && \
    curl https://codeload.github.com/postmodern/ruby-install/tar.gz/v0.8.3 | tar -xz && \
    cd /tmp/ruby-install/ruby-install-0.8.3 && \
    make install && \
    rm -rf /tmp/ruby-install

# ruby
RUN ruby-install ruby ${RUBY_VERSION}

# chruby
RUN /bin/bash -l -c " \
    curl https://codeload.github.com/postmodern/chruby/tar.gz/v0.3.9 | tar -xz -C /tmp/ && \
    pushd /tmp/chruby-0.3.9 && \
    ./scripts/setup.sh && \
    popd && \
    rm -rf /tmp/chruby-0.3.9 \
"


# Bundler
RUN /bin/bash -l -c "                   \
  source /etc/profile.d/chruby.sh ;     \
  chruby ${RUBY_VERSION} ;              \
  gem install bundler --no-document \
"

#BOSH CLI
RUN \
  wget --quiet https://s3.amazonaws.com/bosh-cli-artifacts/bosh-cli-${bosh_cli_version}-linux-amd64 --output-document="/usr/bin/bosh" && \
  chmod +x /usr/bin/bosh && \
  cp /usr/bin/bosh /usr/local/bin/bosh-go && \
  chmod +x /usr/local/bin/bosh-go
