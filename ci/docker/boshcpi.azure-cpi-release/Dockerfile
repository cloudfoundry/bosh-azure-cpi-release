FROM ubuntu:15.04

RUN apt-get update; apt-get -y upgrade; apt-get clean

RUN apt-get install -y git curl tar make; apt-get clean

RUN apt-get install -y sqlite3 libsqlite3-dev; apt-get clean

RUN apt-get install -y mysql-client libmysqlclient-dev; apt-get clean

RUN apt-get install -y jq; apt-get clean

RUN apt-get install -y libpq-dev; apt-get clean

RUN curl -sL https://deb.nodesource.com/setup_4.x | bash -; apt-get install -y nodejs; apt-get clean; rm -f /usr/bin/node; ln -s /usr/bin/nodejs /usr/bin/node

# azure CLI
RUN npm install -g azure-cli@0.10.1; azure -v

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
ENV RUBY_VERSION 2.2.4
RUN ruby-install ruby ${RUBY_VERSION}

# Bundler and BOSH CLI
RUN /bin/bash -l -c "                            \
  source /etc/profile.d/chruby.sh ;              \
  chruby ${RUBY_VERSION} ;                       \
  gem install bundler bosh_cli --no-ri --no-rdoc \
"
