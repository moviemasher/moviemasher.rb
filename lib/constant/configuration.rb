require 'optparse'
require 'optparse/time'
require 'ostruct'
require_relative '../util/hashable'

module MovieMasher
  # provides parsing and help for config options
  class Configuration < Hashable
    DESCRIPTIONS = {
      aws_access_key_id: 'Key identifier for transfers to and from AWS.',
      aws_secret_access_key: 'Key secret for transfers to and from AWS.',
      aws_region: 'Which AWS region to make requests to.',
      chmod_directory_new: 'Octal value indicating the permissions applied to'\
        ' any created directories.',
      disable_local: 'Boolean indicating whether or not local file'\
        ' services should be disabled for security.',
      download_bytes: 'How large of a download cache to maintain. If a number,'\
        ' bytes is assumed. K, M or G at end signifies kilobytes, megabytes,'\
        ' or gigabytes.',
      download_directory: 'Path to the directory used to cache media inputs. '\
        'If empty, render_directory is used.',
      error_directory: 'Path to the directory that problematic jobs are placed'\
        ' for debugging. If empty, such jobs are deleted or not based on'\
        ' render_save.',
      log_directory: 'Path to directory where logs are placed.',
      process_seconds: 'How long to look for queued jobs, in seconds. If zero,'\
        ' do not process. If -1, process one job. If -2 process until jobs'\
        ' done. If -3, process forever.',
      queue_directory: 'Path to directory where job files might be.',
      queue_name: 'SQS queue name where job messages might be.',
      queue_url: 'SQS queue endpoint where job messages might be.',
      queue_wait_seconds: 'How long to wait for SQS messages.',
      render_directory: 'Path to directory where jobs are built.',
      render_save: 'Boolean indicating whether or not jobs should be removed'\
        ' after processing.',
      verbose: 'How much detail to include in logs. One of debug, info, warn'\
        ' or error.'
    }.freeze
    INPUTS = {
      download_bytes: 'num',
      disable_local: 'bool',
      render_save: 'bool',
      chmod_directory_new: 'mode'
    }.freeze
    DEFAULTS = {
      aws_secret_access_key: '',
      aws_access_key_id: '',
      aws_region: 'us-east-1',
      chmod_directory_new: '0775',
      disable_local: false,
      download_directory: '',
      download_bytes: '0M',
      error_directory: '',
      queue_name: '',
      queue_url: '',
      log_directory: '/tmp/moviemasher/log',
      verbose: 'info',
      process_seconds: 55,
      queue_directory: '/tmp/moviemasher/queue',
      queue_wait_seconds: 2,
      render_directory: '/tmp/moviemasher/render',
      render_save: false
    }.freeze
    SWITCHES = {
      aws_secret_access_key: 'k',
      aws_access_key_id: 'i',
      aws_region: 'g',
      verbose: 'v',
      disable_local: 'f',
      download_directory: 'd',
      chmod_directory_new: 'm',
      download_bytes: 'b',
      error_directory: 'e',
      log_directory: 'l',
      process_seconds: 'p',
      queue_directory: 'q',
      queue_name: 'n',
      queue_url: 'u',
      queue_wait_seconds: 'w',
      render_directory: 'r',
      render_save: 's'
    }.freeze

    def self.parse(args = [], hash = nil)
      #  hint for --help
      # Options specified on the command line will be collected in *options*.
      # We set default values here.
      options = {}
      config = new(hash)
      config.keys.each do |key|
        options[key] = config[key]
      end
      opt_parser = OptionParser.new do |opts|
        opts.banner = 'Usage: moviemasher.rb [OPTIONS] [JOB]'
        opts.separator('')
        opts.separator('Options:')
        config.keys.each do |key|
          input = config.input(key).upcase
          short = "-#{config.switch(key)}#{input}"
          long = "--#{key}=#{input}"
          descr = wrap(config.describe(key))
          opts.on(short, long, *descr) do |opt|
            # puts "#{key} = #{opt}"
            options[key] = opt
          end
        end
        # No argument, shows at tail. This will print an options summary.
        opts.on('-h', '--help', 'Display this message and exit.') do
          return opts.to_s
        end
        opts.separator 'Job: Path to a job file or JSON formatted job string.'
      end
      # this might return a string containing usage prompt
      opt_parser.parse!(args)
      options
    end
    def self.wrap(s, width=60)
      lines = []
	    line = ""
	    s.split(/\s+/).each do |word|
	      if line.size + word.size >= width
	        lines << line
	        line = word
	      elsif line.empty?
	        line = word
	        else
	        line << " " << word
	      end
	    end
	    lines << line if line
	    lines
    end
    def describe(key)
      key = key.to_sym unless key.is_a?(Symbol)
      value = @hash[key]
      description = DESCRIPTIONS[key]
      description += " Default value of #{describe_value DEFAULTS[key]}"
      if value && value != DEFAULTS[key]
        description += " overridden by #{describe_value value}"
      end
      description += '.'
      description
    end
    def describe_value(value = nil)
      description = '(empty)'
      if value
        if value.is_a?(String)
          description = value unless value.empty?
        else
          description = value.inspect
        end
      end
      description
    end
    def initialize(hash = nil)
      hash ||= {}
      sym_hash = {}
      hash.each do |key, v|
        key = key.to_sym unless key.is_a?(Symbol)
        sym_hash[key] = v
      end
      super DEFAULTS.merge(sym_hash)
    end
    def input(key)
      key_s = key.to_s
      last_bit = key_s.split('_').last
      case last_bit
      when 'directory'
        'dir'
      when 'seconds'
        'secs'
      else
        INPUTS[key] || (DESCRIPTIONS[key].is_a?(String) ? last_bit : 'num')
      end
    end
    def switch(key)
      key = key.to_sym unless key.is_a?(Symbol)
      SWITCHES[key]
    end
  end
end
