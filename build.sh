#!/bin/bash

docker buildx build $DOCKER_ARGS \
  --build-arg SIDEKIQ_CREDS=$SIDEKIQ_CREDS \
  .
