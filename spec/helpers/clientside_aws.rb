ENV['RACK_ENV'] = 'test'

require 'bundler/setup'
require_relative '../../../clientside_aws/lib/clientside_aws/mock'
require_relative 'spec_helper'
AWS.config(access_key_id: '...', secret_access_key: '...')

def spec_start_redis
  pid = fork { exec 'redis-server --port 6380 --loglevel warning' }
  puts "spec_start_redis pid: #{pid}"
  sleep(1)
  pid
rescue => e
  puts "spec_start_redis caught: #{e.message}"
  nil
end

def spec_stop_redis(pid)
  STDOUT.flush
  puts "spec_stop_redis pid #{pid}"
  Process.kill('KILL', pid)
  # Process.waitall
rescue => e
  puts "spec_stop_redis caught: #{e.message}"
end
