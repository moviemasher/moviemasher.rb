
ENV['RACK_ENV'] = 'test' unless ENV['RACK_ENV']

require 'require_all'
require 'logger'  
require 'digest/sha2'
require 'open3'
require 'uri'
require 'uuid'
require 'yaml'
require 'json'
require 'mime/types'
require 'net/http'
require 'net/http/post/multipart'
require 'aws-sdk' unless defined? AWS # maybe something has loaded aws-mock
S3 = AWS::S3.new

CONFIG = YAML::load( File.open("#{__dir__}/config/config.yml") )[ENV['RACK_ENV']] unless defined? CONFIG
CONFIG['path_temporary'] = File.expand_path CONFIG['path_temporary']
CONFIG['path_cache'] = File.expand_path CONFIG['path_cache']
CONFIG['path_log'] = File.expand_path CONFIG['path_log']


require_relative 'lib/moviemasher' # first, so ElementClasses is defined
require_all "#{__dir__}/lib"

FileUtils.mkdir_p(CONFIG['path_temporary']) unless File.directory?(CONFIG['path_temporary'])
FileUtils.mkdir_p(CONFIG['path_cache']) unless File.directory?(CONFIG['path_cache'])
FileUtils.mkdir_p(CONFIG['path_log']) unless File.directory?(CONFIG['path_log'])

if not defined? LOG then
	LOG = Logger.new("#{CONFIG['path_log']}/moviemasher.log", 7, 1048576 * 100)
	LOG.level = Logger::INFO
end

if 'production' == ENV['RACK_ENV'] then
	
else  # test, development
	LOG.level = Logger::DEBUG
   	#ActiveRecord::Base.logger = LOG	
end
