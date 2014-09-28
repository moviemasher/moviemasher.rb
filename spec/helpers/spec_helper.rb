ENV['RACK_ENV'] = 'test'

# delete previous log directory
FileUtils.rm_rf "#{__dir__}/../../log" if File.directory? "#{__dir__}/../../log"

require_relative '../../index'
require 'rspec'
require 'rack/test'

include RSpec::Matchers

def spec_file dir, name
	JSON.parse(File.read("#{__dir__}/media/json/#{dir}/#{name}.json"))
end
def spec_job_simple(input = nil, output = nil, destination = nil)
	job = Hash.new
	job['id'] = input
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
	destination['directory'] = File.dirname(File.dirname __dir__)
	output['basename'] = "{job.inputs.0.source.id}-{job.id}" unless output['basename'] 
	job
end
def spec_job_output_path job, processed_job
	destination = processed_job[:destination]	
	dest_path = destination[:file]
	if dest_path and File.directory?(dest_path) then
		dest_path = Dir["#{dest_path}/*"].first
		#puts "DIR: #{dest_path}"
	end
	dest_path
end
def spec_job_mash_simple(mash, output = 'video_h264', destination = 'file_log')
	job = spec_job mash, output, destination
	output = job['outputs'][0]
	input = job['inputs'][0]	
	processed_job = MovieMasher.process job
	expect(processed_job[:error]).to be_nil
	#puts processed_job.inspect
	destination_file = spec_job_output_path job, processed_job
	expect(destination_file).to_not be_nil
	#puts "destination_file exists #{File.exists? destination_file} #{destination_file}"
	expect(File.exists?(destination_file)).to be_true
	case output['type']
	when MovieMasher::Type::Audio, MovieMasher::Type::Video
		spec_expect_duration destination_file, processed_job[:duration]
	end
	spec_expect_dimensions(destination_file, output['dimensions']) if MovieMasher::Type::Mash == input['type']
	spec_expect_fps(destination_file, output['fps']) if MovieMasher::Type::Video == output['type'] 
	
	[job, processed_job]
end
def spec_expect_duration destination_file, duration
	expect(cache_get_info(destination_file, 'duration').to_f).to be_within(0.1).of duration
end
def spec_expect_fps destination_file, fps
	expect(cache_get_info(destination_file, 'fps').to_i).to eq fps.to_i
end
def spec_expect_dimensions destination_file, dimensions
	expect(cache_get_info(destination_file, 'dimensions')).to eq dimensions
end

RSpec.configure do |config|
	config.expect_with :rspec do |c|
		c.syntax = :expect
	end
	config.include Rack::Test::Methods
	config.after(:suite) do
		
  	end
end