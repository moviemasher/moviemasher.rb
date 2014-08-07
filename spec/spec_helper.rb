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

PIDS = Array.new


def app
	Sinatra::Application
end


#Dir.chdir __dir__

def spec_file dir, name
	JSON.parse(File.read("#{__dir__}/media/json/#{dir}/#{name}.json"))
end

def spec_job_simple(input = nil, output = nil, destination = nil)
	job = Hash.new
	job['id'] = UUID.new.generate
	job['inputs'] = Array.new
	job['outputs'] = Array.new
	job['destination'] = spec_file('destinations', destination) if destination
	job['inputs'] << spec_file('inputs', input) if input
	job['outputs'] << spec_file('outputs', output) if output
	job
end

def spec_job(mash, output = 'video_h264', destination = 'file_log')
	job = spec_job_simple mash, output, destination
	output = job['outputs'][0]
	input = job['inputs'][0]
	input['base_source'] = spec_file('sources', 'file_spec')
	input['base_source']['directory'] = File.dirname __dir__
	destination = job['destination']
	#puts job.inspect
	input['source']['directory'] = __dir__
	destination['directory'] = File.dirname __dir__
	output['basename'] = "{job.inputs.0.source.id}-{job.id}" unless output['basename'] 
	job
end

def spec_job_output_path job, processed_job
	destination = processed_job[:destination]	
	dest_path = destination[:file]
	if File.directory?(dest_path) then
		dest_path = Dir["#{dest_path}/*"].first
		#puts "DIR: #{dest_path}"
	end
	dest_path
end

def spec_job_mash_simple mash, output = 'video_h264', destination = 'file_log'
	job = spec_job mash, output, destination
	output = job['outputs'][0]
	input = job['inputs'][0]	
	processed_job = MovieMasher.process job
	#puts processed_job.inspect
	destination_file = spec_job_output_path job, processed_job
	
	#puts "destination_file exists #{File.exists? destination_file} #{destination_file}"
	expect(File.exists?(destination_file)).to be_true
	case output['type']
	when MovieMasher::TypeAudio, MovieMasher::TypeVideo
		spec_expect_duration destination_file, processed_job[:duration]
	end
	spec_expect_dimensions(destination_file, output['dimensions']) if MovieMasher::TypeMash == input['type']
	spec_expect_fps(destination_file, output['fps']) if MovieMasher::TypeVideo == output['type'] 
	
	[job, processed_job]
end
def spec_expect_duration destination_file, duration
	expect(MovieMasher.__cache_get_info(destination_file, 'duration').to_f).to be_within(0.1).of duration
end
def spec_expect_fps destination_file, fps
	expect(MovieMasher.__cache_get_info(destination_file, 'fps').to_i).to eq fps.to_i
end
def spec_expect_dimensions destination_file, dimensions
	expect(MovieMasher.__cache_get_info(destination_file, 'dimensions')).to eq dimensions
end


def spec_start_redis
	if PIDS.empty? then
		pid = fork do
			$stdout = File.new('/dev/null', 'w')
			File.open("test1.conf", 'w') {|f| f.write("port 6380\ndbfilename test1.rdb\nloglevel warning") }
			exec "redis-server test1.conf"
		end
		PIDS << pid
		pid = fork do
			$stdout = File.new('/dev/null', 'w')
			File.open("test2.conf", 'w') {|f| f.write("port 6381\ndbfilename test2.rdb\nloglevel warning") }
			exec "redis-server test2.conf"
		end
		PIDS << pid
		
		puts "PIDS: #{PIDS}\n\n"
		sleep(3)
	end
rescue Exception => e
	puts "EXCEPTION: spec_start_redis #{e.inspect}"
end

RSpec.configure do |config|
	config.expect_with :rspec do |c|
		c.syntax = :expect
	end
	config.include Rack::Test::Methods
	config.after(:suite) do
		unless PIDS.empty? then
			STDOUT.flush
			puts "PIDS #{PIDS}" 
			PIDS.each do |pid|
				Process.kill("KILL", pid) 
			end
			FileUtils.rm "test1.rdb" if File.exists?("test1.rdb")
			FileUtils.rm "test2.rdb" if File.exists?("test2.rdb")
			FileUtils.rm "test1.conf" if File.exists?("test1.conf")
			FileUtils.rm "test2.conf" if File.exists?("test2.conf")
			Process.waitall
			puts "AFTER SUITE END"
			PIDS.clear
		end
  	end
end