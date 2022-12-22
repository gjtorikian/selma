FROM ruby:3.1-slim

# Non-interactive frontend for debian stuff to reduce error noise
ENV DEBIAN_FRONTEND noninteractive

# Install basic essentials
RUN apt -y update && \
    apt -y install openssh-client apt-utils curl wget zip git make build-essential libclang-dev

RUN apt-get install -y valgrind

# clean apt cache
RUN rm -rf /var/cache/apt/*

ENV RUSTUP_HOME=/opt/rust \
    CARGO_HOME=/opt/rust

RUN ( curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path ) && \
    find /opt/rust -exec chmod 777 {} +

COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/cargo
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/cargo-clippy
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/cargo-fmt
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rls
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rust-gdb
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rust-lldb
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rustc
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rustdoc
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rustfmt
COPY test/memcheck/tools/rust-wrapper.sh /usr/local/bin/rustup

ENV APP_HOME /selma
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

COPY Gemfile* $APP_HOME/
COPY selma.gemspec $APP_HOME/
RUN mkdir -p $APP_HOME/lib/selma
COPY lib/selma/version.rb $APP_HOME/lib/selma

ENV BUNDLE_GEMFILE=$APP_HOME/Gemfile \
    BUNDLE_JOBS=2 \
    BUNDLE_PATH=/bundle

RUN bundle install

WORKDIR $APP_HOME
# RUN echo "$CACHEBUST"
COPY . $APP_HOME

COPY test/memcheck/entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh

ENTRYPOINT entrypoint.sh
