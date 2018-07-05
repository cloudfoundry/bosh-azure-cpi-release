FROM ubuntu:16.04

RUN apt-get update; apt-get -y upgrade; apt-get clean

RUN apt-get install -y git curl tar make jq; apt-get clean

# dependencies for "bosh create-env" command
RUN apt-get install -y build-essential zlibc zlib1g-dev ruby ruby-dev openssl libxslt-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3; apt-get clean

# azure-cli
RUN echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ xenial main" | tee /etc/apt/sources.list.d/azure-cli.list
RUN curl -L https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN apt-get install -y apt-transport-https
RUN apt-get update; apt-get install -y azure-cli=2.0.41-1~xenial; apt-get clean; az -v

# chruby
RUN /bin/bash -l -c " \
    curl https://codeload.github.com/postmodern/chruby/tar.gz/v0.3.9 | tar -xz -C /tmp/ && \
    pushd /tmp/chruby-0.3.9 && \
    ./scripts/setup.sh && \
    popd && \
    rm -rf /tmp/chruby-0.3.9 \
"

# ruby-install
RUN /bin/bash -l -c " \
    curl https://codeload.github.com/postmodern/ruby-install/tar.gz/v0.5.0 | tar -xz -C /tmp/ && \
    pushd /tmp/ruby-install-0.5.0 && \
    make install && \
    popd && \
    rm -rf /tmp/ruby-install-0.5.0 \
"

# ruby
ENV RUBY_VERSION 2.4.4
RUN ruby-install ruby ${RUBY_VERSION}

# Bundler
RUN /bin/bash -l -c "                   \
  source /etc/profile.d/chruby.sh ;     \
  chruby ${RUBY_VERSION} ;              \
  gem install bundler --no-ri --no-rdoc \
"
