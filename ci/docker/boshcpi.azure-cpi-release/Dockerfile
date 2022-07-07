FROM ubuntu:jammy

ENV bosh_cli_version 7.0.1
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update && apt-get install -y locales && locale-gen en_US.UTF-8
RUN update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

RUN apt-get install -y \
    sudo \
    apt-utils \
    gpg gpg-agent \
    git curl wget tar make jq uuid-runtime \
    sqlite3 libsqlite3-dev \
    build-essential \
    ca-certificates apt-transport-https lsb-release \
    libxslt-dev libxml2-dev libyaml-dev  \
    ruby && \
    apt-get clean

RUN curl -sL https://packages.microsoft.com/keys/microsoft.asc |\
    gpg --dearmor |\
    sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null 

RUN echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" |\
    sudo tee /etc/apt/sources.list.d/azure-cli.list && \
    sudo apt update && sudo apt install azure-cli

# ruby-install
RUN mkdir /tmp/ruby-install && \
    cd /tmp/ruby-install && \
    curl https://codeload.github.com/postmodern/ruby-install/tar.gz/v0.8.3 | tar -xz && \
    cd /tmp/ruby-install/ruby-install-0.8.3 && \
    make install && \
    rm -rf /tmp/ruby-install

# ruby
ARG RUBY_VERSION
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
