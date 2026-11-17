#!/bin/bash

docker buildx build $DOCKER_ARGS \
  --secret id=sidekiq_creds,env=SIDEKIQ_CREDS \
  --build-arg RUBY_VERSION=$(cat .ruby-version) \
  .
