module MovieMasher
  # Represents a single transcoding operation. Once #process is called all of
  # the job's #inputs are downloaded and combined together into one mashup,
  # which is then rendered into each of the formats specified by the job's
  # #outputs.
  #
  # These rendered files are then uploaded to the job's #destination, or to the
  # output's if it has one defined. At junctures during processing the job's
  # #callbacks are requested, so as to alert remote systems of job status.
  #
  #   # construct a job and process it
  #   job = Job.new('./job.json', render_directory: './temp')
  #   job.process
  #   # => true
  #   job[:duration]
  #   # => 360
  #   job.progress
  #   # => {
  #     rendering: 1,
  #     uploading: 1,
  #     downloading: 1,
  #     downloaded: 1,
  #     rendered: 1,
  #     uploaded: 1
  #   }
  class Job < Hashable
    def self.create(hash = nil)
      (hash.is_a?(Job) ? hash : Job.new(hash))
    end
    def self.__init_hash(job)
      job[:progress] = Hash.new { 0 }
      Hashable._init_key(job, :id, SecureRandom.uuid)
      Hashable._init_key(job, :inputs, [])
      Hashable._init_key(job, :outputs, [])
      Hashable._init_key(job, :callbacks, [])
      Hashable._init_key(job, :commands, []) # stores commands as executed
      Hashable._init_key(job, :results, []) # stores results of commands
      job
    end
    def audio_graphs
      @cached_audio_graphs ||= Input.audio_graphs(inputs)
    end
    def base_source
      _get(__method__)
    end
    # Transfer - Resolves relative paths within Input#source and Media#source
    #            String values.
    def base_source=(value)
      _set(__method__, value)
    end
    # Array - Zero or more Callback objects.
    def callbacks
      _get(__method__)
    end
    def destination
      _get(__method__)
    end
    # Destination - Shared by all Output objects that haven't one of their own.
    def destination=(value)
      _set(__method__, value)
    end
    def error
      _get(__method__)
    end
    # Problem encountered during #new or #process. If the source of the problem
    # is a command line application then lines from its output that include
    # common phrases will be included. Problems encountered during rendering of
    # optional outputs are not included - check #log for a warning instead.
    #
    # Returns String that could be multiline and/or quite long.
    def error=(value)
      _set(__method__, value)
    end
    def error?
      preflight
      err = error
      err ||= (inputs.empty? ? 'no inputs specified' : nil)
      err ||= (outputs.empty? ? 'no outputs specified' : nil)
      err ||= callbacks.find(&:error?)
      err ||= inputs.find(&:error?)
      err ||= outputs.find(&:error?)
      found_destination = destination || outputs.any?(&:destination)
      err ||= 'no destinations specified' unless found_destination
      err ||= destination.error? if destination
      err ||= base_source.error? if base_source
      err ||= module_source.error? if module_source
      self.error = err
    end
    # String - user supplied identifier.
    # Default - Nil, or messageId if the Job originated from an SQS message.
    def id
      _get(__method__)
    end
    # Create a new Job object from a nested structure or a file path.
    #
    # hash_or_path - Hash or String expected to be a path to a JSON or YML file,
    # which will be parse to the Hash.
    def initialize(hash_or_path)
      @logger = nil
      @cached_audio_graphs = nil
      @cached_video_graphs = nil
      super Hashable.resolved_hash(hash_or_path)
      self.class.__init_hash(@hash)
      path_job = __path_job
      FileHelper.safe_path path_job
      path_log = "#{path_job}/log.txt"
      @hash[:log] = proc { File.read(path_log) }
      # write massaged job json to job directory
      path_job = Path.concat(path_job, 'job.json')
      File.open(path_job, 'w') { |f| f << @hash.to_json }
      # if we encountered a parsing error, log it
      log_entry(:error) { @hash[:error] } if @hash[:error]
    end
    # Array - One or more Input objects.
    def inputs
      _get(__method__)
    end
    # String - Current content of the job's log file.
    def log
      proc = _get(__method__)
      proc.call
    end
    # Output to the job's log file. If *type* is :error then job will be halted
    # and its #error will be set to the result of *proc*.
    #
    # type - Symbol :debug, :info, :warn or :error.
    # proc - Proc returning a string representing log entry.
    def log_entry(type, &proc)
      @hash[:error] = yield if :error == type
      logger_job = __logger
      if logger_job && logger_job.send(:"#{type.id2name}?")
        logger_job.send(type, &proc)
      end
      puts yield if 'debug' == MovieMasher.configuration[:verbose]
    end
    # Array - One or more Output objects.
    def outputs
      _get(__method__)
    end
    def module_source
      _get(__method__)
    end
    # Transfer - Resolves relative font paths within Media#source String values.
    # Default - #base_source
    def module_source=(value)
      _set(__method__, value)
    end
    def output_path(output, no_trailing_slash = false)
      path = Path.concat(__path_job, output.identifier)
      path = Path.add_slash_end(path) unless no_trailing_slash
      path
    end
    def outputs_desire
      desired = nil
      outputs.each do |output|
        desired = AV.merge(output[:av], desired)
      end
      desired
    end
    def preflight
      self.destination = Destination.create_if destination # must say self. here
      self.base_source = Transfer.create_if base_source
      self.module_source = Transfer.create_if module_source
      inputs.map! do |input|
        input = Input.create input
        input.preflight self
        input
      end
      outputs.map! do |output|
        output = Output.create output
        output.preflight self
        output
      end
      callbacks.map! do |callback|
        Callback.create callback
      end
    end
    # Downloads assets for each Input, renders each Output and uploads to
    # #destination or Output#destination so long as #error is false.
    #
    # Returns true if processing succeeded, otherwise false - check #error for
    # details.
    def process
      rescued_exception = nil
      begin
        error?
        __init_progress unless error
        __process_download unless error
        __process_render unless error
        __process_upload unless error
      rescue => e
        rescued_exception = e
      end
      begin
        if error || rescued_exception
          # encountered a showstopper (not one raised from optional output)
          rescued_exception = __log_exception(rescued_exception)
          __callback(:error)
        end
      rescue => e
        rescued_exception = e
      end
      begin
        __log_exception(rescued_exception)
        __callback(:complete)
      rescue => e
        puts "CAUGHT #{e.is_a?(Error::Job)} #{e.message} #{e.backtrace}"
        # no point in logging after complete
      end
      !error
    end
    # Current status of processing. The following keys are available:
    #
    # :downloading - number of files referenced by inputs
    # :downloaded - number of input files transferred
    # :rendering - number of outputs to render
    # :rendered - number of outputs rendered
    # :uploading - number of files referenced by outputs
    # :uploaded - number of output files transferred
    # :calling - number of non-progress callbacks to trigger
    # :called - number of non-progress callbacks triggered
    #
    # Initial values for keys ending on 'ing' are based on information supplied
    # in the job description and might change after #process is called. For
    # instance, if a mash input uses a remote source then *downloading* might
    # increase once it's downloaded and parsed for nested media files.
    #
    # Returns Hash object with Symbol keys and Integer values.
    def progress
      _get(__method__)
    end
    def render_path(output)
      path = ''
      if Type::SEQUENCE == output[:type]
        path = "/#{output[:name]}#{output[:sequence]}"
      end
      path = "#{path}.#{output[:extension]}"
      path = Evaluate.value(path, job: self, output: output)
      "#{output_path(output, true)}#{path}"
    end
    def video_graphs
      @cached_video_graphs ||= Input.video_graphs(inputs, self)
    end
    def __assure_sequence_complete(output)
      if Type::SEQUENCE == output[:type]
        output[:rendered_file] = File.dirname(output[:rendered_file])
        Output.sequence_complete(output)
      else
        true
      end
    end
    def __cache_asset(asset) # input or media
      url_path = Asset.download_asset(asset, self)
      return unless url_path
      progress[:downloaded] += 1
      __callback(:progress)
    end
    def __callback(type)
      log_entry(:debug) { "__callback #{type.id2name}" }
      did_trigger = false
      type_str = type.id2name
      type_callbacks = @hash[:callbacks].select { |c| type_str == c[:trigger] }
      type_callbacks.each do |callback|
        dont_trigger = false
        if :progress == type
          called = callback[:called]
          next if called && called + callback[:progress_seconds] > Time.now
          callback[:called] = Time.now
        else
          dont_trigger = callback[:called]
          callback[:called] = true unless dont_trigger
        end
        next if dont_trigger
        did_trigger = true
        data = __hash_or_array(callback)
        trigger_error = __callback_request(data, callback)
        progress[:called] += 1 unless :progress == type
        if trigger_error && callback[:required]
          log_entry(:error) { trigger_error }
        end
      end
      did_trigger
    end
    def __callback_request(data, callback)
      err = nil
      begin
        destination_path = callback.full_path
        destination_path = Evaluate.value(destination_path, job: self, callback: callback)
        case callback[:type]
        when Type::FILE
          FileHelper.safe_path(File.dirname(destination_path))
          callback[:callback_file] = destination_path
          if data
            file = Path.concat(__path_job, "callback-#{SecureRandom.uuid}.json")
            File.open(file, 'w') { |f| f.write(data.to_json) }
            Transfer.file(callback[:method], file, destination_path)
          end
        when Type::HTTP, Type::HTTPS
          uri = URI(callback.url)
          uri.port = callback[:port].to_i if callback[:port]
          uri.query = Transfer.query_string(callback, self)
          # __transfer_uri_parameters(callback, uri, callback)
          req = nil
          if data
            headers = { 'Content-Type' => 'application/json' }
            req = Net::HTTP::Post.new(uri, headers)
            log_entry(:debug) { "posting callback #{uri}" }
            req.body = data.to_json
          else
            # simple get request
            log_entry(:debug) { "getting callback #{uri}" }
            req = Net::HTTP::Get.new(uri)
          end
          if callback[:user] && callback[:pass]
            req.basic_auth(callback[:user], callback[:pass])
          end
          use_ssl = (uri.scheme == 'https')
          Net::HTTP.start(uri.host, uri.port, use_ssl: use_ssl) do |http|
            result = http.request(req)
            err = __result_error(result)
          end
        else
          err = "unsupported callback type #{callback[:type]}"
        end
      rescue => e
        err = e.message
        puts "CAUGHT #{e.is_a?(Error::Job)} #{e.message} #{e.backtrace}"
      end
      log_entry(:warn) { err } if err
      err
    end
    def __evaluated_transfer_path(output_dest, output)
      file_name = output_dest.file_name
      if file_name.empty?
        # transfer didn't supply one
        file_name = output[:path]
        unless Type::SEQUENCE == output[:type]
          file_name = Path.concat(file_name, output.file_name)
        end
      end
      key = Path.concat(output_dest[:directory], output_dest[:path])
      key = Path.concat(key, file_name)
      key = Evaluate.value(key, job: self, output: output)
      key
    end
    def __execute_and_log(options)
      # retrieve command before execution, so we can log before problems
      command = ShellHelper.command(options)
      log_entry(:debug) { command }
      @hash[:commands] << command
      result = ShellHelper.capture(command)
      log_entry(:debug) { result }
      @hash[:results] << result
      logs = ShellHelper.raise_unless_rendered(result, command, options)
      logs.each do |hash|
        hash.each do |sym, proc|
          log_entry(sym, &proc)
        end
      end
      result
    end
    def __execute_output_command(output, cmd_hash)
      out_path = cmd_hash[:file]
      content = cmd_hash[:content]
      FileHelper.safe_path(File.dirname(out_path))
      if content
        File.open(out_path, 'w') { |f| f << content }
      elsif !File.exist?(out_path)
        cmd = cmd_hash[:command]
        duration = cmd_hash[:duration]
        precision = cmd_hash[:precision]
        app = cmd_hash[:app]
        do_single_pass = !cmd_hash[:pass]
        unless do_single_pass
          pl = Path.concat(__path_job, "pass-#{SecureRandom.uuid}") #
          cmd_1 = "#{cmd} -pass 1 -passlogfile #{pl} -f #{output[:extension]}"
          cmd_2 = "#{cmd} -pass 2 -passlogfile #{pl}"
          begin
            __execute_and_log(app: app, command: cmd_1, file: '/dev/null')
            __execute_and_log(
              app: app, command: cmd_2, file: out_path,
              duration: duration, precision: precision
            )
          rescue => e
            puts "CAUGHT #{e.is_a?(Error::Job)} #{e.message} #{e.backtrace}"
            log_entry(:debug) { e.message }
            log_entry(:warn) { 'two pass encoding failed, retrying in one' }
            do_single_pass = true
          end
        end
        __execute_and_log(cmd_hash) if do_single_pass
      end
    end
    def __hash_or_array(callback)
      data = callback[:data]
      data = nil unless data.is_a?(Hash) || data.is_a?(Array)
      if data
        data = Marshal.load(Marshal.dump(data))
        Evaluate.object(data, job: self, callback: callback)
      end
      data
    end
    def __init_progress
      # clear existing progress, but not error (allows callback testing)
      self[:progress] = Hash.new { 0 }
      progress[:rendering] += outputs.length
      progress[:uploading] += outputs.length
      inputs.each do |input|
        if input[:input_url]
          progress[:downloading] += 1
        elsif Type::MASH == input[:type]
          mash = input.mash
          progress[:downloading] += (mash ? mash.url_count(outputs_desire) : 1)
        end
      end
      progress_callbacks = callbacks.select { |c| 'progress' == c[:trigger] }
      progress[:calling] += progress_callbacks.length
    end
    def __input_dimensions
      dimensions = nil
      found_mash = false
      inputs.each do |input|
        case input[:type]
        when Type::MASH
          found_mash = true
        when Type::IMAGE, Type::VIDEO
          dimensions = input[:dimensions]
        end
        break if dimensions
      end
      dimensions = '' if !dimensions && found_mash
      dimensions
    end
    def __logger
      unless @logger
        log_dir = __path_job
        FileHelper.safe_path(log_dir)
        @logger = Logger.new(Path.concat(log_dir, 'log.txt'))
        ll = @hash[:log_level]
        ll = MovieMasher.configuration[:verbose] if ll.to_s.empty?
        ll = 'info' if ll.to_s.empty?
        ll = ll.upcase
        ll = (Logger.const_defined?(ll) ? Logger.const_get(ll) : Logger::INFO)
        @logger.level = ll
      end
      @logger
    end
    def __log_exception(exception, is_warning = false)
      if exception
        unless exception.is_a?(Error::Job)
          str = "#{exception.backtrace.join "\n"}\n#{exception.message}"
          puts str # so it gets in cron log as well
        end
        log_entry(:debug) { exception.backtrace.join("\n") }
        log_entry(is_warning ? :warn : :error) { exception.message }
      end
      nil
    end
    def __output_commands(output)
      ShellHelper.set_output_commands(self, output) unless output[:commands]
      output[:commands]
    end
    def __path_job
      path = MovieMasher.configuration[:render_directory]
      path = Path.concat(path, identifier)
      Path.add_slash_end(path)
    end
    def __process_download
      __callback(:initiate)
      desired = outputs_desire
      inputs.each do |input|
        input_url = input[:input_url]
        type = input[:type]
        if input_url
          if Type::MASH == type || AV.includes?(Asset.av_type(input), desired)
            # we won't know if desired content types exist until cached & parsed
            __cache_asset(input)
            if Type::MASH == type
              # read and parse mash json file
              input[:mash] = JSON.parse(File.read(input[:cached_file]))
              Mash.init_mash_input(input)
              progress[:downloading] += input.mash.url_count(outputs_desire)
            end
          end
        end
        if Type::MASH == type && AV.includes?(Asset.av_type(input), desired)
          input[:mash][:media].each do |media|
            next unless Type::ASSETS.include?(media[:type])
            next unless AV.includes?(Asset.av_type(media), desired)
            __cache_asset(media)
          end
        end
        break if @hash[:error]
      end
      @hash[:duration] = TimeRange.update(inputs, outputs)
      __update_sizing
    end
    def __process_render
      outputs.each do |output|
        begin
          cmds = __output_commands(output)
          raise(Error::JobInput, 'could not build commands') if cmds.empty?
          # we only added one for each output, so add more minus one
          progress[:rendering] += cmds.length - 1
          if Type::SEQUENCE == output[:type]
            # sequences have additional uploads, which we can now calculate
            frames = output[:video_rate].to_f * output[:duration]
            progress[:uploading] += frames.floor.to_i - 1
          end
          last_file = nil
          cmds.each do |cmd_hash|
            last_file = cmd_hash[:file]
            __execute_output_command(output, cmd_hash)
            progress[:rendered] += 1
            __callback(:progress)
          end
          output[:rendered_file] = last_file
          unless __assure_sequence_complete(output)
            raise(Error::JobRender, 'no sequence files generated')
          end
        rescue Error::Job => e
          __log_exception(e, !output[:required])
          raise if output[:required]
        end
      end
    end
    def __process_upload
      outputs.each do |output|
        next unless output[:rendered_file]
        begin
          __transfer_job_output(output)
        rescue Error::Job => e
          __log_exception(e, !output[:required])
          raise if output[:required]
        end
      end
    end
    def __result_error(result)
      if '200' == result.code
        log_entry(:debug) { "callback OK response: #{result.body}" }
        nil
      else
        "callback ERROR #{result.code} response: #{result.body}"
      end
    end
    def __transfer_job_output(output)
      rendered_output = output[:rendered_file]
      output_dest = output[:destination] || destination
      raise(Error::JobOutput, 'no destination defined') unless output_dest
      if File.exist?(rendered_output)
        archiving = output_dest[:archive] || output[:archive]
        if archiving
          # rendered_output = "#{rendered_output}.#{archiving}"
          # change extension and mime type too?
          raise(Error::Todo, 'support for archive option coming...')
        end
        options = {
          job: self, output: output,
          path: __evaluated_transfer_path(output_dest, output)
        }
        output_dest.directory_files(rendered_output).each do |up_file|
          output_dest.upload(options.merge(file: up_file))
          progress[:uploaded] += 1
          __callback(:progress)
        end
      else
        log_entry(:warn) { "output not rendered #{rendered_output}" }
        if output[:required]
          log_entry(:error) { "output not rendered #{rendered_output}" }
        end
      end
    end
    def __update_sizing
      # make sure visual outputs have dimensions, using input's for default
      in_dimensions = nil
      outputs.each do |output|
        next if AV::AUDIO_ONLY == output[:av]
        next if output[:dimensions]
        in_dimensions = __input_dimensions unless in_dimensions
        output[:dimensions] = in_dimensions
      end
    end
  end
end
