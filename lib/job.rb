module MovieMasher
# Represents a single transcoding operation. Once #process is called all of the 
# job's #inputs are downloaded and combined together into one mashup, which is 
# then rendered into each of the formats specified by the job's #outputs. 
#
# These rendered files are then uploaded to the job's #destination, or to the 
# output's if it has one defined. At junctures during processing the job's
# #callbacks are requested, so as to alert remote systems of job status. 
#
#   # construct a job and process it
#   job = Job.new './job.json', :render_directory => './temp'
#   job.process
#   # => true
#   job[:duration]
#   # => 360
#   job.progress
#   # => {:rendering=>1, :uploading=>1, :downloading=>1, :downloaded=>1, :rendered=>1, :uploaded=>1}
	class Job < Hashable
		def self.create hash = nil
			(hash.is_a?(Job) ? hash : Job.new(hash))
		end
		def self.resolved_hash hash_or_path
			data = Hash.new
			if hash_or_path.is_a? String
				hash_or_path = resolved_string hash_or_path
				if hash_or_path
					begin
						case string_type hash_or_path
						when 'yaml'
							data = YAML::load hash_or_path
						when 'json'
							data = JSON.parse hash_or_path
						else
							data[:error] = "unsupported configuration file type #{hash_or_path}"
						end
					rescue Exception => e
						data[:error] = "job file could not be parsed: #{e.message}" 
					end
				else
					data[:error] = "job file could not be found: #{hash_or_path}" 
				end
			else
				data = Marshal.load(Marshal.dump(hash_or_path)) if hash_or_path.is_a? Hash
			end
			symbolize_hash! data
			data
		end
		def self.resolved_string hash_or_path
			case string_type hash_or_path
			when 'json', 'yaml'
				hash_or_path 
			else
				(File.exists?(hash_or_path) ? File.read(hash_or_path) : nil)
			end
		end
		def self.string_type hash_or_path
			case hash_or_path[0]
			when '{', '['
				'json'
			when '-'
				'yaml'
			else
				nil
			end
		end
		def self.symbolize_hash! hash
			if hash 
				if hash.is_a? Hash then
					hash.keys.each do |k|
						v = hash[k]
						if k.is_a? String then
							k_sym = k.downcase.to_sym
							hash[k_sym] = v
							hash.delete k
						end
						symbolize_hash! v
					end
				elsif hash.is_a? Array then
					hash.each do |v|
						symbolize_hash! v
					end
				end
			end
			hash
		end
		private
		def self.__audio_from_file path
			raise Error::Parameter.new "__audio_from_file with invalid path" unless path and (not path.empty?) and File.exists? path
			out_file = Path.concat File.dirname(path), "#{File.basename path, File.extname(path)}-intermediate.#{Intermediate::AudioExtension}"
			switches = Array.new
			switches << __switch(path, 'i')
			switches << __switch(2, 'ac')
			switches << __switch(44100, 'ar')
			exec_opts = Hash.new
			exec_opts[:command] = switches.join
			exec_opts[:file] = out_file
			exec_opts
		end
		def self.__init_hash job
			job[:progress] = Hash.new() { 0 }
			Hashable._init_key job, :id, UUID.new.generate
			Hashable._init_key job, :inputs, Array.new
			Hashable._init_key job, :outputs, Array.new
			Hashable._init_key job, :callbacks, Array.new
			Hashable._init_key job, :commands, Array.new # stores commands as executed
			job
		end
	
		def self.__input_length input
			__input_time input, :length
		end
		def self.__input_time input, key
			length = FloatUtil::Zero
			duration = input[:duration].to_f
			if FloatUtil.gtr(input[key], FloatUtil::Zero) then
				symbol = "#{key.id2name}_is_relative".to_sym
				if input[symbol] then
					if FloatUtil.gtr(duration, FloatUtil::Zero) then
						if '%' == input[symbol] then
							length = (input[key] * duration) / FloatUtil::Hundred
						else 
							length = duration - input[key]
						end
					end
				else 
					length = input[key]
				end
			elsif :length == key and FloatUtil.gtr(duration, FloatUtil::Zero) then
				input[key] = duration - __input_trim(input)
				length = input[key]
			end
			length = FloatUtil.precision length
			length
		end
		def self.__input_trim input
			__input_time input, :offset
		end
		def self.__input_trim_range input
			range = TimeRange.new __input_trim(input), 1, 1
			range.length = __input_length input
			range
		end
		def self.__output_command output, av_type, duration = nil
			switches = Array.new
			switches << __switch(FloatUtil.string(duration), 't') if duration
			if AV::Both == av_type or AV::Audio == av_type then # we have audio output
				switches << __switch(output[:audio_bitrate], 'b:a', 'k') if output[:audio_bitrate]
				switches << __switch(output[:audio_rate], 'r:a') if output[:audio_rate]
				switches << __switch(output[:audio_codec], 'c:a') if output[:audio_codec]
			end
			if AV::Both == av_type or AV::Video == av_type then # we have visual output
				case output[:type]
				when Output::TypeVideo
					switches << __switch(output[:dimensions], 's') if output[:dimensions]
					switches << __switch(output[:video_format], 'f:v') if output[:video_format]
					switches << __switch(output[:video_codec], 'c:v') if output[:video_codec]
					switches << __switch(output[:video_bitrate], 'b:v', 'k') if output[:video_bitrate]
					switches << __switch(output[:video_rate], 'r:v') if output[:video_rate]
				when Output::TypeImage
					switches << __switch(output[:quality], 'q:v') if output[:quality]
				when Output::TypeSequence
					switches << __switch(output[:quality], 'q:v') if output[:quality]
					switches << __switch(output[:video_rate], 'r:v') if output[:video_rate]
				end
			end
			switches << __switch(output[:metadata], 'metadata') if output[:metadata]
			switches.join
		end
		def self.__switch(value, prefix = '', suffix = '')
			switch = ''
			value = value.to_s.strip
			if value #and not value.empty? then
				switch += ' ' # always add a leading space
				if value.start_with? '-' then # it's a switch, just include and ignore rest
					switch += value 
				else # prepend value with prefix and space
					switch += '-' unless prefix.start_with? '-'
					switch += prefix
					switch += ' ' + value unless value.empty?
					switch += suffix unless switch.end_with? suffix # note lack of space!
				end
			end
			switch
		end		
		public
		def base_source
			_get __method__
		end
