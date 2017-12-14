#!/bin/bash

echo "running test; current dir is $PWD"

bundle exec rake db:migrate test
