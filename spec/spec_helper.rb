ENV['RACK_ENV'] = 'test'
log_dir = "#{__dir__}/../log"
FileUtils.rm_rf log_dir if File.directory? log_dir
require 'redis'
require 'aws-sdk'
require 'httparty'
require 'sinatra'

require_relative '../../clientside_aws/aws_mock'
require_relative '../../clientside_aws/clientside_aws/s3'

AWS_REDIS = REDIS = Redis.new(:host => "localhost", :port => 6380, :driver => :hiredis)

require_relative '../index'
require 'rspec'
require 'rack/test'
Sinatra::Base.set :environment, :test
Sinatra::Base.set :run, false
Sinatra::Base.set :raise_errors, true
Sinatra::Base.set :logging, false
include RSpec::Matchers

pid1 = nil
pid2 = nil

def app
	Sinatra::Application
end


#Dir.chdir __dir__

def spec_file dir, name
	JSON.parse(File.read("#{__dir__}/media/json/#{dir}/#{name}.json"))
end

def spec_output name
	spec_file 'outputs', name	
end

def spec_transfer name
	spec_file 'transfers', name	
end

def spec_input name
	spec_file 'inputs', name	
end

def spec_job_simple input = nil, output = nil, destination = nil
	job = Hash.new
	job['id'] = UUID.new.generate
	job['inputs'] = Array.new
	job['outputs'] = Array.new
	job['destination'] = spec_transfer(destination) if destination
	job['inputs'] << spec_input(input) if input
	job['outputs'] << spec_output(output) if output
	job
end

def spec_job_mash_simple mash, output = 'video_h264', destination = 'file_log'
	job = spec_job_simple mash, output, destination
	output = job['outputs'][0]
	input = job['inputs'][0]
	input['base_source'] = spec_transfer 'file_spec'
	input['base_source']['directory'] = File.dirname __dir__
	destination = job['destination']
	#puts job.inspect
	input['source']['directory'] = __dir__
	destination['directory'] = File.dirname __dir__
	output['basename'] = "#{mash}-{job_id}"
	processed_job = MovieMasher.process job
	#puts processed_job.inspect
	destination_file = destination['directory'] + '/' + destination['path'] + '/' + output['basename'].gsub!('{job_id}', job['id']) + '.' + output['extension']
	#puts "destination_file exists #{File.exists? destination_file} #{destination_file}"
	expect(File.exists? destination_file).to be_true
	expect(MovieMasher.__cache_get_info(destination_file, 'dimensions')).to eq output['dimensions']
	expect(MovieMasher.__cache_get_info(destination_file, 'fps').to_i).to eq output['fps'].to_i
	expect(MovieMasher.__cache_get_info(destination_file, 'duration').to_f).to be_within(0.1).of processed_job[:duration]
end

def spec_start_redis
	pid1 = fork do
		$stdout = File.new('/dev/null', 'w')
		File.open("test1.conf", 'w') {|f| f.write("port 6380\ndbfilename test1.rdb\nloglevel warning") }
		exec "redis-server test1.conf"
	end
	pid2 = fork do
		$stdout = File.new('/dev/null', 'w')
		File.open("test2.conf", 'w') {|f| f.write("port 6381\ndbfilename test2.rdb\nloglevel warning") }
		exec "redis-server test2.conf"
	end
	puts "PID1 is #{pid1} and PID2 is #{pid2}\n\n"
	sleep(3)
rescue Exception => e
	puts "EXCEPTION: spec_start_redis #{e.inspect}"
end

RSpec.configure do |config|
	config.expect_with :rspec do |c|
		c.syntax = :expect
	end
	config.include Rack::Test::Methods

#	config.before(:suite) do
# 		puts "BEFORE SUITE START"
# 		puts "BEFORE SUITE END"
#	end

	config.after(:suite) do
		STDOUT.flush
		puts "PID1 is #{pid1} and PID2 is #{pid2}\n\n" if pid1
		Process.kill("KILL", pid1) if pid1
		Process.kill("KILL", pid2) if pid2
		FileUtils.rm "test1.rdb" if File.exists?("test1.rdb")
		FileUtils.rm "test2.rdb" if File.exists?("test2.rdb")
		FileUtils.rm "test1.conf" if File.exists?("test1.conf")
		FileUtils.rm "test2.conf" if File.exists?("test2.conf")
		Process.waitall if pid1
	#	puts "AFTER SUITE END"
  	end
end