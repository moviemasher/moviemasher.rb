require 'optparse'
require 'optparse/time'
require 'ostruct'
require_relative '../util/hashable'

module MovieMasher
# Supported configuration keys: 
#
# chmod_directory_new - Octal value indicating the permissions applied to any created directories.
# download_bytes - How large of a download cache to maintain. If a number, bytes is assumed. K, M or G at end signifies kilobytes, megabytes, or gigabytes.
# download_directory - Path to the directory used to cache media inputs. If empty, render_directory is used. 
# error_directory - Path to the directory that problematic jobs are placed for debugging. If empty, such jobs are deleted or not based on render_save.
# log_directory - Path to directory where logs are placed.
# process_seconds - How long to look for queued jobs, in seconds. If zero, do not process. If -1, process one job. If -2 process until jobs done. If -3, process forever.
# queue_directory - Path to directory where job files might be.
# queue_url - SQS queue endpoint where job messages might be.
# queue_wait_seconds - How long to wait for SQS messages.
# render_directory - Path to directory where jobs are built.
# render_save - Boolean indicating whether or not jobs should be removed after processing.
# verbose - How much detail to include in logs. One of debug, info, warn or error.
#
	class Configuration < Hashable
		
		Descriptions = {
			:chmod_directory_new => 'Octal value indicating the permissions applied to any created directories.',
			:download_bytes => 'How large of a download cache to maintain. If a number, bytes is assumed. K, M or G at end signifies kilobytes, megabytes, or gigabytes.',
			:download_directory => 'Path to the directory used to cache media inputs. If empty, render_directory is used.', 
			:error_directory => 'Path to the directory that problematic jobs are placed for debugging. If empty, such jobs are deleted or not based on render_save.',
			:log_directory => 'Path to directory where logs are placed.',
			:process_seconds => 'How long to look for queued jobs, in seconds. If zero, do not process. If -1, process one job. If -2 process until jobs done. If -3, process forever.',
			:queue_directory => 'Path to directory where job files might be.',
			:queue_url => 'SQS queue endpoint where job messages might be.',
			:queue_wait_seconds => 'How long to wait for SQS messages.',
			:render_directory => 'Path to directory where jobs are built.',
			:render_save => 'Boolean indicating whether or not jobs should be removed after processing.',
			:verbose => 'How much detail to include in logs. One of debug, info, warn or error.',
		}
		Inputs = {
			:download_bytes => 'num',
			:render_save => 'bool',
			:chmod_directory_new => 'mode',
		}
		Defaults = {
			:chmod_directory_new => '0775',
			:download_directory => '', 
			:download_bytes => '0M', 
			:error_directory => '',
			:queue_url => '',
			:log_directory => '/tmp/moviemasher/log',
			:verbose => 'info',
			:process_seconds => 55,
			:queue_directory => '/tmp/moviemasher/queue',
			:queue_wait_seconds => 2,
			:render_directory => '/tmp/moviemasher/render',
			:render_save => false,
		}
		Switches = {
			:verbose => 'v',
			:download_directory => 'd',
			:chmod_directory_new => 'm',
		}
		
		def self.init_switches
			Descriptions.keys.sort.each do |key|
				next unless Switches[key].nil?
				key_s = key.to_s
				chars = key_s.split('_').map{|w|w[0]} + ('a'..'z').to_a
				char = nil
				while not chars.empty?
					char = chars.shift 
					break unless Switches.values.include? char
					char = nil
				end
				Switches[key] = char if char
			end
		end
		init_switches 
		def self.parse(args = [], hash = nil, command = nil) # command is hint for --help
			# The options specified on the command line will be collected in *options*.
			# We set default values here.
			options = Hash.new
			config = new hash
			config.keys.each do |key|
				options[key] = config[key]
			end
			opt_parser = OptionParser.new do |opts|
				opts.banner = "Usage: moviemasher.rb [OPTIONS] [JOB]"
				#opts.summary = "Overrides options specified in config/config.yml and/or executes a job."
				opts.separator ""
				opts.separator "Options:"
				config.keys.each do |key|
					input = config.input(key).upcase
					short = "-#{config.switch key}#{input}"
					long = "--#{key}=#{input}"
					opts.on(short, long, config.describe(key)) do |opt|
						puts "#{key} = #{opt}"
						options[key] = opt
					end
				end

				# No argument, shows at tail. This will print an options summary.
				opts.on("-h", "--help", "Display this message and exit.") do
					return opts.to_s
				end
				opts.separator ""
				opts.separator "Job: Path to a job file or JSON formatted job string."
			end
			opt_parser.parse!(args)
			options
		end

		def initialize hash = nil
			hash = Hash.new unless hash
			sym_hash = Hash.new
			hash.each do |key,v|
				key = key.to_sym unless key.is_a? Symbol
				sym_hash[key] = v
			end
			super Defaults.merge sym_hash
		end
		def switch key
			key = key.to_sym unless key.is_a? Symbol
			Switches[key]
		end
		def describe_value value = nil
			description = '(empty)'
			if value 
				if value.is_a? String
					description = value unless value.empty?
				else
					description = value.inspect
				end
			end
			description 
		end
		def input key
			
			key_s = key.to_s
			last_bit = key_s.split('_').last 
			case last_bit
			when 'directory'
				'dir'
			when 'seconds'
				'secs'
			else
				
				Inputs[key] || (Descriptions[key].is_a?(String) ? last_bit : 'num')
			end
		end
		def describe key
			key = key.to_sym unless key.is_a? Symbol
			value = @hash[key]
			description = "#{Descriptions[key]}"
			description += " Default value of #{describe_value Defaults[key]}"
			description += " overridden by #{describe_value value}" if value and value != Defaults[key]
			description += '.'
			description
		end
		
	end
end
