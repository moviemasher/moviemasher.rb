
require 'cgi'
require 'digest/sha2'
require 'fileutils'
require 'json'
require 'logger'  
require 'mime/types'
require 'net/http'
require 'net/http/post/multipart'
require 'open3'
require 'require_all'
require 'uri'
require 'uuid'
require 'yaml'

require_rel '.'

# Handles global configuration and high level processing of Job objects. The 
# ::process_queues method will look for jobs in a directory and optionally an 
# SQS queue for a period of time, calling ::process for each one found. No 
# configuration is required, though be aware that no download cache is 
# maintained by default. 
#
#   MovieMasher.configure :render_directory => './temp'
#   MovieMasher.process './job.json'
#   # => #<MovieMasher::Job:0x007fa34300abc0>
module MovieMasher
	@@configuration = Configuration::Defaults.dup
	@@job = nil
	@@logger = nil
	@@queues = Array.new
	public
# Returns the configuration Hash with Symbol keys. 
	def self.configuration
		configure nil 
		@@configuration
	end
# hash_or_path - Set one or more configuration options. If supplied a String, 
# it's assumed to be a path to a JSON or YML file and converted to a Hash. The 
# Hash can use a String or Symbol for each key. See Config for supported keys. 
#
# Returns nothing. 
#
# Raises Error::Configuration if String supplied doesn't have json/yml extension or 
# if *render_directory* is empty.
	def self.configure hash_or_path
		service_config = Hash.new
		queue_config = Hash.new
		service_names = __service_names
		if hash_or_path and not hash_or_path.empty? 
			if hash_or_path.is_a? String
				if File.exists? hash_or_path
					case File.extname hash_or_path
					when '.yml'
						hash_or_path = YAML::load(File.open(hash_or_path))
					when '.json'
						hash_or_path = JSON.parse(File.read(hash_or_path))
					else
						raise Error::Configuration.new "unsupported configuration file type #{hash_or_path}"
					end
				end
			end
			if hash_or_path.is_a? Hash and not hash_or_path.empty?
				# grab all keys in configuration starting with aws_, to pass to AWS if needed
				hash_or_path.each do |key_str,v|
					next if v.to_s.empty?
					key_str = key_str.id2name if key_str.is_a? Symbol
					key_str = key_str.dup
					key_sym = key_str.to_sym
					found = false
					service_names.each do |name|
						name_underscore = "#{name}_"
						name_sym = name.to_sym
						if key_str.start_with? name_underscore
							service_config[name_sym] = Hash.new unless service_config[name_sym]
							key_str[name_underscore] = ''
							service_config[name_sym][key_str.to_sym] = v
							found = true
							break
						end
					end
					unless found
						queue_config[key_sym] = v if key_str.start_with? 'queue_'
						@@configuration[key_sym] = v 
					end
				end
			end
		end	
		[:render_directory, :download_directory, :queue_directory, :error_directory, :log_directory].each do |sym|
			if @@configuration[sym] and not @@configuration[sym].empty? then
				# expand directory and create if needed
				@@configuration[sym] = File.expand_path(@@configuration[sym])
				__file_safe @@configuration[sym]
				if :log_directory == sym and service_config[:aws]
					service_config[:aws][:logger] = Logger.new Path.concat(@@configuration[sym], 'moviemasher.rb.aws.log')
				end
			else
				raise Error::Configuration.new "#{sym.id2name} must be defined" if :render_directory == sym
			end
		end
		service_names.each do |name|
			name_sym = name.to_sym
			if service_config[name_sym]
				class_sym = "#{name.capitalize}Service".to_sym
				unless MovieMasher.const_defined? class_sym
					puts "loading service #{name}"
					require_relative "../service/#{name}"
					raise Error::Configuration.new "MovieMasher::#{class_sym.id2name} not defined" unless MovieMasher.const_defined? class_sym
					queue_class = MovieMasher.const_get class_sym
					queue_instance = queue_class.new
					queue_instance.configure_service service_config[name_sym]
					queue_instance.configure_queue queue_config
					@@queues << queue_instance
				end
			end
		end
	end
# Returns valediction for command line apps.
	def self.goodbye
		"#{Time.now} #{self.name} done"
	end
# Returns salutation for command line apps.
	def self.hello 
		"#{Time.now} #{self.name} version #{VERSION}"
	end
