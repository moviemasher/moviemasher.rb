
ENV['RACK_ENV'] = 'test' unless ENV['RACK_ENV']

require 'require_all'
require 'logger'  
require 'digest/sha2'
require 'open3'
require 'uri'
require 'uuid'
require 'rack'
require 'yaml'
require 'json'
require 'mime/types'
require 'net/http'
require 'net/http/post/multipart'
require 'aws-sdk' unless defined? AWS # maybe something has loaded aws-mock

user_data_file = "#{__dir__}/config/userdata.json"

CONFIG = YAML::load( File.open("#{__dir__}/config/config.yml") )[ENV['RACK_ENV']] unless defined? CONFIG
if File.exists? "#{__dir__}/config/userdata.json" then
	begin
		JSON.parse(File.read("#{__dir__}/config/userdata.json")).each do |k, v|
			CONFIG[k] = v
		end
	rescue 
		puts "Could not parse userdata.json"
	end
end
CONFIG['dir_temporary'] = File.expand_path CONFIG['dir_temporary']
CONFIG['dir_cache'] = File.expand_path CONFIG['dir_cache']
CONFIG['path_log'] = File.expand_path CONFIG['path_log']
			

IDER = UUID.new

S3 = AWS::S3.new
SQS = AWS::SQS.new
# queue will be nil if their URL is not defined in config.yml
SQS_QUEUE = (CONFIG['queue_url'] ? SQS.queues[CONFIG['queue_url']] : nil)

#require_relative 'lib/moviemasher' # first, so ElementClasses is defined
require_all "#{__dir__}/lib"

FileUtils.mkdir_p(CONFIG['dir_temporary']) unless File.directory?(CONFIG['dir_temporary'])
FileUtils.mkdir_p(CONFIG['dir_cache']) unless File.directory?(CONFIG['dir_cache'])
FileUtils.mkdir_p(CONFIG['path_log']) unless File.directory?(CONFIG['path_log'])

if not defined? LOG then
	LOG = Logger.new("#{CONFIG['path_log']}/transcoder.log", 7, 1048576 * 100)
	LOG.level = Logger::INFO
end

if 'production' == ENV['RACK_ENV'] then
	
else  # test, development
	LOG.level = Logger::DEBUG
   	#ActiveRecord::Base.logger = LOG	
end