# Transfer - Resolves relative paths within Input#source and Media#source String values.
		def base_source= value
			_set __method__, value
		end
		
# Array - Zero or more Callback objects.
		def callbacks
			_get __method__
		end
		def destination
			_get __method__
		end
# Destination - Shared by all Output objects that don't have one of their own.
		def destination= value
			_set __method__, value
		end
		def error
			_get __method__
		end
# Problem encountered during #new or #process. If the source of the problem is a 
# command line application then lines from its output that include common 
# phrases will be included. Problems encountered during rendering of optional outputs 
# are not included - check #log for a warning instead. 
#
# Returns String that could be multiline and/or quite long. 
		def error=(value)
			_set __method__, value
		end

		def error?	
			preflight
			err = error
			err = 'no inputs specified' if (not err) and inputs.empty?
			err = 'no outputs specified' if (not err) and outputs.empty?
			err = base_source.error? if (not err) and base_source
			err = module_source.error? if (not err) and module_source
			
			callbacks.each do |callback| 
				break if err = callback.error?
			end unless err

			inputs.each do |input| 
				break if err = input.error?
			end unless err
			
			found_destination = !! destination
			outputs.each do |output| 
				break if err = output.error?
				found_destination = true if output.destination
			end unless err
			err = 'no destinations specified' if (not err) and not found_destination
			err = destination.error? if (not err) and destination
			self.error = err
		end
		
# String - user supplied identifier.
# Default - Nil, or messageId if the Job originated from an SQS message. 
		def id
			_get __method__
		end
# Create a new Job object from a nested structure or a file path.
#
# hash_or_path - Hash or String expected to be a path to a JSON or YML file, 
# which will be parse to the Hash. 
		def initialize hash_or_path
			@logger = nil
			@audio_graphs = nil
			@video_graphs = nil
			super self.class.resolved_hash hash_or_path
			self.class.__init_hash @hash
			path_job = __path_job
			FileHelper.safe_path path_job
			path_log = "#{path_job}/log.txt"			
			@hash[:log] = Proc.new { File.read path_log }

			# write massaged job json to job directory
			path_job = Path.concat(path_job, 'job.json')
			File.open(path_job, 'w') { |f| f << @hash.to_json }	
			# if we encountered a parsing error, log it
			log_entry(:error) { @hash[:error] } if @hash[:error]
		end
# Array - One or more Input objects.
		def inputs
			_get __method__
		end
# String - Current content of the job's log file.
		def log
			proc = _get(__method__)
			proc.call
		end
# Output to the job's log file. If *type* is :error then job will be halted and 
# its #error will be set to the result of *proc*.
#
# type - Symbol :debug, :info, :warn or :error.
# proc - Proc returning a string representing log entry.
		def log_entry type, &proc
			@hash[:error] = proc.call if :error == type
			logger_job = __logger
			if logger_job and logger_job.send (type.id2name + '?').to_sym
				logger_job.send(type, &proc)
			end
			puts proc.call if 'debug' == MovieMasher.configuration[:verbose]
		end
# Array - One or more Output objects. 
		def outputs
			_get __method__
		end
		def module_source
			_get __method__
		end
