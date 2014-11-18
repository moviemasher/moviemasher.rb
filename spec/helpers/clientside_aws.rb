ENV['RACK_ENV'] = 'test'

require 'bundler/setup'
require 'clientside_aws/mock'
require_relative 'spec_helper'
AWS.config :access_key_id => '...', :secret_access_key => '...'
PIDS = Array.new

def spec_start_redis
	if PIDS.empty? then
		pid = fork do
			exec "redis-server --port 6380 --loglevel warning"
		end
		PIDS << pid
		puts "spec_start_redis PIDS: #{PIDS}\n\n"
		sleep(1)
	end
rescue Exception => e
	puts "spec_start_redis caught: #{e.message}"
end

def spec_stop_redis
	unless PIDS.empty? then
		STDOUT.flush
		puts "spec_stop_redis PIDS #{PIDS}" 
		PIDS.each do |pid|
			Process.kill("KILL", pid) 
		end
		PIDS.clear
		#Process.waitall
	end
rescue Exception => e
	puts "spec_stop_redis caught: #{e.message}"
end