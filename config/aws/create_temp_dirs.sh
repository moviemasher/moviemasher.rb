#!/bin/bash

mkdir -p /tmp/moviemasher/download
mkdir -p /tmp/moviemasher/render
chown -R ec2-user:www /tmp/moviemasher
chmod -R g+w /tmp/moviemasher