# Transfer - Resolves relative font paths within Media#source String values.
# Default - #base_source
		def module_source= value
			_set __method__, value
		end
		def outputs_desire
			desired = nil
			outputs.each do |output| 
				desired = AV.merge output[:av], desired
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
				__init_progress
				__process_download
				__process_render
				__process_upload
			rescue Exception => e 
				rescued_exception = e
			end
			begin
				if error or rescued_exception then 
					# encountered a showstopper (not one raised from optional output)
					rescued_exception = __log_exception rescued_exception
					__callback :error
				end
			rescue Exception => e
				rescued_exception = e
			end
			begin
				rescued_exception = __log_exception rescued_exception
				__callback :complete
			rescue Exception => e
				rescued_exception = e
			end
			! error
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
# Initial values for keys ending on 'ing' are based on information supplied in 
# the job description and might change after #process is called. For instance, 
# if a mash input uses a remote source then *downloading* might increase once 
# it's downloaded and parsed for nested media files. 
#
# Returns Hash object with Symbol keys and Integer values.
		def progress
			_get __method__
		end
		private
		def __assure_sequence_complete dir_path, result, output
			if File.directory? dir_path then
				first_frame = 1
				frame_count = (output[:video_rate].to_f * output[:duration]).floor.to_i
				padding = (first_frame + frame_count).to_s.length
				last_file = nil
				frame_count.times do |frame_number|
					file_frame = frame_number + first_frame
					file_path = Path.concat dir_path, "#{output[:name]}#{file_frame.to_s.rjust padding, '0'}.#{output[:extension]}"
					if File.exists? file_path then
						last_file = file_path
					else
						if last_file then
							log_entry(:warn) { "copying #{File.basename last_file} to #{File.basename file_path} to fulfill duration of sequence" }
							FileUtils.copy last_file, file_path
						else
							raise Error::JobRender.new result, "could not generate any sequence files"
							break
						end
					end
				end
			end
		end
		def __audio_graphs
			unless @audio_graphs
				@audio_graphs = Array.new
				start_counter = FloatUtil::Zero	
				inputs.each do |input|
					next if input[:no_audio]
					case input[:type]
					when Input::TypeVideo, Input::TypeAudio
						data = Hash.new
						data[:type] = input[:type]
						data[:offset] = input[:offset]
						data[:length] = input[:length]
						data[:start] = input[:start]	
						data[:cached_file] = input[:cached_file]
						data[:duration] = input[:duration]
						data[:gain] = input[:gain]
						data[:loop] = input[:loop]
						@audio_graphs << data
					when Input::TypeMash
						quantize = input[:mash][:quantize]
						audio_clips = Mash.clips_having_audio input[:mash]
						audio_clips.each do |clip|
							media = Mash.media input[:mash], clip[:id]
							raise Error::JobInput.new "could not find media for clip #{clip[:id]}" unless media
							clip[:cached_file] = media[:cached_file] || raise("could not find cached file")
							clip[:duration] = media[:duration]
							clip[:no_audio] = media[:no_audio] unless clip[:no_audio]
							next if clip[:no_audio]
							data = Hash.new
							data[:type] = clip[:type]
							data[:offset] = clip[:offset]
							data[:length] = clip[:length]
							data[:start] = input[:start].to_f + clip[:frame].to_f / quantize.to_f
							data[:cached_file] = clip[:cached_file]
							data[:gain] = clip[:gain]
							data[:duration] = clip[:duration]
							data[:loop] = clip[:loop]
							@audio_graphs << data
						end
					end
				end
			end
			@audio_graphs
		end
		def __cache_asset asset # input or media
		  #puts "__cache_asset #{asset}"
			input_url = asset[:input_url]
			if input_url then
				cache_url_path = __cache_url_path input_url
				unless File.exists? cache_url_path then
					#source = asset.module_source || asset.base_source || asset.source
					#raise Error::JobInput.new "no source for #{input_url}" unless source
					begin
						FileHelper.safe_path(File.dirname(cache_url_path))
						#puts "input_url #{input_url}"
						#puts "cache_url_path #{cache_url_path}"
						asset.download :job => self, :path => cache_url_path
						
