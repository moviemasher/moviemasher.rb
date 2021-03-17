#!/usr/bin/ruby
# encoding: utf-8

commands = {
  process: 0,
  process_one: -1,
  process_all: -2,
  process_loop: -3,
  moviemasher: false,
}
arguments = ARGV.dup
arguments = arguments.first.split(' ') if arguments.count == 1
command = arguments.first.to_sym

def puts_configuration(config)
  keys = config.keys.sort.map { |k| "#{k}: #{config[k]}" }
  puts "Loaded configuration: #{keys.join(', ')}"
end

if commands.include?(command)
  arguments.shift # remove command
  config_file = ENV['MOVIEMASHER_CONFIG']
  puts "Loading configuration #{config_file}"
  config_file ||= '/mnt/moviemasher.rb/config/docker/config.yml'
  require '/mnt/moviemasher.rb/lib/moviemasher'
  config = YAML.load(File.open(config_file))
  config[:process_seconds] = commands[command] if commands[command]
  configuration = MovieMasher::Configuration.parse(arguments, config)
  if configuration.is_a?(String)
    puts configuration
    puts_configuration(config)
  else
    puts_configuration(configuration)
    MovieMasher.configure(configuration)
    puts MovieMasher.hello
    MovieMasher.process_jobs(arguments)
    MovieMasher.process_queues(configuration[:process_seconds])
    puts MovieMasher.goodbye
  end
else
  puts "Executing #{command}"
  exec(arguments.join(' '))
end
