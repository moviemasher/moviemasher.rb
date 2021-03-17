# frozen_string_literal: true

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
#   MovieMasher.configure(render_directory: './temp')
#   MovieMasher.process('./job.json')
#   # => #<MovieMasher::Job::Instance:0x007fa34300abc0>
module MovieMasher
  class << self
    attr_accessor :__config, :__job, :__logger

    # Returns the configuration Hash with Symbol keys.
    def configuration
      MovieMasher.__config || configure
    end

    # hash_or_path - Set one or more configuration options. If supplied a
    # String, it's assumed to be a path to a JSON or YML file and converted to a
    # Hash. The Hash can use a String or Symbol for each key. See Config for
    # supported keys.
    #
    # Returns nothing.
    #
    # Raises Error::Configuration if String supplied doesn't have json/yml
    # extension or if *render_directory* is empty.
    def configure(hash_or_path = nil)
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
    def goodbye
      "#{Time.now} #{name} done"
    end

    # Returns salutation for command line apps.
    def hello
      "#{Time.now} #{name} version #{VERSION}"
    end

    # job_hash_or_path - job, string, or hash to be passed to Job.create along
    # with ::configuration. After the job's process method is called,
    # its render directory is either moved to *error_directory* (if that option
    # is not empty and a problem arose during processing) or deleted (unless
    # *render_save* is true). The *download_directory* will also be pruned to
    # assure its size is not greater than *download_bytes*.
    #
    # Returns job object with *error* key set if problem arose.
    # Raises Error::Configuration if *render_directory* is empty.
    def process(job_hash_or_path)
      result = MovieMasher.__job = Job.create(job_hash_or_path) 
      # try to process job
      begin
        MovieMasher.__job.process unless MovieMasher.__job[:error]
      rescue StandardError => e
        __log_exception(e)
      end
      # try to move or remove job's render directory
      begin
        job_dir = Path.concat(
          configuration[:render_directory], result.identifier
        )
        if File.directory?(job_dir)
          if result[:error] && !configuration[:error_directory].to_s.empty?
            FileUtils.mv(job_dir, configuration[:error_directory])
          else
            FileUtils.rm_r(job_dir) unless configuration[:render_save]
          end
        end
      rescue StandardError => e
        __log_exception(e)
      ensure
        MovieMasher.__job = nil
      end
      __flush
      result # what was MovieMasher.__job
    end

    # Calls process for each item in array
    # of job strings or paths
    def process_jobs(array)
      array.each do |job_str|
        process job_str
      end
      (array.empty? ? nil : array.length)
    end

    # Searches configured queue(s) for job(s) and processes.
    #
    # process_seconds - overrides this same configuration option. A positive
    # value will cause the method to loop that many seconds, while a value of
    # zero will cause it to immediately return without searching for a job. A
    # value of -1 indicates that each queue should be searched just once for a
    # job, and -2will loop until no queue returns a job. And finally, -3 will
    # cause the method to loop forever.
    #
    # This method should not raise an Exception, but if it does it is not
    # trapped here so queue processing will stop.
    #
    # Returns nothing.
    #
    # Raises Error::Configuration if *queue_directory* or *render_directory* is
    # empty.
    def process_queues(process_seconds = nil)
      process_seconds ||= configuration[:process_seconds]
      process_seconds = process_seconds.to_i
      __log_process(process_seconds)
      start = Time.now
      while process_seconds.negative? || (process_seconds > (Time.now - start))
        found = false
        Service.queues.each do |queue|
          job_data = queue.receive_job
          next unless job_data

          found = true
          __log_transcoder(:debug) { "starting #{job_data[:id]}" }
          process(job_data)
          __log_transcoder(:debug) { "finishing #{job_data[:id]}" }
          break
        end
        break if process_seconds == -1
        break if process_seconds == -2 && !found

        sleep(0.01)
      end
    end

    private

    def __configuration_from_file(hash_or_path)
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

    def __configure_directories
      %i[
        render_directory download_directory queue_directory
        error_directory log_directory
      ].each do |sym|
        if MovieMasher.__config[sym].to_s.empty?
          if %i[render_directory queue_directory].include?(sym)
            raise(Error::Configuration, "#{sym.id2name} must be defined")
          end
        else
          # expand directory and create if needed
          MovieMasher.__config[sym] = File.expand_path(
            MovieMasher.__config[sym]
          )
          FileHelper.safe_path(
            MovieMasher.__config[sym],
            MovieMasher.__config[:chmod_directory_new]
          )
        end
      end
    end

    def __flush
      directory = MovieMasher.__config[:download_directory].to_s
      directory = MovieMasher.__config[:render_directory] if directory.empty?
      __flush_downloads(directory, configuration[:download_bytes])
    rescue StandardError => e
      __log_exception(e)
    end

    def __bytes_in_directory(download_directory)
      hash = {}
      cmd = "-d 1 -k #{download_directory}"
      result = ShellHelper.execute(command: cmd, app: 'du')
      return hash unless result

      result.split("\n").each do |line|
        next unless line && !line.empty?

        bits = line.split("\t")
        next if bits.length < 2 || bits[1].to_s.empty?

        dir = bits[1]
        next if dir == download_directory || !File.directory?(dir)

        hash[dir] = bits.first.to_i * 1024
      end
      hash
    end

    def __flush_bytes_from_directory(download_directory, bytes_to_flush)
      bytes_by_directory = __bytes_in_directory(download_directory)
      return true if bytes_by_directory.empty?

      directories = []
      bytes_by_directory.each do |dir, bytes|
        file_name = "#{Info::DOWNLOADED}.#{Info::AT}.#{Info::EXTENSION}"
        downloaded_at_file = Path.concat(dir, file_name)
        next unless File.exist?(downloaded_at_file)

        at = File.read(downloaded_at_file).to_i
        next unless at.positive?

        directories << { at: at, bytes: bytes, dir: dir }
      end
      !__flush_directories(directories, bytes_to_flush).negative?
    end

    def __flush_directories(directories, bytes_to_flush)
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

    def __flush_directory_bytes(dir)
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

    def __flush_downloads(dir, size)
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
        dir_bytes = __flush_directory_bytes(dir)
        if dir_bytes >= target_bytes
          result = __flush_bytes_from_directory(dir, dir_bytes - target_bytes)
        end
      end
      result
    end

    def __log(type, &proc)
      MovieMasher.__job&.log_entry(type, &proc)
      __log_transcoder(type, &proc)
    end

    def __log_exception(exception)
      if exception
        unless exception.is_a?(Error::Job)
          str = "#{exception.backtrace.join "\n"}\n#{exception.message}"
          puts str # so it gets in cron log as well
          $stdout.flush
          __log_transcoder(:error) { str }
        end
        __log(:debug) { exception.backtrace.join "\n" }
        __log(:error) { exception.message }
      end
      nil # so we can assign in a oneliner
    end

    def __log_process(process_seconds)
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
      __log_transcoder(:debug) { "process_queues #{how_long}" }
    end

    def __log_transcoder(type, &proc)
      puts proc.call if configuration[:verbose] == 'debug'
      $stdout.flush
      logger = __logger_instance
      return unless logger&.send("#{type.id2name}?".to_sym)

      logger.send(type, proc.call)
    end

    def __logger_instance
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
end
