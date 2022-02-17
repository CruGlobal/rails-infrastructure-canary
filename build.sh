#!/bin/bash

docker buildx build $DOCKER_ARGS \
  --build-arg DD_API_KEY=$DD_API_KEY \
  --build-arg SIDEKIQ_CREDS=$SIDEKIQ_CREDS \
  .
