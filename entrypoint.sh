#!/bin/bash
set -e

export DEBUG=1

bundle exec rake compile

# LD_PRELOAD=$(gcc -print-file-name=libasan.so) bundle exec rake test:asan

bundle exec rake test:memcheck