#						case source[:type]
#						when Transfer::TypeFile
#							source_path = input_url.dup
#							source_path['file://'] = '' if source_path.start_with?('file://');
#							source_path = File.expand_path(source_path) unless source_path.start_with?('/')
#							if File.exists? source_path
#								__transfer_file(source[:method], source_path, cache_url_path) 
#							else
#								log_entry(:error) { "file does not exist #{source_path}" }
#							end
#						when Transfer::TypeHttp, Transfer::TypeHttps
#							uri = URI input_url
#							uri.port = source[:port] if source[:port]
#							__transfer_uri_parameters asset, uri, source
#							req.basic_auth(source[:user], source[:pass]) if source[:user] and source[:pass]
#							Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
#								request = Net::HTTP::Get.new uri
#								http.request request do |response|
#									if '200' == response.code then
#										File.open(cache_url_path, 'wb') do |io|
#											response.read_body do |chunk|
#												io.write chunk
#											end
#										end
#										mime_type = response['content-type']
#										Info.set(cache_url_path, 'Content-Type', mime_type) if mime_type
#									else
#										log_entry(:warn) {"got #{response.code} response code from #{input_url}"}
#									end
#								end
#							end
#						when Transfer::TypeS3
#							bucket = __s3_bucket source
#							bucket_key = source.full_path
#							object = bucket.objects[bucket_key]
#							if MovieMasher.configuration[:s3_read_at_once] then
#								object_read_data = object.read
#								File.open(cache_url_path, 'wb') { |f| f << object_read_data } if object_read_data
#							else
#								File.open(cache_url_path, 'wb') do |file|
#									object.read do |chunk|
#										file << chunk
#									end
#								end
#							end
#						end
					rescue Exception => e
						puts "CAUGHT #{e.message} #{e.backtrace.join "\n"}"
						raise Error::JobInput.new e.message unless e.is_a? Error::Job
					end
					raise Error::JobInput.new "could not cache #{input_url}" unless File.size?(cache_url_path)
				end
				Info.set cache_url_path, Info::At, Time.now.to_i
				asset[:cached_file] = cache_url_path
				case asset[:type]
				when Input::TypeVideo
					asset[:duration] = Info.get(cache_url_path, Info::Duration).to_f unless asset[:duration] and FloatUtil.gtr(asset[:duration], FloatUtil::Zero)
					asset[:no_audio] = ! Info.get(cache_url_path, Info::Audio)
					asset[:dimensions] = Info.get(cache_url_path, Info::Dimensions)
					asset[:no_video] = ! asset[:dimensions]
					Mash.init_av_input asset
				when Input::TypeAudio
					asset[:duration] = Info.get(cache_url_path, Info::AudioDuration).to_f unless asset[:duration] and FloatUtil.gtr(asset[:duration], FloatUtil::Zero)
					asset[:duration] = Info.get(cache_url_path, Info::VideoDuration).to_f unless FloatUtil.gtr(asset[:duration], FloatUtil::Zero)
				when Input::TypeImage 
					asset[:dimensions] = Info.get(cache_url_path, Info::Dimensions)
					raise Error::JobInput.new "could not determine image dimensions" unless asset[:dimensions]
				end
				progress[:downloaded] += 1
				__callback :progress
			end
		end
		def __cache_url_path url
			directory = MovieMasher.configuration[:download_directory]
			directory = MovieMasher.configuration[:render_directory] unless directory and not directory.empty?
			Path.concat directory, Digest::SHA2.new(256).hexdigest(url) + '/' + Info::Downloaded + File.extname(url)
		end
		def __callback type
			log_entry(:debug) { "__callback #{type.id2name}" }
			did_trigger = false
			type_str = type.id2name
			@hash[:callbacks].each do |callback|
				next unless type_str == callback[:trigger]
				dont_trigger = false
				if :progress == type then
					last_triggered = callback[:called]
					next if last_triggered and last_triggered + callback[:progress_seconds] > Time.now
					callback[:called] = Time.now
				else
					dont_trigger = callback[:called]
					callback[:called] = true unless dont_trigger
				end
				unless dont_trigger
					did_trigger = true
					data = callback[:data] || nil
					if data then
						if data.is_a?(Hash) or data.is_a?(Array) then
							data = Marshal.load(Marshal.dump(data)) 
							Evaluate.object data, __scope(callback)
						else # only arrays and hashes supported
							data = nil  
						end
					end
					trigger_error = __callback_request data, callback
					progress[:called] += 1 unless :progress == type
					log_entry(:error) { trigger_error } if trigger_error and callback[:required]
				end
			end
			did_trigger
		end
		def __callback_request data, callback
			err = nil
			begin
				destination_path = callback.full_path
				destination_path = Evaluate.value destination_path, __scope(callback)
				case callback[:type]
				when Transfer::TypeFile
					FileHelper.safe_path(File.dirname(destination_path))
					callback[:callback_file] = destination_path
					if data then
						file = Path.concat __path_job, "callback-#{UUID.new.generate}.json"
						File.open(file, 'w') { |f| f.write(data.to_json) }
						__transfer_file callback[:method], file, destination_path
					end
				when Transfer::TypeHttp, Transfer::TypeHttps
					url = callback.url
					uri = URI(url)
					uri.port = callback[:port].to_i if callback[:port]
					__transfer_uri_parameters callback, uri, callback
					req = nil
					if data and not data.empty? then
						headers = {"Content-Type" => "application/json"}
						req = Net::HTTP::Post.new(uri, headers)
						log_entry(:debug) {"posting callback #{uri.to_s}"}
						req.body = data.to_json
					else # simple get request
						log_entry(:debug) {"getting callback #{uri.to_s}"}
						req = Net::HTTP::Get.new(uri)
					end
					req.basic_auth(callback[:user], callback[:pass]) if callback[:user] and callback[:pass]
			
					res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
						result = http.request(req)
						if '200' == result.code then
							log_entry(:debug) {"callback OK response: #{result.body}"}
						else
							err = "callback ERROR #{result.code} response: #{result.body}"
						end
					end
				else
					err = "unsupported callback type #{callback[:type]}"
				end
			rescue Exception => e
				err = e.message
			end
			log_entry(:warn) { err } if err
			err
		end
		def __construct_commands
			outputs.each do |output|
				begin
					__output_commands output
				rescue Error::Job => e
					__log_exception e, ! output[:required]
					raise if output[:required]
				end
			end		
		end
		def __evaluated_path_for_transfer output_destination, output
			file_name = output_destination.file_name
			if file_name.empty? 
				# transfer didn't supply one
				file_name = output[:path]
				file_name = Path.concat file_name, output.file_name unless Output::TypeSequence == output[:type]
			end
			key = Path.concat output_destination[:directory], output_destination[:path]
			key = Path.concat key, file_name
			Evaluate.value key, __scope(output)
		end
		def __execute_and_log options
			options[:log] = true
			result, whole_cmd, logs = ShellHelper.execute options
			@hash[:commands] << whole_cmd
			logs.each do |hash|
				hash.each do |sym, proc|
					send(:log_entry, sym, &proc)
				end
			end
			result
		end
		def __execute_output_command output, cmd_hash
			result = nil
			out_path = cmd_hash[:file]
			content = cmd_hash[:content]
			if content
				FileHelper.safe_path File.dirname(out_path)
				File.open(out_path, 'w') { |f| f << content}	
			else			
				unless File.exists? out_path then
					cmd = cmd_hash[:command]
					duration = cmd_hash[:duration]
					precision = cmd_hash[:precision]
					app = cmd_hash[:app]
					do_single_pass = ! cmd_hash[:pass]
					unless do_single_pass then
						pass_log_file = Path.concat __path_job, "pass-#{UUID.new.generate}"
						cmd_pass_1 = "#{cmd} -pass 1 -passlogfile #{pass_log_file} -f #{output[:extension]}"
						cmd_pass_2 = "#{cmd} -pass 2 -passlogfile #{pass_log_file}"
						begin
							__execute_and_log :command => cmd_pass_1, :file => '/dev/null', :app => app
							result = __execute_and_log :command => cmd_pass_2, :file => out_path, :duration => duration, :precision => precision, :app => app
						rescue Exception => e
							log_entry(:debug) { e.message }
							log_entry(:warn) { "unable to encode in two passes, retrying in one" }
							do_single_pass = true
						end
					end
					if do_single_pass then
						result = __execute_and_log cmd_hash
					end
				end
			end
			result
		end
		def __input_dimensions
			dimensions = nil
			found_mash = false
			inputs.each do |input|
				case input[:type]
				when Input::TypeMash
					found_mash = true
				when Input::TypeImage, Input::TypeVideo
					dimensions = input[:dimensions]
				end
				break if dimensions
			end
			dimensions = '' if ((! dimensions) && found_mash) 
			dimensions
		end
		def __logger
			unless @logger
				log_dir = __path_job
				FileHelper.safe_path log_dir
				@logger = Logger.new(Path.concat log_dir, 'log.txt')
				log_level = @hash[:log_level]
				log_level = MovieMasher.configuration[:verbose] unless log_level and not log_level.empty?
				log_level = 'info' unless log_level and not log_level.empty?
				log_level = log_level.upcase
				log_level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
				@logger.level = log_level
			end
			@logger
		end
		def __log_exception(rescued_exception, is_warning = false)
			if rescued_exception
				unless rescued_exception.is_a? Error::Job
					str =  "#{rescued_exception.backtrace.join "\n"}\n#{rescued_exception.message}" 
					puts str # so it gets in cron log as well
				end
				log_entry(:debug) { rescued_exception.backtrace.join "\n" }
				log_entry(is_warning ? :warn : :error) { rescued_exception.message }
			end
			nil
		end
		def __output_commands output
			unless output[:commands]
				output[:commands] = Array.new
				avb = output[:av]
				v_graphs = (AV::Audio == avb ? Array.new : __video_graphs)
				a_graphs = (AV::Video == avb ? Array.new : __audio_graphs)
				#puts "__output_commands #{a_graphs} #{v_graphs}"
				type_is_video_or_audio = ( (Output::TypeVideo == output[:type]) or (Output::TypeAudio == output[:type]) )
				two_pass = type_is_video_or_audio
				switches = Array.new
				video_duration = FloatUtil::Zero
				audio_duration = FloatUtil::Zero
				out_path = __render_path output
				unless AV::Audio == avb then # we've got video
					if 0 < v_graphs.length then
						switches << self.class.__switch(output[:video_rate], 'r:v') if output[:video_rate]
						if 1 == v_graphs.length 
						# and v_graphs.first.is_a?(RawGraph)
							graph = v_graphs[0]
							video_duration = graph.duration
							cmd = graph.graph_command output, self
							raise Error::JobInput.new "could not build complex filter" if cmd.empty?
							switches << self.class.__switch("'#{cmd}'", 'filter_complex')
						else
							two_pass = false
							concat_switches = Array.new
							concat_files = Array.new
							concat_files << 'ffconcat version 1.0'
							v_graphs.length.times do |index|
								graph = v_graphs[index]
								duration = graph.duration
								
								video_duration += duration
								out_file_name = "concat-#{index}.#{output[:extension]}"
								out_file = "#{__output_path output}#{out_file_name}"
								concat_files << "file '#{out_file_name}'"
								concat_files << "duration #{duration}"
								cmd = graph.graph_command output, self
								raise Error::JobInput.new "Could not build complex filter" if cmd.empty?
								cmd = "-y -filter_complex '#{cmd}' " #-vbsf h264_mp4toannexb 
								cmd += self.class.__output_command output, AV::Video, duration
								exec_opts = Hash.new
								exec_opts[:command] = cmd
								exec_opts[:pass] = true
								exec_opts[:duration] = duration
								exec_opts[:precision] = output[:precision]
								exec_opts[:file] = out_file
								output[:commands] << exec_opts
							end
							file_path = "#{__output_path output}concat.txt"
							exec_opts = Hash.new
							exec_opts[:content] = concat_files.join("\n")
							exec_opts[:file] = file_path
							output[:commands] << exec_opts
							
							switches << self.class.__switch('1', 'auto_convert')
							#switches << self.class.__switch('concat', 'f:v')
							switches << self.class.__switch("'#{file_path}'", 'i')
							switches << self.class.__switch('copy', 'c:v')
							#switches << self.class.__switch(output[:video_bitrate], 'b:v', 'k') if output[:video_bitrate]
							avb = (AV::Video == avb ? AV::Neither : AV::Audio)
							
						end
					else 
						avb = AV::Audio
					end
				end
					
				if AV::Both == avb or AV::Audio == avb then 
					# we want audio
					audio_graphs_count = a_graphs.length
					if 0 < audio_graphs_count then
						# we got audio
						data = a_graphs[0]
						if 1 == audio_graphs_count and 1 == data[:loop] and (not Mash.gain_changes(data[:gain])) and FloatUtil.cmp(data[:start], FloatUtil::Zero) then
							# just one non-looping graph, starting at zero with no gain change
							raise Error::JobInput.new "zero length #{data.inspect}" unless FloatUtil.gtr(data[:length], FloatUtil::Zero)
							audio_duration = data[:length]
							cmd_hash = self.class.__audio_from_file(data[:cached_file])
							output[:commands] << cmd_hash
							data[:waved_file] = cmd_hash[:file] unless data[:waved_file]
						else 
							# merge audio and feed resulting file to ffmpeg
							audio_cmd = ''
							counter = 1
							start_counter = FloatUtil::Zero
							audio_graphs_count.times do |audio_graphs_index|
								data = a_graphs[audio_graphs_index]
								loops = data[:loop] || 1
								volume = data[:gain]
								start = data[:start]
								raise Error::JobInput.new "negative start time #{data.inspect}" unless FloatUtil.gtre(start, FloatUtil::Zero)
								raise Error::JobInput.new "zero length #{data.inspect}" unless FloatUtil.gtr(data[:length], FloatUtil::Zero)
								cmd_hash = self.class.__audio_from_file(data[:cached_file])
								output[:commands] << cmd_hash
								data[:waved_file] = cmd_hash[:file] unless data[:waved_file]
								audio_cmd += " -a:#{counter} -i "
								counter += 1
								audio_cmd += 'audioloop,' if 1 < loops
								audio_cmd += "playat,#{data[:start]},"
								audio_cmd += "select,#{data[:offset]},#{data[:length]}"
								audio_cmd += ",typeselect,.raw,#{data[:waved_file]}"
								audio_cmd += " -t:{FloatUtil.string data[:length]}" if 1 < loops
								if Mash.gain_changes(volume) then
									volume = volume.to_s unless volume.is_a?(String)
									volume = "0,#{volume},1,#{volume}" unless volume.include?(',') 
									volume = volume.split ','
									z = volume.length / 2
									audio_cmd += " -ea:0 -klg:1,0,100,#{z}"
									z.times do |i|
										p = (i + 1) * 2
										pos = volume[p - 2].to_f
										val = volume[p - 1].to_f
										pos = (data[:length] * loops.to_f * pos) if (FloatUtil.gtr(pos, FloatUtil::Zero)) 									
										audio_cmd += ",#{FloatUtil.precision(start + pos)},#{val}"
									end
								end
								audio_duration = FloatUtil.max(audio_duration, data[:start] + data[:length])
							end
							audio_cmd += ' -a:all -z:mixmode,sum'
							audio_cmd += ' -o'
							audio_path = "#{__output_path output}audio-#{Digest::SHA2.new(256).hexdigest audio_cmd}.#{Intermediate::AudioExtension}"
						
							exec_opts = Hash.new
							exec_opts[:command] = audio_cmd
							exec_opts[:file] = audio_path
							exec_opts[:duration] = audio_duration
							exec_opts[:precision] = output[:precision]
							exec_opts[:app] = 'ecasound'
							output[:commands] << exec_opts
						
							data = Hash.new
							data[:type] = Output::TypeAudio
							data[:offset] = FloatUtil::Zero
							data[:length] = audio_duration
							data[:waved_file] = audio_path
						end
						# data is now just one wav file - audio_duration may be less or more than video_duration
						if Output::TypeWaveform == output[:type] then
							dimensions = output[:dimensions].split 'x'
							switches << self.class.__switch(data[:waved_file], '--input')
							switches << self.class.__switch(dimensions.first, '--width')
							switches << self.class.__switch(dimensions.last, '--height')
							switches << self.class.__switch(output[:forecolor], '--linecolor')
							switches << self.class.__switch(output[:backcolor], '--backgroundcolor')
							switches << self.class.__switch('0', '--padding')
							switches << self.class.__switch('', '--output')
						
							exec_opts = Hash.new
							exec_opts[:command] = switches.join
							exec_opts[:file] = out_path
							exec_opts[:app] = 'wav2png'
							output[:commands] << exec_opts
							switches = Array.new
						else
							switches.unshift self.class.__switch(data[:waved_file], 'i')
							unless FloatUtil.cmp(data[:offset], FloatUtil::Zero) and FloatUtil.cmp(data[:length], data[:duration]) then
								switches << self.class.__switch("'atrim=start=#{data[:offset]}:duration=#{audio_duration},asetpts=expr=PTS-STARTPTS'", 'af') 
							end
							switches << self.class.__switch(1, 'async')
			
						end
					else
						avb = (AV::Audio == avb ? AV::Neither : AV::Video)
					end
				end
					
				unless switches.empty? then # we've got audio and/or video
					duration = FloatUtil.max(audio_duration, video_duration)
					cmd = switches.join
					cmd += self.class.__output_command output, avb, (type_is_video_or_audio ? duration : nil)
					cmd = '-y ' + cmd
					exec_opts = Hash.new
					exec_opts[:command] = cmd
					exec_opts[:file] = out_path
					exec_opts[:duration] = duration unless Output::TypeImage == output[:type] or Output::TypeSequence == output[:type]
					exec_opts[:precision] = output[:precision]
					exec_opts[:pass] = two_pass
					output[:commands] << exec_opts
				end
				#puts "__output_commands #{output[:commands]}"
				
				# we only added one for each output, so add more minus one
				progress[:rendering] += output[:commands].length - 1
				# sequences have additional uploads, which we can now calculate
				progress[:uploading] += ((output[:video_rate].to_f * output[:duration]).floor - 1) if Output::TypeSequence == output[:type]
			end
			output[:commands]
		end
		def __output_path output, no_trailing_slash = false
			path = Path.concat __path_job, output.identifier
			path = Path.add_slash_end path unless no_trailing_slash
			path
		end
		def __path_job
			path = Path.concat MovieMasher.configuration[:render_directory], identifier
			Path.add_slash_end path
		end
		def __init_progress
			unless error
				self[:progress] = Hash.new() { 0 } # clear existing progress, but not error (allows callback testing)
				outputs.each do |output| 
					progress[:rendering] += 1
					progress[:uploading] += 1
				end
				desired = outputs_desire
			
				inputs.each do |input|
					if input[:input_url]
						progress[:downloading] += 1
					else
						progress[:downloading] += (input.mash ? input.mash.url_count(outputs_desire) : 1) if Input::TypeMash == input[:type]
					end
				end
				callbacks.each do |callback|
					progress[:calling] += 1 unless 'progress' == callback[:trigger]
				end
			end
		end
		def __process_download
			unless error
				__callback :initiate
				desired = outputs_desire
				inputs.each do |input|
					input_url = input[:input_url]
					if input_url then
						# if it's a mash we won't know if it has desired content types until cached and parsed
						if (Input::TypeMash == input[:type]) or AV.includes?(Asset.av_type(input), desired)
							__cache_asset input
							if (Input::TypeMash == input[:type]) then # read and parse mash json file
								input[:mash] = JSON.parse(File.read(input[:cached_file])) 
								Mash.init_mash_input input
								progress[:downloading] += input.mash.url_count outputs_desire
							end
						end
					end
					if (Input::TypeMash == input[:type]) and AV.includes?(Asset.av_type(input), desired)
						input[:mash][:media].each do |media|
							case media[:type]
							when Mash::Frame, Mash::Video, Mash::Audio, Mash::Image, Mash::Font
								__cache_asset media if AV.includes?(Asset.av_type(media), desired)
							end
						end
					end
					break if @hash[:error]
				end
				__update_timing
				__update_sizing
				__construct_commands
			end
		end
		def __process_render
			unless error then 
				outputs.each do |output|
					begin
						cmds = __output_commands output
						last_file = nil
						result = nil
						cmds.each do |cmd_hash|
							last_file = cmd_hash[:file] 
							result = __execute_output_command output, cmd_hash
						
							progress[:rendered] += 1 
							__callback :progress
						end
						output[:rendered_file] = (Output::TypeSequence == output[:type] ? File.dirname(last_file) : last_file) # so only set if all completed
						__assure_sequence_complete(output[:rendered_file], result, output) if Output::TypeSequence == output[:type]
					rescue Error::Job => e
						__log_exception e, ! output[:required]
						raise if output[:required]
					end
				end
			end
		end
		def __process_upload
			unless error then 
				outputs.each do |output|
					next unless output[:rendered_file]
					begin
						__transfer_job_output output, output[:rendered_file]
					rescue Error::Job => e
						__log_exception e, ! output[:required]
						raise if output[:required]
					end
				end
			end
		end
		def __render_path output
			out_file = (Output::TypeSequence == output[:type] ? "/#{output[:name]}#{output[:sequence]}" : '')
			out_file = "#{out_file}.#{output[:extension]}"
			
			out_file = Evaluate.value out_file, __scope(output)
			"#{__output_path output, true}#{out_file}"
		end
		def __s3 source
			unless source[:s3] 
				region = ((source[:region] and not source[:region].empty?) ? source[:region] : nil)
				source[:s3] = (region ? AWS::S3.new(:region => region) : AWS::S3.new)
			end
			source[:s3]
		end
		def __s3_bucket source
			source[:s3_bucket] ||= __s3(source).buckets[source[:bucket]]
		end
		def __scope object = nil
			hash = Hash.new
			hash[:job] = self
			hash[object.class_symbol] = object if object and object.is_a? Hashable
			hash
		end
		def __transfer_file mode, source_path, out_file
			source_path = File.expand_path(source_path) unless source_path.start_with? '/'
			if File.exists? source_path
				#out_file = Path.add_slash_start out_file
				out_file = File.expand_path(out_file) unless out_file.start_with? '/'
				case mode
				when Method::Copy
					FileUtils.copy source_path, out_file
				when Method::Move
					FileUtils.move source_path, out_file
				else # Method::Symlink
					FileUtils.symlink source_path, out_file
				end
				raise Error::JobUpload.new "could not #{mode} #{source_path} to #{out_file}" unless File.exists? out_file
			end
		end
		def __transfer_job_output output, file
			output_destination = output[:destination] || destination
			raise Error::JobInput.new "output has no destination" unless output_destination 
		
			if File.exists?(file) then
				if output_destination[:archive] || output[:archive] then
					raise Error::Todo.new "support for archive option coming..."
				end
				options = Hash.new
				options[:upload] = file
				options[:output] = output
				options[:destination] = output_destination
				
				files = output_destination.directory_files file
				options[:path] = __evaluated_path_for_transfer output_destination, output
				files.each do |file|
					options[:file] = file
					output_destination.upload options
					progress[:uploaded] += 1
					__callback :progress
				end
				
				
				
