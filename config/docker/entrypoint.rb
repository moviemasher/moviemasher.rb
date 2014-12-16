#!/usr/local/bin/ruby
# encoding: utf-8
command = ARGV.first
commands = {
	:process => 0,
	:process_one => -1,
	:process_all => -2,
	:process_loop => -3,
	:moviemasher => false,
}
exec(ARGV.join ' ') unless commands.include? command.to_sym
ARGV.shift # remove command
require '/mnt/moviemasher.rb/lib/moviemasher'
config = YAML::load(File.open(ENV['MOVIEMASHER_CONFIG'] || '/mnt/moviemasher.rb/config/docker/config.yml'))
configuration = MovieMasher::Configuration.parse(ARGV, config, command)
if configuration.is_a? String
	puts configuration
else	
	MovieMasher.configure configuration
	puts MovieMasher.hello
	MovieMasher.process_jobs ARGV
	MovieMasher.process_queues commands[command.to_sym]
	puts MovieMasher.goodbye
end