# object_or_path - Job object or String/Hash to be passed to Job.new along 
# with ::configuration. After the MovieMasher::Job#process method is called, its render 
# directory is either moved to *error_directory* (if that option is not empty 
# and a problem arose during processing) or deleted (unless 
# *render_save* is true). The *download_directory* will also be pruned 
# to assure its size is not greater than *download_bytes*. 
#
# Returns Job object with *error* key set if problem arose.
# Raises Error::Configuration if *render_directory* is empty.
	def self.process object_or_path
		result = @@job = (object_or_path.is_a?(Job) ? object_or_path : Job.new(object_or_path))
		begin # try to process job
			@@job.process unless @@job[:error]
		rescue Exception => e 
			__log_exception e
		end
		begin # try to move or remove job's render directory
			job_directory = Path.concat configuration[:render_directory], @@job.identifier
			if File.directory? job_directory then
				if @@job[:error] and configuration[:error_directory] and not configuration[:error_directory].empty? then
					FileUtils.mv job_directory, configuration[:error_directory]
				else
					FileUtils.rm_r job_directory unless configuration[:render_save]
				end
			end
		rescue Exception => e
			__log_exception e
		ensure
			@@job = nil
		end
		begin # try to flush the download directory
			directory = @@configuration[:download_directory]
			directory = @@configuration[:render_directory] unless directory and not directory.empty?
			__flush_downloads directory, configuration[:download_bytes]
		rescue Exception => e
			__log_exception e
		end
		result # what was @@job
	end
# Calls process for each item in array
	def self.process_jobs array # of job strings or paths
		array.each do |job_str|
			process job_str
		end
		(array.empty? ? nil : array.length)
	end
