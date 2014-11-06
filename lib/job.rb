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
	class Job
		include JobHash
		private
		def self.__audio_from_file path
			raise Error::Parameter.new "__audio_from_file with invalid path" unless path and (not path.empty?) and File.exists? path
			out_file = "#{File.dirname path}/#{File.basename path}-intermediate.#{Intermediate::AudioExtension}"
			switches = Array.new
			switches << __switch(path, 'i')
			switches << __switch(2, 'ac')
			switches << __switch(44100, 'ar')
			exec_opts = Hash.new
			exec_opts[:command] = switches.join
			exec_opts[:file] = out_file
			exec_opts
		end
		def self.__av_type_for_input input
			case input[:type]
			when Input::TypeAudio
				AV::Audio
			when Mash::Image, Mash::Font, Mash::Frame
				AV::Video
			when Input::TypeVideo, Input::TypeMash
				(input[:no_audio] ? AV::Video : input[:no_video] ? AV::Audio : AV::Both)
			end
		end
		def self.__av_type_for_output output
			case output[:type]
			when Output::TypeAudio, Output::TypeWaveform
				AV::Audio
			when Output::TypeImage, Output::TypeSequence
				AV::Video
			when Output::TypeVideo
				AV::Both
			end
		end
		def self.__evaluated_path_for_transfer transfer, scope, output
			file_name = __transfer_file_name transfer
			if file_name.empty? 
				# transfer didn't supply one
				file_name = output[:path]
				file_name = Path.concat file_name, __transfer_file_name(output) unless Output::TypeSequence == output[:type]
			end
			key = __transfer_directory(transfer)
			key = Path.concat key, file_name
			Evaluate.value key, scope
		end
		def self.__hash_from_path hash_or_path
			data = Hash.new
			if hash_or_path.is_a? String
				if File.exists? hash_or_path
					begin
						case File.extname hash_or_path
						when '.yml'
							data = YAML::load(File.open(hash_or_path))
						when '.json'
							data = JSON.parse(File.read(hash_or_path))
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
			__hash_keys_to_symbols! data
			data
		end
		def self.__file_info type, ffmpeg_output
			result = nil
			if ffmpeg_output and not ffmpeg_output.empty?
				case type
				when Info::Audio
					/Audio: ([^,]+),/.match(ffmpeg_output) do |match|
						if 'none' != match[1] then
							result = 1
						end
					end
				when Info::Dimensions
					/, ([\d]+)x([\d]+)/.match(ffmpeg_output) do |match|
						result = match[1] + 'x' + match[2]
					end
				when Info::Duration
					/Duration\s*:\s*([\d]+):([\d]+):([\d\.]+)/.match(ffmpeg_output) do |match|
						result = 60 * 60 * match[1].to_i + 60 * match[2].to_i + match[3].to_f
					end
				when Info::FPS
					match = / ([\d\.]+) fps/.match(ffmpeg_output)
					match = / ([\d\.]+) tb/.match(ffmpeg_output) unless match 
					result = match[1].to_f.round	
				end
			end
			result
		end
		def self.__hash_keys_to_symbols! hash
			if hash 
				if hash.is_a? Hash then
					hash.keys.each do |k|
						v = hash[k]
						if k.is_a? String then
							k_sym = k.downcase.to_sym
							hash[k_sym] = v
							hash.delete k
						end
						__hash_keys_to_symbols! v
					end
				elsif hash.is_a? Array then
					hash.each do |v|
						__hash_keys_to_symbols! v
					end
				end
			end
			hash
		end
		def self.__init_callback job, callback
			if callback
				__init_key callback, :trigger, Callback::TriggerComplete
				__init_destination job, callback # not using returned Transfer object, but callback Hash was inited
				case callback[:trigger]
				when 'progress'
					__init_key callback, :progress_seconds, 10	
				end
				callback = Callback.new callback
			end
			callback
		end
		def self.__init_clip input, mash, track_index, track_type
			__init_clip_media input, mash
			input[:frame] = (input[:frame] ? input[:frame].to_f : FloatUtil::Zero)
			raise Error::JobInput.new "mash clips must have frames" unless input[:frames] and 0 < input[:frames]
			input[:range] = TimeRange.new input[:frame], mash[:quantize], input[:frames]
			input[:length] = input[:range].length_seconds unless input[:length]
			input[:track] = track_index if track_index 
			case input[:type]
			when Mash::Frame
				input[:still] = 0 unless input[:still]
				input[:fps] = mash[:quantize] unless input[:fps]
				if 2 > input[:still] + input[:fps] then
					input[:quantized_frame] = 0
				else 
					input[:quantized_frame] = mash[:quantize] * (input[:still].to_f / input[:fps].to_f).round
				end
			when Mash::Transition
				input[:to] = Hash.new unless input[:to]
				input[:from] = Hash.new unless input[:from]
				input[:to][:merger] = Defaults.module_for_type(:merger) unless input[:to][:merger]
				input[:to][:scaler] = Defaults.module_for_type(:scaler) unless input[:to][:scaler] or input[:to][:fill]
				input[:from][:merger] = Defaults.module_for_type(:merger) unless input[:from][:merger]
				input[:from][:scaler] = Defaults.module_for_type(:scaler) unless input[:from][:scaler] or input[:from][:fill]
				__init_clip_media(input[:to][:merger], mash, Mash::Merger)
				__init_clip_media(input[:from][:merger], mash, Mash::Merger)
				__init_clip_media(input[:to][:scaler], mash, Mash::Scaler)
				__init_clip_media(input[:from][:scaler], mash, Mash::Scaler)
			when Mash::Video, Mash::Audio
				input[:trim] = 0 unless input[:trim]
				input[:offset] = input[:trim].to_f / mash[:quantize] unless input[:offset]
			end
			__init_raw_input input
		end
		def self.__init_clip_media clip, mash, type = nil
			raise Error::JobInput.new "clip has no id #{clip}" unless clip[:id]
			media = Mash.media_search type, clip, mash
			raise Error::JobInput.new "#{clip[:id]} #{type ? type : 'media'} not found in mash" unless media
			media.each do |k,v|
				clip[k] = v unless clip[k]
			end 
		end
		def self.__init_destination job, destination
			if destination
				__init_key destination, :type, Transfer::TypeFile
				case destination[:type]
				when Transfer::TypeS3
					__init_key destination, :acl, 'public-read' 
				when Transfer::TypeFile
					__init_key destination, :method, Method::Move 
				when Transfer::TypeHttp
					__init_key destination, :method, Method::Post 
				end
				job[:error] = "destination name contains slash #{destination[:name]} - use path instead" if destination[:name] and destination[:name].to_s.include? '/'
				destination = Transfer.create destination
			end
			destination
		end
		def self.__init_input input
			__init_time input, :offset
			__init_key input, :start, FloatUtil::NegOne
			__init_key input, :duration, FloatUtil::Zero
			__init_key(input, :length, 1.0) if Input::TypeImage == input[:type]
			__init_time input, :length # ^ image will already be one by default, others zero
			__init_raw_input input
		end
		def self.__init_input_av input
			input[:av] = (input[:no_video] ? (input[:no_audio] ? AV::Neither : AV::Audio) : (input[:no_audio] ? AV::Video : AV::Both))
		end
		def self.__init_hash job
			outputs_desire = nil
			job[:progress] = Hash.new() { 0 } # clear existing progress, but not error (allows callback testing)
			job[:log] = Proc.new { File.read(Path.concat __path_job, 'log.txt') }
			__init_key job, :id, UUID.new.generate
			__init_key job, :inputs, Array.new
			__init_key job, :outputs, Array.new
			__init_key job, :callbacks, Array.new
			__init_key job, :commands, Array.new # stores commands as executed
			job[:base_source] = __init_source job[:base_source]
			job[:module_source] = __init_source job[:module_source]		
			__init_destination job, job[:destination]
			found_destination = !! job[:destination]
			job[:outputs].map! do |output| 
				output = __init_output output
				job[:error] = "output name contains slash #{output[:name]} - use path instead" if output[:name].to_s.include? '/'
				outputs_desire = AV.merge output[:av], outputs_desire
				job[:progress][:rendering] += 1
				job[:progress][:uploading] += 1
				destination = output[:destination]
				if destination then
					__init_destination job, destination
					found_destination = true
				end
				output
			end
			job[:inputs].map! do |input| 
				input = __init_input input
				input[:base_source] = __init_source input[:base_source]
				input[:module_source] = __init_source input[:module_source]
				base_src, module_src = __input_sources input, job
				input[:input_url] = Job.__url_for_input input, base_src, module_src
				if input[:input_url] then
					job[:progress][:downloading] += 1
				elsif Input::TypeMash == input[:type] then
					job[:progress][:downloading] += __mash_url_count input[:source], outputs_desire, base_src, module_src
				end
				input
			end
			job[:callbacks].map! do |callback|
				callback = __init_callback job, callback
				job[:progress][:calling] += 1 unless 'progress' == callback[:trigger]
				callback
			end
			job[:error] = 'no destinations specified' unless found_destination
			job[:error] = 'no outputs specified' if job[:outputs].empty?
			job[:error] = 'no inputs specified' if job[:inputs].empty?
			outputs_desire
		end
		def self.__init_key hash, key, default
			if hash
				value = hash[key]
				overwrite = value.nil?
				unless overwrite
					if default.is_a? Array or default.is_a? Hash then
						overwrite = ! (value.is_a? Array or value.is_a? Hash)
						overwrite = value.empty? unless overwrite
					else
						overwrite = value.to_s.empty?
					end
				end
				hash[key] = default if overwrite
			end
		end
		def self.__init_mash mash
			__init_key mash, :backcolor, 'black'
			mash[:quantize] = (mash[:quantize] ? mash[:quantize].to_f : FloatUtil::One)
			mash[:media] = Array.new unless mash[:media] and mash[:media].is_a? Array
			longest = FloatUtil::Zero
			Mash::Tracks.each do |track_type|
				track_sym = track_type.to_sym
				mash[track_sym] = Array.new unless mash[track_sym] and mash[track_sym].is_a? Array
				mash[track_sym].length.times do |track_index|
					track = mash[track_sym][track_index]
					track[:clips] = Array.new unless track[:clips] and track[:clips].is_a? Array
					track[:clips].map! do |clip|
						clip = __init_clip clip, mash, track_index, track_type
						__init_clip_media(clip[:merger], mash, :merger) if clip[:merger]
						__init_clip_media(clip[:scaler], mash, :scaler) if clip[:scaler]
						clip[:effects].each do |effect|
							__init_clip_media effect, mash, :effect
						end
						clip
					end
					clip = track[:clips].last
					if clip then
						longest = FloatUtil.max(longest, clip[:range].stop)
					end
					track_index += 1
				end
			end
			mash[:length] = longest
			Mash.new mash
		end
		def self.__init_mash_input input
			if Mash.hash? input[:source] then
				input[:source] = __init_mash input[:source]
				input[:duration] = Mash.duration(input[:source]) if FloatUtil.cmp(input[:duration], FloatUtil::Zero)
				input[:no_audio] = ! Mash.has_audio?(input[:source])
				input[:no_video] = ! Mash.has_video?(input[:source])
			end
		end
		def self.__init_output output
			__init_key output, :type, Output::TypeVideo
			output[:av] = __av_type_for_output output
			__init_key output, :name, (Output::TypeSequence == output[:type] ? '' : output[:type])	
			unless output[:extension] # try to determine from name if it has one
				output_name_extension = File.extname output[:name]
				if output_name_extension and not output_name_extension.empty?
					output[:name] = File.basename output[:name], output_name_extension
					output[:extension] = output_name_extension.delete '.'
				end
			end
			case output[:type]
			when Output::TypeVideo
				__init_key output, :audio_bitrate, 224
				__init_key output, :audio_codec, 'aac -strict experimental'
				__init_key output, :audio_rate, 44100
				__init_key output, :backcolor, 'black'
				__init_key output, :dimensions, '512x288'
				__init_key output, :extension, 'mp4'
				__init_key output, :fill, Fill::None
				__init_key output, :video_rate, 30
				__init_key output, :gain, Gain::None
				__init_key output, :precision, 1
				__init_key output, :video_bitrate, 2000
				__init_key output, :video_codec, 'libx264 -level 41 -movflags faststart'
			when Output::TypeSequence
				__init_key output, :backcolor, 'black'
				__init_key output, :video_rate, 101
				__init_key output, :extension, 'jpg'
				__init_key output, :dimensions, '256x144'
				__init_key output, :quality, 1
				output[:no_audio] = true
			when Output::TypeImage
				__init_key output, :backcolor, 'black'
				__init_key output, :quality, 1						
				__init_key output, :extension, 'jpg'
				__init_key output, :dimensions, '256x144'
				output[:no_audio] = true
			when Output::TypeAudio
				__init_key output, :audio_bitrate, 224
				__init_key output, :precision, 0
				__init_key output, :audio_codec, 'libmp3lame'
				__init_key output, :extension, 'mp3'
				__init_key output, :audio_rate, 44100
				__init_key output, :gain, Gain::None
				output[:no_video] = true
			when Output::TypeWaveform
				__init_key output, :backcolor, 'FFFFFF'
				__init_key output, :precision, 0
				__init_key output, :dimensions, '8000x32'
				__init_key output, :forecolor, '000000'
				__init_key output, :extension, 'png'
				output[:no_video] = true
			end
			Output.create output		
		end
		def self.__init_raw_input input
			input_type = input[:type]
			is_av = [Mash::Video, Mash::Audio].include? input_type
			is_v = [Mash::Video, Mash::Image, Mash::Frame].include? input_type

			input[:effects] = Array.new unless input[:effects] and input[:effects].is_a? Array
			input[:merger] = Defaults.module_for_type(:merger) unless input[:merger]
			input[:scaler] = Defaults.module_for_type(:scaler) unless input[:scaler] or input[:fill]
	
			# set volume with default of none (no adjustment)
			__init_key(input, :gain, Gain::None) if is_av
			__init_key(input, :fill, Fill::Stretch) if is_v
		
			# set source from url unless defined
			case input_type
			when Mash::Video, Mash::Image, Mash::Frame, Mash::Audio
				input[:source] = input[:url] unless input[:source]
				if input[:source].is_a? Hash then
					source_ob = __init_source input[:source], Source
					input[:source] = source_ob
				end
			end
			# set no_* when we know for sure
			case input_type
			when Input::TypeMash
				__init_mash_input input
			when Input::TypeVideo
				input[:speed] = (input[:speed] ? input[:speed].to_f : FloatUtil::One) 
				input[:no_audio] = ! FloatUtil.cmp(FloatUtil::One, input[:speed])
				input[:no_video] = false
			when Input::TypeAudio
				__init_key input, :loop, 1
				input[:no_video] = true
			when Input::TypeImage
				input[:no_video] = false
				input[:no_audio] = true
			else
				input[:no_audio] = true
			end		
			input[:no_audio] = ! Mash.clip_has_audio(input) if is_av and not input[:no_audio]
			__init_input_av input
			Input.create input
		end
		def self.__init_source source, klass = Transfer
			if source 
				__init_key source, :type, Transfer::TypeFile
				case source[:type]
				when Transfer::TypeFile
					__init_key source, :method, Method::Symlink 
				when Transfer::TypeHttp
					__init_key source, :method, Method::Get 
				end
				source = klass.create source
			end
			source
		end
		def self.__init_time input, key
			if input[key] then
				if input[key].is_a? String then
					input["#{key.id2name}_is_relative".to_sym] = '%'
					input[key]['%'] = ''
				end
				input[key] = input[key].to_f
				if FloatUtil.gtr(FloatUtil::Zero, input[key]) then
					input["#{key.id2name}_is_relative".to_sym] = '-'
					input[key] = FloatUtil::Zero - input[key]
				end
			else 
				input[key] = FloatUtil::Zero
			end
		end
		def self.__input_length input
			__input_time input, :length
		end
		def self.__input_sources input, job
			[(input[:base_source] || job[:base_source]), (input[:module_source] || job[:module_source])]
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
		def self.__mash_url_count mash, outputs_desire, base_src, module_src
			count = 0
			mash[:media].each do |media|
				case media[:type]
				when Mash::Video, Mash::Audio, Mash::Image, Mash::Font
					if AV.includes?(Job.__av_type_for_input(media), outputs_desire) then
						count += 1 if Job.__url_for_input media, base_src, module_src
					end
				end
			end
			count
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
		def self.__path_for_transfer source
			Path.concat __transfer_directory(source), __transfer_file_name(source)
		end
		def self.__source_from_url url
			uri = URI url
			source = Hash.new
			source[:type] = uri.scheme #=> "http(s)"
			source[:host] = uri.host #=> "foo.com"
			source[:path] = uri.path #=> "/posts"
			source[:user] = uri.user
			source[:pass] = uri.password 
			source[:port] = uri.port
			source[:parameters] = CGI.parse(uri.query) if uri.query
			source
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
		def self.__transfer_directory transfer
			Path.concat transfer[:directory], transfer[:path]
		end
		def self.__transfer_file_name transfer	
			name = Path.strip_slashes transfer[:name]
			name += '.' + transfer[:extension] if transfer[:extension]
			name
		end
		def self.__url_for_input input, base_src = nil, module_src = nil
			url = nil
			if input[:source] then
				if input[:source].is_a? String then 
					url = input[:source]
					if not url.include? '://' then # it would start with file:/// if a file path
						# relative url
						case input[:type]
						when Mash::Theme, Mash::Font, Mash::Effect
							base_src = module_src if module_src
						end
						base_url = __url_for_source base_src
						if base_url then
							#puts "base_url = #{base_url}"
							#puts "url = #{url}"
							base_url = Path.add_slash_end base_url
							url = Path.strip_slash_start url
							if Transfer::TypeFile == base_src[:type]
								url = Path.concat base_url, url
							else
								url = URI.join(base_url, url).to_s
							end
						end
					end
				else
					unless Input::TypeMash == input[:type] and Mash.hash?(input[:source]) then
						url = __url_for_source input[:source]
					end
				end
			end
			url
		end
		def self.__url_for_source input_source
			url = nil
			if input_source then
				if input_source[:url] then
					url = input_source[:url]
				else
					url = "#{input_source[:type]}://"
					case input_source[:type]
					when Transfer::TypeHttp, Transfer::TypeHttps
						url += input_source[:host] if input_source[:host]
					when Transfer::TypeS3
						url += "#{input_source[:bucket]}." if input_source[:bucket] and not input_source[:bucket].empty?
						url += 's3'
						url += "-#{input_source[:region]}" if input_source[:region] and not input_source[:region].empty?
						url += '.amazonaws.com'
					end
					url += Path.add_slash_start __path_for_transfer(input_source)
				end
			end
			url
		end
		public