#				case output_destination[:type]
#				when Transfer::TypeFile
#					#TODO: we should be using output, no??
#					output = options[:output] 
#					output_destination = options[:destination]
#					destination_path = options[:path]
#					FileHelper.safe_path(File.dirname(destination_path))
#					__transfer_file output_destination[:method], file, destination_path
#					output_destination[:file] = destination_path # for spec tests to find file...
#				when Transfer::TypeS3
#					#TODO: we should be using output, no??
#					output = options[:output] 
#					destination_path = options[:path]
#					output_content_type = output[:mime_type]
#					output_destination = options[:destination]
#					files = Array.new
#					uploading_directory = File.directory?(file)
#					if uploading_directory then
#						file = Path.add_slash_end file
#						Dir.entries(file).each do |f|
#							f = file + f
#							files << f unless File.directory?(f)
#						end
#					else 
#						files << file
#					end
#					files.each do |file|
#						bucket_key = Path.strip_slash_start destination_path
#						bucket_key = Path.concat(bucket_key, File.basename(file)) if uploading_directory
#						#puts "bucket_key = #{bucket_key}"
#						bucket = __s3_bucket output_destination
#						bucket_object = bucket.objects[bucket_key]
#						options = Hash.new
#						options[:acl] = output_destination[:acl].to_sym if output_destination[:acl]
#						options[:content_type] = output_content_type if output_content_type
#						log_entry(:debug) { "s3 write to #{bucket_key}" }
#						bucket_object.write(Pathname.new(file), options)
#						progress[:uploaded] += 1
#					end
#		
#				when Transfer::TypeHttp, Transfer::TypeHttps
#					output = options[:output] 
#					output_destination = options[:destination]
#					output_content_type = output[:mime_type]
#					destination_path = options[:path]
#					url = "#{output_destination[:type]}://#{output_destination[:host]}"
#					url += Path.add_slash_start destination_path
#					uri = URI(url)
#					uri.port = output_destination[:port].to_i if output_destination[:port]
#					__transfer_uri_parameters output, uri, output_destination
#					uploading_directory = File.directory?(file)
#					files = Array.new
#					if uploading_directory then
#						file = Path.add_slash_end file
#						Dir.entries(file).each do |f|
#							f = file + f
#							files << f unless File.directory?(f)
#						end
#					else 
#						files << file
#					end
#					files.each do |file|
#						file_name = File.basename file
#						io = File.open(file)
#						raise Error::Object.new "could not open file #{file}" unless io
#						upload_io = UploadIO.new(io, output_content_type, file_name)
#						req = Net::HTTP::Post::Multipart.new(uri, "key" => destination_path, "file" => upload_io)
#						raise Error::JobUpload.new "could not construct multipart POST request" unless req
#						req.basic_auth(output_destination[:user], output_destination[:pass]) if output_destination[:user] and output_destination[:pass]
#						res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
#							result = http.request(req)
#							if '200' == result.code then
#								log_entry(:debug) {"uploaded #{file} #{uri}\n#{result.body}"}
#							else
#								log_entry(:error) { "#{result.code} upload response #{result.body}" }
#							end
#						end
#						io.close 
#						progress[:uploaded] += 1
#						__callback :progress
#					end
#				end
			else
				log_entry(:warn) { "file was not rendered #{file}" }
				log_entry(:error) { "required output not rendered" } if output[:required]
			end
		end
		def __transfer_uri_parameters scope_object, uri, transfer
			if uri and transfer
				parameters = transfer[:parameters]
				if parameters and not parameters.empty?
					if parameters.is_a?(Hash) then
						parameters = Marshal.load(Marshal.dump(parameters)) 
						Evaluate.object parameters, __scope(scope_object)
						parameters = URI.encode_www_form(parameters)
						uri.query = parameters
					end
				end
			end
		end
		def __update_sizing
			# make sure visual outputs have dimensions, using input's for default
			in_dimensions = nil
			outputs.each do |output|
				next if AV::Audio == output[:av]
				next if output[:dimensions]
				in_dimensions = __input_dimensions unless in_dimensions
				output[:dimensions] = in_dimensions 
			end
		end
		def __update_timing
			start_audio = FloatUtil::Zero
			start_video = FloatUtil::Zero
			inputs.each do |input|
				if FloatUtil.cmp(input[:start], FloatUtil::NegOne) then
					unless (input[:no_video] or input[:no_audio]) then
						input[:start] = [start_audio, start_video].max
					else
						if input[:no_video] then
							input[:start] = start_audio
						else 
							input[:start] = start_video
						end
					end
				end
				length = self.class.__input_length input
				start_video = input[:start] + length unless input[:no_video]
				start_audio = input[:start] + length unless input[:no_audio]
				input[:range] = self.class.__input_trim_range input
				input[:offset] = self.class.__input_trim input
				input[:length] = length # self.class.__input_length input
				
			end
			output_duration = FloatUtil.max(start_video, start_audio)
			@hash[:duration] = output_duration
			outputs.each do |output|
				output[:duration] = output_duration
				if Output::TypeSequence == output[:type] then
					padding = (output[:video_rate].to_f * output_duration).floor.to_i.to_s.length
					output[:sequence] = "%0#{padding}d"
				end
			end
		end
		def __video_graphs
			unless @video_graphs
				@video_graphs = Array.new
				inputs.each do |input|
					next if input[:no_video]
					case input[:type]
					when Input::TypeMash
						mash = input[:mash]
						all_ranges = Mash.video_ranges mash
						all_ranges.each do |range|
							graph = GraphMash.new input, range
							clips = Mash.clips_in_range mash, range, Mash::Video
							if 0 < clips.length then
								transition_layer = nil
								transitioning_clips = Array.new
								clips.each do |clip|
									case clip[:type]
									when Mash::Video, Mash::Image
										# media properties were copied to clip BEFORE file was cached, so repeat now
										media = Mash.media mash, clip[:id]
										raise Error::JobInput.new "could not find media for clip #{clip[:id]}" unless media
										clip[:cached_file] = media[:cached_file] || raise("could not find cached file #{media}")
										clip[:no_video] = media[:no_video] unless clip[:no_video]
										clip[:dimensions] = media[:dimensions] || raise("could not find dimensions #{clip} #{media}")
									end	
									if Mash::Transition == clip[:type] then
										raise Error::JobInput.new "found two transitions within #{range.inspect}" if transition_layer
										transition_layer = graph.add_new_layer clip
									elsif 0 == clip[:track] then
										transitioning_clips << clip
									end
								end
								if transition_layer then
									raise Error::JobInput.new "too many clips on track zero" if 2 < transitioning_clips.length
									if 0 < transitioning_clips.length then
										transitioning_clips.each do |clip| 
											transition_layer.add_new_layer clip
										end 
									end
								end
								clips.each do |clip|
									next if transition_layer and 0 == clip[:track] 
									case clip[:type]
									when Mash::Video, Mash::Image, Mash::Theme
										graph.add_new_layer clip
									end
								end
							end
							@video_graphs << graph
						end
					when Mash::Video, Mash::Image
						@video_graphs << GraphRaw.new(input)
					end
				end
			end
			@video_graphs
		end
	end
end
