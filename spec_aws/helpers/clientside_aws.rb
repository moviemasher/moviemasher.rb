
# 	redis-server --port 6380 &
#	cd /path/to/clientside_aws
# 	rvm gemset use clientside_aws
#	RACK_ENV=test ruby ./index.rb -p 4568 &

require 'redis'
require 'httparty'
require 'sinatra'

require_relative '../../../clientside_aws/aws_mock'
require_relative '../../../clientside_aws/clientside_aws/s3'

PIDS = Array.new
AWS_REDIS = Redis.new(:host => "localhost", :port => 6380, :driver => :hiredis)

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
		Process.waitall
		PIDS.clear
	end
rescue Exception => e
	puts "spec_stop_redis caught: #{e.message}"
end