# Transfer - Resolves relative paths within Input#source and Media#source String values.
		def base_source; _get __method__; end
# Array - Zero or more Callback objects.
		def callbacks; _get __method__; end
# Transfer - Shared by all Output objects that don't have one of their own.
		def destination; _get __method__; end
# Problem encountered during #new or #process. If the source of the problem is a 
# command line application then lines from its output that include common 
# phrases will be included. Problems encountered during rendering of optional outputs 
# are not included - check #log for a warning instead. 
#
# Returns String that could be multiline and/or quite long. 
		def error; _get __method__; end
# String - user supplied identifier.
# Default - Nil, or messageId if the Job originated from an SQS message. 
		def id; _get __method__; end
# Create a new Job object from a nested structure or a file path.
#
# hash_or_path - Hash or String expected to be a path to a JSON or YML file, 
# which will be parse to the Hash. 
		def initialize hash_or_path, configuration = nil
			@logger = nil
			@audio_graphs = nil
			@video_graphs = nil
			@configuration = configuration || Hash.new
			super Job.__hash_from_path hash_or_path
			@outputs_desire = Job.__init_hash @hash
			path_job = __path_job
			__file_safe path_job
			# write massaged job json to job directory
			File.write(Path.concat(path_job, 'job.json'), @hash.to_json)	
			# if we encountered a parsing error, log it
			log_entry(:error) { @hash[:error] } if @hash[:error]
		end
