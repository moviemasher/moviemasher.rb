#!/usr/local/bin/ruby
# encoding: utf-8

commands = {
  process: 0,
  process_one: -1,
  process_all: -2,
  process_loop: -3,
  moviemasher: false,
}
command = ARGV.first.to_sym
def puts_configuration(config)
  puts "Current Configuration:"
  config.keys.sort.each { |k| puts "  #{k}: #{config[k]}" }
end
if commands.include?(command)
  ARGV.shift # remove command
  config_file = ENV['MOVIEMASHER_CONFIG']
  config_file ||= '/mnt/moviemasher.rb/config/docker/config.yml'
  puts "Command #{command} loading configuration file #{config_file}"
  require '/mnt/moviemasher.rb/lib/moviemasher'
  config = YAML.load(File.open(config_file))
  config[:process_seconds] = commands[command] if commands[command]
  configuration = MovieMasher::Configuration.parse(ARGV, config)
  if configuration.is_a?(String)
    puts configuration
    puts_configuration(config)
  else
    puts_configuration(configuration)
    MovieMasher.configure(configuration)
    puts MovieMasher.hello
    MovieMasher.process_jobs(ARGV)
    MovieMasher.process_queues(configuration[:process_seconds])
    puts MovieMasher.goodbye
  end
else
  exec(ARGV.join(' '))
end
