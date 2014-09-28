
ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']

require 'fileutils'
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
require 'aws-sdk' unless defined? AWS 

user_data_file = "#{__dir__}/config/userdata.json"

CONFIG = YAML::load( File.open("#{__dir__}/config/config.yml") )[ENV['RACK_ENV']] unless defined? CONFIG
if File.exists? user_data_file then
	begin
		JSON.parse(File.read(user_data_file)).each do |k, v|
			CONFIG[k] = v
		end
	rescue 
		puts "Could not parse userdata.json"
	end
end

require_all "#{__dir__}/lib"