# Loops for *process_seconds* searching for the oldest JSON or YML 
# formatted job file in *queue_directory*, as well as polling *queue_url* for an 
# SQS message. If the later is found its body is expected to be a JSON formatted 
# job and its identifier is used to populate the *id* key (if that's empty), as 
# well as the basename of the file saved to the *queue_directory*. The message is 
# immediately deleted from the queue. 
#
# When a file is found its base name is changed to 'working' and its path is
# passed to the ::process method before it's deleted. This method should not
# raise an Exception, but if it does it is not trapped here so queue processing
# will stop and the file will not be deleted. When #process_queues is
# subsequently called the contents of the file are logged as an error before it
# is deleted without retrying. 
#
# Returns nothing.
#
# Raises Error::Configuration if *queue_directory* or *render_directory* is empty.
	def self.process_queues process_seconds = nil
		process_seconds = configuration[:process_seconds] unless process_seconds
		process_seconds = process_seconds.to_i
		how_long = case process_seconds
		when 0
			'disabled'
		when -1
			'once'
		when -2
			'until drained'
		when -3
			'forever'
		else 
			"for #{process_seconds} seconds"
		end
		__log_transcoder(:info) { "process_queues #{how_long}" }
		raise Error::Configuration.new "queue_directory not found in configuration" unless configuration[:queue_directory] and not configuration[:queue_directory].empty?
		start = Time.now
		Dir[Path.concat configuration[:queue_directory], 'working.*'].each do |working_file|
			# if this process didn't create it, we must have crashed on it in a previous run
			__log_transcoder(:error) { "deleting previously active job:\n#{File.read working_file}" }
			File.delete working_file				
		end
		while (0 > process_seconds) or (process_seconds > (Time.now - start))
			found = false
			job_file = Dir[Path.concat configuration[:queue_directory], '*'].sort_by{ |f| File.mtime(f) }.first
			if job_file then
				found = true
				__log_transcoder(:info) { "starting #{job_file}" }
				working_file = Path.concat File.dirname(job_file), "working#{File.extname job_file}"
				File.rename job_file, working_file
				process working_file
				__log_transcoder(:info) { "finishing #{job_file}" }
				File.delete working_file
			else # see if one can be copied from a queue
				if (0 > process_seconds) or (process_seconds > (Time.now + configuration[:queue_wait_seconds] - start))
					@@queues.each do |queue|
						job_data = queue.receive_job
						if job_data
							found = true
							__log_transcoder(:info) { "starting #{job_data[:id]}" }
							process job_data 
							__log_transcoder(:info) { "finishing #{job_data[:id]}" }
							break
						end
					end
				end
			end
			break if -1 == process_seconds
			break if -2 == process_seconds and not found
			sleep 0.01
		end
	end
	private
	def self.__execute options
		cmd = options[:command]
		app = options[:app] || 'ffmpeg'
		whole_cmd = @@configuration["#{app}_path".to_sym]
		whole_cmd = app unless whole_cmd and not whole_cmd.empty?
		whole_cmd += ' ' + cmd
		Open3.capture3(whole_cmd).join "\n"
	end
	def self.__file_safe path
		unless File.directory? path
			options = Hash.new
			mod = @@configuration[:chmod_directory_new]
			if mod
				mod = mod.to_i(8) if mod.is_a? String
				options[:mode] = mod 
			end
			FileUtils.makedirs path, options
		end
	end
	def self.__flush_downloads(dir, size)
		result = false
		if File.exists?(dir) then
			size = '0M' unless size and not size.to_s.empty?
			size = size.to_s
			number = size[0...-1]
			char = size[-1, 1].upcase
			multiplier = case char
			when 'K'
				1024
			when 'M'
				1024 ** 2
			when 'G'
				1024 ** 3
			else
				number = size
				1
			end
			number = 0 unless number.to_i.to_s == number
			target_bytes = number.to_i * multiplier
			bytes_in_dir = __flush_directory_bytes(dir)
			bytes_to_flush = bytes_in_dir - target_bytes
			
			result = __flush_bytes_from_directory(dir, bytes_in_dir, target_bytes) if (bytes_in_dir > target_bytes)
		end
		result
	end
	def self.__flush_bytes_from_directory download_directory, bytes_in_dir, target_bytes
		bytes_to_flush = bytes_in_dir - target_bytes
		cmd = "-d 1 -k #{download_directory}"
		result = __execute :command => cmd, :app => 'du'
		if result then
			directories = Array.new
			lines = result.split "\n"
			lines.each do |line|
				next unless line and not line.empty?
				bits = line.split "\t"
				next if ((bits.length < 2) || (! bits[1]) || bits[1].empty?)
				dir = bits[1]
				next if (dir == download_directory)
				next unless File.directory? dir
				downloaded_at_file = Path.concat dir, "#{Info::Downloaded}.#{Info::At}.#{Info::Extension}"
				if File.exists? downloaded_at_file then
					at = File.read(downloaded_at_file).to_i
					directories << {:at => at, :bytes => bits.first.to_i * 1024, :dir => dir} if 0 < at
				end
			end
			unless directories.empty?
				directories.sort! { |a,b| a[:at] <=> b[:at] }				
				directories.each do |dir|
					bytes_in_dir -= dir[:bytes]
					bytes_to_flush -= dir[:bytes]
					FileUtils.rm_r dir[:dir]
					break if (bytes_to_flush <= 0) 
				end
			end
		end
		(bytes_to_flush <= 0)
	end
	def self.__flush_directory_bytes(dir)
		size = 0
		cmd = "-d 0 -k #{dir}"
		result = __execute :command => cmd, :app => 'du'
		if result then
			result = result.split "\t"
			result = result.first
			size += result.to_i * 1024 if result.to_i.to_s == result
		end
		size
	end
	def self.__log type, &proc
		 @@job.log_entry(type, &proc) if @@job
		__log_transcoder(type, &proc) if 'debug' == configuration[:verbose]
	end
	def self.__logger
		unless @@logger
			log_dir = @@configuration[:log_directory]
			if log_dir and not log_dir.empty?
				__file_safe log_dir
				@@logger = Logger.new(Path.concat(log_dir, 'moviemasher.rb.log'), 7, 1048576 * 100)
				log_level = (@@configuration[:verbose] || 'info').upcase
				@@logger.level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
			end
		end
		@@logger
	end
	def self.__log_exception(rescued_exception, is_warning = false)
		if rescued_exception then
			unless rescued_exception.is_a? Error::Job
				str =  "#{rescued_exception.backtrace.join "\n"}\n#{rescued_exception.message}" 
				puts str # so it gets in cron log as well
				__log_transcoder(:error) { str }
			end
			__log(:debug) { rescued_exception.backtrace.join "\n" }
			__log(is_warning ? :warn : :error) { rescued_exception.message }
		end
		nil # so we can assign in a oneliner
	end
	def self.__log_transcoder type, &proc
		puts proc.call
		#STDOUT.flush
	
		logger = __logger
		if logger and logger.send((type.id2name + '?').to_sym)
			logger.send(type, proc.call)
		end
	end
	def self.__service_names
		Dir["#{__dir__}/../service/*.rb"].map { | path | File.basename path, '.rb' }
	end
end
