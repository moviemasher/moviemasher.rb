
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
require 'securerandom'
require 'yaml'

require_rel '.'

# Handles global configuration and high level processing of Job objects. The
# ::process_queues method will look for jobs in a directory and optionally an
# SQS queue for a period of time, calling ::process for each one found. No
# configuration is required, though be aware that no download cache is
# maintained by default.
#
#   MovieMasher.configure render_directory: './temp'
#   MovieMasher.process './job.json'
#   # => #<MovieMasher::Job:0x007fa34300abc0>
module MovieMasher
  class << self
    attr_accessor :__config
    attr_accessor :__job
    attr_accessor :__logger
  end
  MovieMasher.__config = nil
  MovieMasher.__job = nil
  MovieMasher.__logger = nil
  # Returns the configuration Hash with Symbol keys.
  def self.configuration
    MovieMasher.__config || configure
  end
  # hash_or_path - Set one or more configuration options. If supplied a String,
  # it's assumed to be a path to a JSON or YML file and converted to a Hash. The
  # Hash can use a String or Symbol for each key. See Config for supported keys.
  #
  # Returns nothing.
  #
  # Raises Error::Configuration if String supplied doesn't have json/yml
  # extension or if *render_directory* is empty.
  def self.configure(hash_or_path = nil)
    MovieMasher.__config ||= Configuration::DEFAULTS.dup
    if hash_or_path && !hash_or_path.empty?
      if hash_or_path.is_a?(String)
        hash_or_path = __configuration_from_file(hash_or_path)
      end
      if hash_or_path.is_a?(Hash) && !hash_or_path.empty?
        hash_or_path.each do |key_str, v|
          next if v.to_s.empty?
          key_str = key_str.to_sym if key_str.respond_to?(:to_sym)
          MovieMasher.__config[key_str] = v
        end
      end
    end
    __configure_directories
    Service.configure_services(MovieMasher.__config)
    MovieMasher.__config
  end
  # Returns valediction for command line apps.
  def self.goodbye
    "#{Time.now} #{name} done"
  end
  # Returns salutation for command line apps.
  def self.hello
    "#{Time.now} #{name} version #{VERSION}"
  end
  # object_or_path - Job object or String/Hash to be passed to Job.new along
  # with ::configuration. After the MovieMasher::Job#process method is called,
  # its render directory is either moved to *error_directory* (if that option is
  # not empty and a problem arose during processing) or deleted (unless
  # *render_save* is true). The *download_directory* will also be pruned to
  # assure its size is not greater than *download_bytes*.
  #
  # Returns Job object with *error* key set if problem arose.
  # Raises Error::Configuration if *render_directory* is empty.
  def self.process(object_or_path)
    object_or_path = Job.new(object_or_path) unless object_or_path.is_a?(Job)
    result = MovieMasher.__job = object_or_path
    begin # try to process job
      MovieMasher.__job.process unless MovieMasher.__job[:error]
    rescue => e
      __log_exception(e)
    end
    begin # try to move or remove job's render directory
      job_dir = Path.concat(configuration[:render_directory], result.identifier)
      if File.directory?(job_dir)
        if result[:error] && !configuration[:error_directory].to_s.empty?
          FileUtils.mv(job_dir, configuration[:error_directory])
        else
          FileUtils.rm_r(job_dir) unless configuration[:render_save]
        end
      end
    rescue => e
      __log_exception(e)
    ensure
      MovieMasher.__job = nil
    end
    __flush
    result # what was MovieMasher.__job
  end
  # Calls process for each item in array
  def self.process_jobs(array) # of job strings or paths
    array.each do |job_str|
      process job_str
    end
    (array.empty? ? nil : array.length)
  end
  # Searches configured queue(s) for job(s) and processes.
  #
  # process_seconds - overrides this same configuration option. A positive value
  # will cause the method to loop that many seconds, while a value of zero will
  # cause it to immediately return without searching for a job. A value of -1
  # indicates that each queue should be searched just once for a job, and -2
  # will loop until no queue returns a job. And finally, -3 will cause the
  # method to loop forever.
  #
  # This method should not raise an Exception, but if it does it is not trapped
  # here so queue processing will stop.
  #
  # Returns nothing.
  #
  # Raises Error::Configuration if *queue_directory* or *render_directory* is
  # empty.
  def self.process_queues(process_seconds = nil)
    process_seconds ||= configuration[:process_seconds]
    process_seconds = process_seconds.to_i
    __log_process(process_seconds)
    start = Time.now
    while (0 > process_seconds) || (process_seconds > (Time.now - start))
      found = false
      Service.queues.each do |queue|
        job_data = queue.receive_job
        next unless job_data
        found = true
        __log_transcoder(:info) { "starting #{job_data[:id]}" }
        process(job_data)
        __log_transcoder(:info) { "finishing #{job_data[:id]}" }
        break
      end
      break if -1 == process_seconds
      break if -2 == process_seconds && !found
      sleep(0.01)
    end
  end
  def self.__configuration_from_file(hash_or_path)
    if File.exist?(hash_or_path)
      case File.extname(hash_or_path)
      when '.yml'
        hash_or_path = YAML.load(File.open(hash_or_path))
      when '.json'
        hash_or_path = JSON.parse(File.read(hash_or_path))
      else
        raise(Error::Configuration, "invalid configuration #{hash_or_path}")
      end
    end
    hash_or_path
  end
  def self.__configure_directories
    [
      :render_directory, :download_directory, :queue_directory,
      :error_directory, :log_directory
    ].each do |sym|
      if MovieMasher.__config[sym].to_s.empty?
        if [:render_directory, :queue_directory].include?(sym)
          raise(Error::Configuration, "#{sym.id2name} must be defined")
        end
      else
        # expand directory and create if needed
        MovieMasher.__config[sym] = File.expand_path(MovieMasher.__config[sym])
        FileHelper.safe_path(
          MovieMasher.__config[sym], MovieMasher.__config[:chmod_directory_new]
        )
      end
    end
  end
  def self.__flush
    directory = MovieMasher.__config[:download_directory].to_s
    directory = MovieMasher.__config[:render_directory] if directory.empty?
    __flush_downloads(directory, configuration[:download_bytes])
  rescue => e
    __log_exception(e)
  end
  def self.__flush_bytes_from_directory(download_directory, bytes_to_flush)
    cmd = "-d 1 -k #{download_directory}"
    result = ShellHelper.execute(command: cmd, app: 'du')
    if result
      directories = []
      lines = result.split("\n")
      lines.each do |line|
        next unless line && !line.empty?
        bits = line.split("\t")
        next if bits.length < 2 || bits[1].to_s.empty?
        dir = bits[1]
        next if dir == download_directory
        next unless File.directory?(dir)
        file_name = "#{Info::DOWNLOADED}.#{Info::AT}.#{Info::EXTENSION}"
        downloaded_at_file = Path.concat(dir, file_name)
        next unless File.exist?(downloaded_at_file)
        at = File.read(downloaded_at_file).to_i
        if 0 < at
          directories << { at: at, bytes: bits.first.to_i * 1024, dir: dir }
        end
      end
      bytes_to_flush = __flush_directories(directories, bytes_to_flush)
    end
    (bytes_to_flush <= 0)
  end
  def self.__flush_directories(directories, bytes_to_flush)
    unless directories.empty?
      directories.sort! { |a, b| a[:at] <=> b[:at] }
      directories.each do |dir|
        bytes_to_flush -= dir[:bytes]
        FileUtils.rm_r(dir[:dir])
        break if bytes_to_flush <= 0
      end
    end
    bytes_to_flush
  end
  def self.__flush_directory_bytes(dir)
    size = 0
    cmd = "-d 0 -k #{dir}"
    result = ShellHelper.execute(command: cmd, app: 'du')
    if result
      result = result.split("\t")
      result = result.first
      size += result.to_i * 1024 if result.to_i.to_s == result
    end
    size
  end
  def self.__flush_downloads(dir, size)
    result = false
    if File.exist?(dir)
      size = '0M' unless size && !size.to_s.empty?
      size = size.to_s
      number = size[0...-1]
      char = size[-1, 1].upcase
      multiplier =
        case char
        when 'K'
          1024
        when 'M'
          1024**2
        when 'G'
          1024**3
        else
          number = size
          1
        end
      number = 0 unless number.to_i.to_s == number
      target_bytes = number.to_i * multiplier
      bytes_in_dir = __flush_directory_bytes(dir)
      if bytes_in_dir >= target_bytes
        result = __flush_bytes_from_directory(dir, bytes_in_dir - target_bytes)
      end
    end
    result
  end
  def self.__log(type, &proc)
    MovieMasher.__job.log_entry(type, &proc) if MovieMasher.__job
    __log_transcoder(type, &proc) # if 'debug' == configuration[:verbose]
  end
  def self.__log_exception(exception, is_warning = false)
    if exception
      unless exception.is_a?(Error::Job)
        str = "#{exception.backtrace.join "\n"}\n#{exception.message}"
        puts str # so it gets in cron log as well
        STDOUT.flush
        __log_transcoder(:error) { str }
      end
      __log(:debug) { exception.backtrace.join "\n" }
      __log(is_warning ? :warn : :error) { exception.message }
    end
    nil # so we can assign in a oneliner
  end
  def self.__log_process(process_seconds)
    how_long =
      case process_seconds
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
  end
  def self.__log_transcoder(type, &proc)
    puts proc.call
    STDOUT.flush
    logger = __logger_instance
    if logger && logger.send("#{type.id2name}?".to_sym)
      logger.send(type, proc.call)
    end
  end
  def self.__logger_instance
    unless MovieMasher.__logger
      log_dir = MovieMasher.__config[:log_directory]
      if log_dir && !log_dir.empty?
        FileHelper.safe_path(log_dir)
        log_file = Path.concat(log_dir, 'moviemasher.rb.log')
        MovieMasher.__logger = Logger.new(log_file, 7, 1_048_576 * 100)
        log_level = MovieMasher.__config[:verbose].to_s.upcase
        log_level =
          if log_level.empty? || !Logger.const_defined?(log_level)
            Logger::INFO
          else
            Logger.const_get(log_level)
          end
        MovieMasher.__logger.level = log_level
      end
    end
    MovieMasher.__logger
  end
end
