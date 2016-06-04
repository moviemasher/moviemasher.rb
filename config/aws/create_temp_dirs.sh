#!/bin/bash

mkdir -p /tmp/moviemasher/queue
mkdir -p /tmp/moviemasher/temporary
mkdir -p /tmp/moviemasher/log
mkdir -p /tmp/moviemasher/download
mkdir -p /tmp/moviemasher/render
chown -R ec2-user:apache /tmp/moviemasher
chmod -R g+w /tmp/moviemasher
