FROM ruby:3.1-slim

# Non-interactive frontend for debian stuff to reduce error noise
ENV DEBIAN_FRONTEND noninteractive

# Install basic essentials
RUN apt -y update && \
    apt -y install openssh-client apt-utils curl wget zip git make build-essential

RUN apt-get install -y valgrind

# clean apt cache
RUN rm -rf /var/cache/apt/*

ENV RUSTUP_HOME=/opt/rust \
    CARGO_HOME=/opt/rust

RUN ( curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path ) && \
    find /opt/rust -exec chmod 777 {} +

ADD docker/rust-wrapper.sh /usr/local/bin/cargo
ADD docker/rust-wrapper.sh /usr/local/bin/cargo-clippy
ADD docker/rust-wrapper.sh /usr/local/bin/cargo-fmt
ADD docker/rust-wrapper.sh /usr/local/bin/rls
ADD docker/rust-wrapper.sh /usr/local/bin/rust-gdb
ADD docker/rust-wrapper.sh /usr/local/bin/rust-lldb
ADD docker/rust-wrapper.sh /usr/local/bin/rustc
ADD docker/rust-wrapper.sh /usr/local/bin/rustdoc
ADD docker/rust-wrapper.sh /usr/local/bin/rustfmt
ADD docker/rust-wrapper.sh /usr/local/bin/rustup

ENV APP_HOME /selma
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/
ADD selma.gemspec $APP_HOME/
RUN mkdir -p $APP_HOME/lib/selma
ADD lib/selma/version.rb $APP_HOME/lib/selma

ENV BUNDLE_GEMFILE=$APP_HOME/Gemfile \
  BUNDLE_JOBS=2 \
  BUNDLE_PATH=/bundle

RUN bundle install

ADD ext/selma/lol-html-upstream $APP_HOME/ext/selma/lol-html-upstream
WORKDIR $APP_HOME/ext/selma/lol-html-upstream/c-api
RUN cargo build --release

WORKDIR $APP_HOME
ADD . $APP_HOME

COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
