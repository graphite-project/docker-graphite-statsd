#!/usr/bin/env bash
VERSION=1.1.7-7
docker build . --build-arg python_binary=python3 --no-cache --tag graphiteapp/graphite-statsd:$VERSION