# Array - One or more Input objects.
		def inputs; _get __method__; end
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
			puts proc.call if 'debug' == @configuration[:log_level]
		end
# Array - One or more Output objects. 
		def outputs; _get __method__; end
# Transfer - Resolves relative font paths within Media#source String values.
# Default - #base_source
		def module_source; _get __method__; end
# Downloads assets for each Input, renders each Output and uploads to
# #destination or Output#destination so long as #error is false.
#
# Returns true if processing succeeded, otherwise false - check #error for
# details.
#
# Raises Error::Job or subclass depending on processing stage - Error::JobInput, 
# Error::JobRender, Error::JobUpload.
		def process 
			rescued_exception = nil
			begin
				__process_download
				__process_render
				__process_upload
			rescue Exception => e 
				rescued_exception = e
			end
			begin
				if rescued_exception then 
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
			! @hash[:error]
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
		def progress; _get __method__; end
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
						quantize = input[:source][:quantize]
						audio_clips = Mash.clips_having_audio input[:source]
						audio_clips.each do |clip|
							media = Mash.media input[:source], clip[:id]
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
		def __cache_input input, input_url, base_src = nil, module_src = nil
			if input_url then
				cache_url_path = __cache_url_path input_url
				unless File.exists? cache_url_path then
					source = input[:source]
					if source.is_a? String then
						if source == input_url then
							source = Job.__source_from_url(input_url)
						else 
							base_src = module_src if module_src and Mash::Font == input[:type]
							new_source = base_src.to_hash
							new_source[:name] = source
							source = new_source
						end
						source = Source.create source
					end
					raise Error::JobInput.new "no source for #{input_url}" unless source
					__cache_input_source input, source, input_url, cache_url_path
					raise Error::JobInput.new "could not cache #{input_url}" unless File.exists? cache_url_path
				end
				__set_info cache_url_path, Info::At, Time.now.to_i
				input[:cached_file] = cache_url_path
				unless input[:type] then
					input[:type] = __file_type(cache_url_path)
					Job.__init_input input
				end
				case input[:type]
				when Input::TypeVideo
					input[:duration] = __get_info(cache_url_path, Info::Duration).to_f unless input[:duration] and FloatUtil.gtr(input[:duration], FloatUtil::Zero)
					input[:no_audio] = ! __get_info(cache_url_path, Info::Audio)
					input[:dimensions] = __get_info(cache_url_path, Info::Dimensions)
					input[:no_video] = ! input[:dimensions]
					Job.__init_input_av input
				when Input::TypeAudio
					input[:duration] = __get_info(cache_url_path, Info::AudioDuration).to_f unless input[:duration] and FloatUtil.gtr(input[:duration], FloatUtil::Zero)
					input[:duration] = __get_info(cache_url_path, Info::VideoDuration).to_f unless FloatUtil.gtr(input[:duration], FloatUtil::Zero)
				when Input::TypeImage 
					input[:dimensions] = __get_info(cache_url_path, Info::Dimensions)
					raise Error::JobInput.new "could not determine image dimensions" unless input[:dimensions]
				end
			else
				raise Error::JobInput.new "could not produce an input_url #{input}"
			end
			progress[:downloaded] += 1
			__callback :progress
		end
		def __cache_job_mash input
			mash = input[:source]
			base_src, module_src = Job.__input_sources input, self
			mash[:media].each do |media|
				case media[:type]
				when Mash::Video, Mash::Audio, Mash::Image, Mash::Font
					if AV.includes?(Job.__av_type_for_input(media), @outputs_desire) then
						input_url = Job.__url_for_input media, base_src, module_src
						if input_url then
							__cache_input media, input_url, base_src, module_src
						end
					end
				end
			end
		end
		def __cache_input_source input, source, input_url, out_file
			begin
				__file_safe(File.dirname(out_file))
				case source[:type]
				when Transfer::TypeFile
					source_path = input_url.dup
					source_path['file://'] = ''
					source_path = File.expand_path source_path
					if File.exists? source_path
						__transfer_file(source[:method], source_path, out_file) 
					else
						log_entry(:error) { "file does not exist #{source_path}" }
					end
				when Transfer::TypeHttp, Transfer::TypeHttps
					#puts "retrieving #{input_url}"
					uri = URI input_url
					uri.port = source[:port] if source[:port]
					__transfer_uri_parameters input, uri, source
					req.basic_auth(source[:user], source[:pass]) if source[:user] and source[:pass]
					Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
						request = Net::HTTP::Get.new uri
						http.request request do |response|
							if '200' == response.code then
								File.open(out_file, 'wb') do |io|
									response.read_body do |chunk|
										io.write chunk
									end
								end
								mime_type = response['content-type']
								#puts "MIME: #{mime_type}"
								__set_info(out_file, 'Content-Type', mime_type) if mime_type
							else
								log_entry(:warn) {"got #{response.code} response code from #{input_url}"}
							end
						end
					end
				when Transfer::TypeS3
					bucket = __s3_bucket source
					bucket_key = Job.__path_for_transfer source
					object = bucket.objects[bucket_key]
					if @configuration[:s3_read_at_once] then
						#puts "reading from S3 #{bucket_key}"
						object_read_data = object.read
						File.open(out_file, 'wb') { |file| file.write(object_read_data) } if object_read_data
					else
						File.open(out_file, 'wb') do |file|
							object.read do |chunk|
								file.write(chunk)
							end
						end
					end
				end
			rescue Exception => e
				raise Error::JobInput.new e.message unless e.is_a? Error::Job
			end
			out_file
		end
		def __cache_url_path url
			directory = @configuration[:download_directory]
			directory = @configuration[:render_directory] unless directory and not directory.empty?
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
				destination_path = Job.__path_for_transfer callback
				destination_path = Evaluate.value destination_path, __scope(callback)
				case callback[:type]
				when Transfer::TypeFile
					__file_safe(File.dirname(destination_path))
					callback[:file] = destination_path
					if data then
						file = Path.concat __path_job, "callback-#{UUID.new.generate}.json"
						File.open(file, 'w') { |f| f.write(data.to_json) }
						__transfer_file callback[:method], file, destination_path
					end
				when Transfer::TypeHttp, Transfer::TypeHttps
					url = "#{callback[:type]}://#{callback[:host]}"
					url += Path.add_slash_start Job.__path_for_transfer(callback)
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
		def __execute options
			cmd = options[:command]
			out_file = options[:file] || ''
			duration = options[:duration]
			precision = options[:precision] || 1
			app = options[:app] || 'ffmpeg'
			outputs_file = ((not out_file.empty?) and ('/dev/null' != out_file))
			whole_cmd = @configuration["#{app}_path".to_sym]
			whole_cmd = app unless whole_cmd and not whole_cmd.empty?
			whole_cmd += ' ' + cmd
			__file_safe(File.dirname(out_file)) if outputs_file
			whole_cmd += " #{out_file}" if out_file and not out_file.empty?
			@hash[:commands] << whole_cmd
			log_entry(:debug) { whole_cmd }
			result = Open3.capture3(whole_cmd).join "\n"
			if outputs_file and not out_file.include?('%') then	
				unless File.exists?(out_file) and File.size?(out_file)
					log_entry(:debug) { result }
					raise Error::JobRender.new result
				end
				if duration then
					audio_duration, video_duration = __file_durations out_file
					log_entry(:debug) { "rendered file with audio_duration: #{audio_duration} video_duration: #{video_duration}" }
					unless audio_duration or video_duration
						raise Error::JobRender.new result, "could not determine if #{duration} == duration of #{out_file}" 
					end
					unless FloatUtil.cmp(duration, video_duration.to_f, precision) or FloatUtil.cmp(duration, audio_duration.to_f, precision)
						log_entry(:warn) { result }
						raise Error::JobRender.new result, "generated file with incorrect duration #{duration} != #{audio_duration} or #{video_duration} #{out_file}" 
					end
				end
			end 
			log_entry(:debug) { result }
			result
		end
		def __execute_output_command output, cmd_hash
			result = nil
			#puts "__execute_output_command #{cmds}"
			out_path = cmd_hash[:file]
			content = cmd_hash[:content]
			if content
				__file_safe File.dirname(out_path)
				File.write(out_path, content)
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
							__execute :command => cmd_pass_1, :file => '/dev/null', :app => app
							result = __execute :command => cmd_pass_2, :file => out_path, :duration => duration, :precision => precision, :app => app
						rescue Exception => e
							log_entry(:debug) { e.message }
							log_entry(:warn) { "unable to encode in two passes, retrying in one" }
							do_single_pass = true
						end
					end
					if do_single_pass then
						result = __execute cmd_hash
					end
				end
			end
			result
		end
		def __file_durations path
			video_data = __execute :command => path, :app => 'ffprobe'
			audio_data = __execute :command => "--i #{path}", :app => 'sox'
			[Job.__file_info('duration', audio_data), Job.__file_info('duration', video_data)]
		end
		def __file_mime path
			mime = __get_info path, 'Content-Type'
			if not mime then
				type = MIME::Types.of(path).first
				if type 
					mime = type.simplified
				else
					mime = Rack::Mime.mime_type(File.extname(path))
				end
				#puts "LOOKING UP MIME: #{ext} #{mime}"
				__set_info(path, 'Content-Type', mime) if mime
			end
			mime
		end
		def __file_safe path
			options = Hash.new
			options[:mode] = @configuration[:chmod_directory_new] if @configuration[:chmod_directory_new]
			FileUtils.makedirs path, options
		end
		def __file_type path
			result = nil
			if path then
				result = __get_info path, 'type'
				if not result then
					mime = __file_mime path
					result = mime.split('/').shift if mime
					__set_info(path, 'type', result) if result
				end
			end
			result
		end
		def __get_info path, type
			raise Error::Parameter.new "false or empty path or type #{path}, #{type}" unless type and path and (not (type.empty? or path.empty?))
			result = nil
			if File.exists?(path) then
				info_file = __meta_path type, path
				if File.exists? info_file then
					result = File.read info_file
				else
					check = Hash.new
					case type
					when Info::Type, 'http', 'ffmpeg', 'sox' 
						# do nothing if file doesn't already exist
					when Info::Dimensions
						check[:ffmpeg] = true
					when Info::VideoDuration
						check[:ffmpeg] = true
						type = Info::Duration
					when Info::AudioDuration
						check[:sox] = true
						type = Info::Duration
					when Info::Duration
						check[Info::Audio == __file_type(path) ? :sox : :ffmpeg] = true
					when Info::FPS, Info::Audio # only from FFMPEG
						check[:ffmpeg] = true
					end
					if check[:ffmpeg] then
						data = __get_info(path, 'ffmpeg')
						if not data then
							data = __execute :command => path, :app => 'ffprobe'
							__set_info path, 'ffmpeg', data
						end
						result = Job.__file_info(type, data) if data
					elsif check[:sox] then
						data = __get_info(path, 'sox')
						if not data then
							data = __execute :command => "--i #{path}", :app => 'sox'
							__set_info(path, 'sox', data)
						end
						result = Job.__file_info(type, data) if data
					end
					# try to cache the data for next time
					__set_info(path, type, result) if result
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
				__file_safe log_dir
				@logger = Logger.new(Path.concat log_dir, 'log.txt')
				log_level = @hash[:log_level]
				log_level = @configuration[:log_level] unless log_level and not log_level.empty?
				log_level = 'info' unless log_level and not log_level.empty?
				log_level = log_level.upcase
				log_level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
				@logger.level = log_level
			end
			@logger
		end
		def __log_exception(rescued_exception, is_warning = false)
			unless rescued_exception.is_a? Error::Job
				str =  "#{rescued_exception.backtrace.join "\n"}\n#{rescued_exception.message}" 
				puts str # so it gets in cron log as well
			end
			log_entry(:debug) { rescued_exception.backtrace.join "\n" }
			log_entry(is_warning ? :warn : :error) { rescued_exception.message }
			nil
		end
		def __meta_path type, path
			Path.concat File.dirname(path), "#{File.basename path, '.*'}.#{type}.#{Info::Extension}"
		end
		def __output_commands output
			unless output[:commands]
				output[:commands] = Array.new
				avb = Job.__av_type_for_output output
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
						switches << Job.__switch(output[:video_rate], 'r:v') if output[:video_rate]
						if 1 == v_graphs.length 
						# and v_graphs.first.is_a?(RawGraph)
							graph = v_graphs[0]
							video_duration = graph.duration
							cmd = graph.graph_command output, self
							raise Error::JobInput.new "could not build complex filter" if cmd.empty?
							switches << Job.__switch("'#{cmd}'", 'filter_complex')
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
								cmd += Job.__output_command output, AV::Video, duration
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
							
							switches << Job.__switch('1', 'auto_convert')
							#switches << Job.__switch('concat', 'f:v')
							switches << Job.__switch("'#{file_path}'", 'i')
							switches << Job.__switch('copy', 'c:v')
							#switches << Job.__switch(output[:video_bitrate], 'b:v', 'k') if output[:video_bitrate]
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
							cmd_hash = Job.__audio_from_file(data[:cached_file])
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
								cmd_hash = Job.__audio_from_file(data[:cached_file])
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
							switches << Job.__switch(data[:waved_file], '--input')
							switches << Job.__switch(dimensions.first, '--width')
							switches << Job.__switch(dimensions.last, '--height')
							switches << Job.__switch(output[:forecolor], '--linecolor')
							switches << Job.__switch(output[:backcolor], '--backgroundcolor')
							switches << Job.__switch('0', '--padding')
							switches << Job.__switch('', '--output')
						
							exec_opts = Hash.new
							exec_opts[:command] = switches.join
							exec_opts[:file] = out_path
							exec_opts[:app] = 'wav2png'
							output[:commands] << exec_opts
							switches = Array.new
						else
							switches.unshift Job.__switch(data[:waved_file], 'i')
							unless FloatUtil.cmp(data[:offset], FloatUtil::Zero) and FloatUtil.cmp(data[:length], data[:duration]) then
								switches << Job.__switch("'atrim=start=#{data[:offset]}:duration=#{audio_duration},asetpts=expr=PTS-STARTPTS'", 'af') 
							end
							switches << Job.__switch(1, 'async')
			
						end
					else
						avb = (AV::Audio == avb ? AV::Neither : AV::Video)
					end
				end
					
				unless switches.empty? then # we've got audio and/or video
					duration = FloatUtil.max(audio_duration, video_duration)
					cmd = switches.join
					cmd += Job.__output_command output, avb, (type_is_video_or_audio ? duration : nil)
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
			path = Path.concat @configuration[:render_directory], identifier
			Path.add_slash_end path
		end
		def __process_download
			unless @hash[:error] then 
				__callback :initiate
				inputs.each do |input|
					
					input_url = input[:input_url]
					if input_url then
						# if it's a mash we won't know if it has desired content types until cached and parsed
						if (Input::TypeMash == input[:type]) or AV.includes?(Job.__av_type_for_input(input), @outputs_desire) then
							base_src, module_src = Job.__input_sources input, self
							__cache_input input, input_url, base_src, module_src
							if (Input::TypeMash == input[:type]) then # read and parse mash json file
								input[:source] = JSON.parse(File.read(input[:cached_file])) 
								Job.__init_mash_input input
								progress[:downloading] += Job.__mash_url_count input[:source], @outputs_desire, base_src, module_src
							end
						end
					end
					if (Input::TypeMash == input[:type]) and AV.includes?(Job.__av_type_for_input(input), @outputs_desire) then
						__cache_job_mash input
					end
					break if @hash[:error]
				end
				__update_timing
				__update_sizing
				__construct_commands
			end
			! @hash[:error]
		end
		def __process_render
			unless @hash[:error] then 
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
			! @hash[:error]
		end
		def __process_upload
			unless @hash[:error] then 
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
			! @hash[:error]
		end
		def __render_path output
			out_file = (Output::TypeSequence == output[:type] ? "/#{output[:name]}#{output[:sequence]}" : '')
			out_file = "#{out_file}.#{output[:extension]}"
			out_file = Evaluate.value out_file, __scope(output)
			"#{__output_path output, true}#{out_file}"
		end
		def __s3 source
			unless source[:s3] 
				require 'aws-sdk' unless defined? AWS
				source[:s3] = ((source[:region] and not source[:region].empty?) ? AWS::S3.new(:region => source[:region]) : AWS::S3.new)
			end
			source[:s3]
		end
		def __s3_bucket source
			source[:s3_bucket] ||= __s3(source).buckets[source[:bucket]]
		end
		def __scope object = nil
			scope = Hash.new
			scope[:job] = self
			scope[object.class_symbol] = object  if object and object.is_a? JobHash
			scope
		end
		def __set_info(path, type, data)
			result = nil
			if type and path then
				info_file_path = __meta_path(type, path)
				File.open(info_file_path, 'w') {|f| f.write(data) }
			end
		end
		def __transfer_file mode, source_path, out_file
			#source_path = Path.add_slash_start source_path
			source_path = File.expand_path source_path
			if File.exists? source_path
				#out_file = Path.add_slash_start out_file
				out_file = File.expand_path out_file
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
			output_content_type = output[:mime_type]
			raise Error::JobInput.new "output has no destination" unless output_destination 
		
			if File.exists?(file) then
				if output_destination[:archive] || output[:archive] then
					raise Error::Todo.new "support for archive option coming..."
				end
				destination_path = Job.__evaluated_path_for_transfer output_destination, __scope(output), output
				raise Error::Parameter.new "got invalid destination path with percent sign #{destination_path}" if destination_path.include? '%'
				case output_destination[:type]
				when Transfer::TypeFile
					__file_safe(File.dirname(destination_path))
					__transfer_file output_destination[:method], file, destination_path
					output_destination[:file] = destination_path # for spec tests to find file...
					progress[:uploaded] += (File.directory?(file) ? Dir.entries(file).length : 1)
					__callback :progress
				when Transfer::TypeS3
					files = Array.new
					uploading_directory = File.directory?(file)
					if uploading_directory then
						file = Path.add_slash_end file
						Dir.entries(file).each do |f|
							f = file + f
							files << f unless File.directory?(f)
						end
					else 
						files << file
					end
					files.each do |file|
						bucket_key = Path.strip_slash_start destination_path
						bucket_key = Path.concat(bucket_key, File.basename(file)) if uploading_directory
						#puts "bucket_key = #{bucket_key}"
						bucket = __s3_bucket output_destination
						bucket_object = bucket.objects[bucket_key]
						options = Hash.new
						options[:acl] = output_destination[:acl].to_sym if output_destination[:acl]
						options[:content_type] = output_content_type if output_content_type
						log_entry(:debug) { "s3 write to #{bucket_key}" }
						bucket_object.write(Pathname.new(file), options)
						progress[:uploaded] += 1
						__callback :progress
					end
		
				when Transfer::TypeHttp, Transfer::TypeHttps
					url = "#{output_destination[:type]}://#{output_destination[:host]}"
					url += Path.add_slash_start destination_path
					uri = URI(url)
					uri.port = output_destination[:port].to_i if output_destination[:port]
					__transfer_uri_parameters output, uri, output_destination
					uploading_directory = File.directory?(file)
					files = Array.new
					if uploading_directory then
						file += '/' unless file.end_with? '/'
						Dir.entries(file).each do |f|
							f = file + f
							files << f unless File.directory?(f)
						end
					else 
						files << file
					end
					files.each do |file|
						file_name = File.basename file
						io = File.open(file)
						raise Error::Object.new "could not open file #{file}" unless io
						upload_io = UploadIO.new(io, output_content_type, file_name)
						req = Net::HTTP::Post::Multipart.new(uri, "key" => destination_path, "file" => upload_io)
						raise Error::JobUpload.new "could not construct multipart POST request" unless req
						req.basic_auth(output_destination[:user], output_destination[:pass]) if output_destination[:user] and output_destination[:pass]
						res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
							result = http.request(req)
							if '200' == result.code then
								log_entry(:debug) {"uploaded #{file} #{uri}\n#{result.body}"}
							else
								log_entry(:error) { "#{result.code} upload response #{result.body}" }
							end
						end
						io.close 
						progress[:uploaded] += 1
						__callback :progress
					end
				end
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
						#puts "copying parameters #{parameters}"
						parameters = Marshal.load(Marshal.dump(parameters)) 
						#puts "evaluating parameters #{parameters}"
						Evaluate.object parameters, __scope(scope_object)
						#puts "encoding parameters #{parameters}"
						parameters = URI.encode_www_form(parameters)
						#puts "setting query parameters #{parameters}"
						uri.query = parameters
					
					end
				else 
					#puts "EMPTY #{parameters} #{transfer}"
				end
			else
				#puts "EMPTY uri #{uri} or transfer #{transfer}"
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
				length = Job.__input_length(input)
				start_video = input[:start] + length unless input[:no_video]
				start_audio = input[:start] + length unless input[:no_audio]
				input[:range] = Job.__input_trim_range(input)
				input[:offset] = Job.__input_trim input
				input[:length] = Job.__input_length input
						
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
						mash = input[:source]
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
