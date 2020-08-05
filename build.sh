#!/bin/bash

docker build --build-arg DD_API_KEY=$DD_API_KEY \
             --build-arg SIDEKIQ_CREDS=$SIDEKIQ_CREDS \
             -t 056154071827.dkr.ecr.us-east-1.amazonaws.com/$PROJECT_NAME:$ENVIRONMENT-$BUILD_NUMBER .
