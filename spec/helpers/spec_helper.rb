ENV['RACK_ENV'] = 'test'
RAILS_ROOT = File.expand_path("#{__dir__}/../../") unless defined?(RAILS_ROOT)
DIR_HTTP_POSTS = File.expand_path("#{RAILS_ROOT}/config/docker/rspec/http/posts")
DIR_LOCAL_POSTS = '/tmp/spec/service_output'

require 'rspec'
require_relative 'magick_generator'

extend RSpec::Matchers
include MagickGenerator

# delete previous temp directory !!
if File.directory?("#{RAILS_ROOT}/tmp/spec")
  FileUtils.rm_rf("#{RAILS_ROOT}/tmp/spec")
end

require_relative '../../lib/moviemasher'

MovieMasher::FileHelper.safe_path("#{RAILS_ROOT}/tmp/spec")
MovieMasher.configure("#{RAILS_ROOT}/config/docker/rspec/config.yml")
puts MovieMasher::Configuration.parse(['--help'])
require_relative 'expect_methods'
require_relative 'spec_methods'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.before(:suite) do
  end
end
