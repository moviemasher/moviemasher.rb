
module MovieMasher
	TypeVideo = 'video'
	TypeSequence = 'sequence'
	TypeAudio = 'audio'
	TypeImage = 'image'
	TypeFont = 'font'
	TypeFrame = 'frame'
	TypeMash = 'mash'
	TypeWaveform = 'waveform'
	TypeTheme = 'theme'
	TypeEffect = 'effect'
	TypeMerger = 'merger'
	TypeScaler = 'scaler'
	TypeTransition = 'transition'
	InitiateTrigger = 'initiate'
	DoneTrigger = 'done'
	CompleteTrigger = 'complete'
	ErrorTrigger = 'error'
	TrackTypeVideo = TypeVideo
	TrackTypeAudio = TypeAudio
	SourceTypeFile = 'file'
	SourceTypeHttp = 'http'
	SourceTypeHttps = 'https'
	SourceTypeS3 = 's3'
	SourceModeSymlink = 'symlink'
	SourceModeMove = 'move'
	SourceModeCopy = 'copy'
	RegexFunctionCalls = /([\w]+)\((.+)\)/
	RegexVariables = /([\w]+)/
	AVVideo = 'v'
	AVAudio = 'a'
	AVBoth = 'b'
	TrackTypes = [TrackTypeAudio, TrackTypeVideo]
	MASH_FILL_NONE = 'none'
	MASH_FILL_STRETCH = 'stretch'
	MASH_FILL_CROP = 'crop'
	MASH_FILL_SCALE = 'scale'
	
	MASH_VOLUME_NONE = '0,1,1,1'
	MASH_VOLUME_MUTE = '0,0,1,0'
	INTERMEDIATE_AUDIO_EXTENSION = 'wav' # file extension for audio portion
	INTERMEDIATE_VIDEO_CODEC = 'png' #'mpeg2video';#''; # -vcodec switch
	INTERMEDIATE_VIDEO_EXTENSION = 'mov' #'mpg'; # file extension for video portion
	PIPE_VIDEO_EXTENSION = 'mpg' # used for piped and concat files
	PIPE_VIDEO_FORMAT = 'yuv4mpegpipe' # -f:v switch for piped and concat files
	
	@@formats = nil
	@@codecs = nil
	def self.codecs
		@@codecs = __ffmpeg_command('-codecs') unless @@codecs
		@@codecs
	end
	def self.formats
		@@formats = __ffmpeg_command('-formats') unless @@formats
		@@formats
	end
	def self.process orig_job
		job = valid? orig_job
		#puts "JOB\n#{job}\nORIGJOB\n#{orig_job}"
		raise "invalid job" unless job  # makes a copy with keys as symbols instead of strings
		#puts "job #{job.inspect}"
		input_ranges = Array.new
		copy_files = Hash.new # key is value of input[:copy] (basename for copied input)
		output_inputs = Hash.new # key is output id, value is array of intersecting input refs
		video_outputs = Array.new
		audio_outputs = Array.new
		mash_inputs = job[:inputs].select { |i| TypeMash == i[:type] }
		job[:outputs].each do |output|
			video_outputs << output unless AVAudio == output[:desires]
			audio_outputs << output unless AVVideo == output[:desires]
		end
		output_desires = (0 < video_outputs.length ? (0 < audio_outputs.length ? AVBoth : AVVideo) : AVAudio)
		__trigger job, InitiateTrigger
		job[:inputs].each do |input|
			input_url = __input_url job, input, (input[:base_source] || job[:base_source])
			if input_url then
				if (TypeMash == input[:type]) or __has_desired?(__input_has(input), output_desires) then
					if not job[:cached][input_url] then 
						job[:cached][input_url] = __cache_input job, input, (input[:base_source] || job[:base_source]), input_url
					end
					# TODO: handle copy flag in input
					copy_files[input[:copy]] = job[:cached][input_url] if input[:copy]
				else
					#puts "__has_desired?(__input_has(input), output_desires) = #{__has_desired?(__input_has(input), output_desires)}"
					#puts "__has_desired?(#{__input_has(input)}, #{output_desires})"
					#puts "__input_has(input) == output_desires #{__input_has(input) == output_desires}"
				end
				if (TypeMash == input[:type]) then
					input[:source] = JSON.parse(File.read(job[:cached][input_url])) 
					__init_input_mash input
				end
			end
			if (TypeMash == input[:type]) and __has_desired?(__input_has(input), output_desires) then
				__cache_job_mash job, input
			end
		end
		# everything that needs to be cached is now cached
		__set_timing job
		if not video_outputs.empty? then
			# make sure visual outputs have dimensions, using input's for default
			input_dimensions = __input_dimensions job
			video_outputs.each do |output|
				output[:dimensions] = input_dimensions unless output[:dimensions]
			end
			# sort visual outputs by dimensions, fps
			video_outputs.sort! do |a, b|
				if a[:type] == b[:type] then
					a_ratio = __aspect_ratio(a[:dimensions])
					b_ratio = __aspect_ratio(b[:dimensions])
					if a_ratio == b_ratio then
						a_dims = a[:dimensions].split 'x'
						b_dims = b[:dimensions].split 'x'
						if a_dims[0].to_i == b_dims[0].to_i then
							return 0 if a[:fps] == b[:fps] 
							return (a[:fps].to_i > b[:fps].to_i ? -1 : 1)
						end
						return (a_dims[0].to_i > b_dims[0].to_i ? -1 : 1)
					end
					# different types with different aspect ratios are sorted by type
				end
				return ((TypeVideo == a[:type]) ? -1 : 1)
			end
			
		end
		video_graphs = (video_outputs.empty? ? Array.new : __filter_graphs_video(job[:inputs]))
		audio_graphs = (audio_outputs.empty? ? Array.new : __filter_graphs_audio(job[:inputs]))
		
		
		# do video outputs first
		video_outputs.each do |output|
			__build_output job, output, video_graphs, audio_graphs
		end
		# then audio and other outputs
		audio_outputs.each do |output|
			__build_output job, output, video_graphs, audio_graphs
		end
		job[:outputs].each do |output|
			__transfer_job_output job, output
		end
		job
	end
	def self.valid? job
		valid = false
		if job and job.is_a? Hash then
			job = Marshal.load(Marshal.dump(job))
			__change_keys_to_symbols! job
			if job[:inputs] and job[:inputs].is_a?(Array) and not job[:inputs].empty? then
				if job[:outputs] and job[:outputs].is_a?(Array) and not job[:outputs].empty? then
					job[:inputs].each do |input| 
						__init_input input
					end
					job[:outputs].each do |output| 
						__init_output output
					end
					# TODO: more validation!
					job[:cached] = Hash.new
					job[:id] = UUID.new.generate unless job[:id]
					valid = job
				end
			end
		end
		valid
	end
	def self.__aspect_ratio dimensions
		result = dimensions
		if dimensions then
			wants_string = dimensions.is_a?(String)
			dimensions = dimensions.split('x') if wants_string
			w = dimensions[0].to_i
			h = dimensions[1].to_i
			gcf = __cache_gcf(w, h)
			result = [w / gcf, h / gcf]
			result = result.join('x') if wants_string
		end
		result
	end
	def self.__audio_from_file path
		raise "__audio_from_file with invalid path" unless path and (not path.empty?) and File.exists? path
		out_file = "#{File.dirname path}/#{File.basename path}-intermediate.#{INTERMEDIATE_AUDIO_EXTENSION}"
		unless File.exists? out_file then
			cmds = Array.new
			cmds << __cache_switch(path, 'i')
			cmds << __cache_switch(2, 'ac')
			cmds << __cache_switch(44100, 'ar')
			__ffmpeg_command cmds.join(' '), out_file
		end
		out_file
	end
	def self.__cache_gcf a, b 
		 ( ( b == 0 ) ? a : __cache_gcf(b, a % b) )
	end
	def self.__build_output job, output, video_graphs, audio_graphs
		unless output[:rendering] then
			cmd = ''
			duration = FLOAT_ZERO
			audio_duration = FLOAT_ZERO
			unless video_graphs.empty? then
				if 1 == video_graphs.length then
					graph = video_graphs[0]
					duration = graph.duration
					cmd = graph.command output
					raise "Could not build complex filter" if cmd.empty?
				else 
					cmd = __filter_graphs_concat output, video_graphs
					raise "Could not build complex filter" if cmd.empty?
					video_graphs.each do |graph|
						duration += graph.duration
					end
				end
				cmd = "-filter_complex '#{cmd}' -t #{duration} "
			end
			unless audio_graphs.empty? then
				audio_graphs_count = audio_graphs.length
				data = audio_graphs[0]
				unless 1 == audio_graphs_count and 1 == data[:loops] and MASH_VOLUME_NONE == data[:volume] and float_cmp(data[:start_seconds], FLOAT_ZERO) then
					# merge audio and feed resulting file to ffmpeg
					audio_cmd = ''
					counter = 1
					start_counter = FLOAT_ZERO
					audio_graphs_count.times do |audio_graphs_index|
						data = audio_graphs[audio_graphs_index]
						loops = data[:loops] || 1
						volume = data[:volume]
						start = data[:start_seconds]
						raise "negative start time" unless float_gtre(start, FLOAT_ZERO)
						data[:waved_file] = __audio_from_file(data[:cached_file]) unless data[:waved_file]
						audio_cmd += " -a:#{counter} -i "
						counter += 1
						audio_cmd += 'audioloop,' if 1 < loops
						audio_cmd += "playat,#{data[:start_seconds]},"
						audio_cmd += "select,#{data[:trim_seconds]},#{data[:length_seconds]}"
						audio_cmd += ",#{data[:waved_file]}"
						audio_cmd += ' -t:' + data[:length_seconds] if 1 < loops
						unless MASH_VOLUME_NONE == volume then
							volume = volume.split ','
							z = volume.length / 2
							audio_cmd += " -ea:0 -klg:1,0,100,#{z}"
							z.times do |i|
								p = (i + 1) * 2
								pos = volume[p - 2].to_f
								val = volume[p - 1].to_f
								pos = (data[:length_seconds] * loops.to_f * pos) if (float_gtr(pos, FLOAT_ZERO)) 									
								audio_cmd += ",#{__cache_time(start + pos)},#{val}"
							end
						end
						#puts "audio_duration #{data[:start_seconds]} + #{data[:length_seconds]}"
						audio_duration = float_max(audio_duration, data[:start_seconds] + data[:length_seconds])
					end
					audio_cmd += ' -a:all -z:mixmode,sum'
					audio_cmd += ' -o'
					audio_path = output_path output
					audio_path += "audio-#{Digest::SHA2.new(256).hexdigest(audio_cmd)}.#{INTERMEDIATE_AUDIO_EXTENSION}"
					unless File.exists? audio_path then
						__ffmpeg_command(audio_cmd, audio_path, audio_duration, 'ecasound')
					end
					data = Hash.new
					data[:type] = TypeAudio
					data[:trim_seconds] = FLOAT_ZERO
					data[:length_seconds] = audio_duration
					data[:waved_file] = audio_path
				else
					audio_duration = data[:length_seconds]
				end
				data[:waved_file] = __audio_from_file(data[:cached_file]) unless data[:waved_file]
				cmds = Array.new
				cmds << __cache_switch(data[:waved_file], 'i')
				if float_cmp(data[:trim_seconds], FLOAT_ZERO) and float_cmp(data[:length_seconds], output[:duration]) then
					cmds << __cache_switch(data[:length_seconds], 't')
				else
					cmds << __cache_switch("'atrim=start=#{data[:trim_seconds]}:duration=#{audio_duration},asetpts=expr=PTS-STARTPTS'", 'af') 
				end
				cmd += cmds.join(' ')
				duration = float_max(audio_duration, duration)
			end
			if not cmd.empty? then
				#puts "audio_graphs: #{audio_graphs}"
				cmd += __output_command output, (audio_graphs.empty? ? AVVideo : (video_graphs.empty? ? AVAudio : AVBoth))
				output[:rendering] = __output_path job, output
				cmd = '-y ' + cmd
				#puts cmd
				raise "duration does not match length #{duration} != #{job[:duration]}" if duration and not float_cmp(duration, job[:duration])
				__ffmpeg_command cmd, output[:rendering], duration
			end
		end
	end	
	def self.__cache_meta_path type, file_path
		parent_dir = File.dirname file_path
		base_name = File.basename file_path
		parent_dir + '/' + base_name + '.' + type + '.txt'
	end
	def self.__cache_set_info(path, key_or_hash, data = nil)
		result = nil
		if key_or_hash and path then
			hash = Hash.new
			if key_or_hash.is_a?(Hash) then
				hash = key_or_hash
			else
				hash[key_or_hash] = data
			end
			hash.each do |k, v|
				info_file_path = __cache_meta_path(k, path)
				File.open(info_file_path, 'w') {|f| f.write(v) }
			end
		end
	end
	def self.__cache_file_type path
		result = nil
		if path then
			result = __cache_get_info path, 'type'
			if not result then
				mime = __cache_get_info path, 'Content-Type'
				if not mime then
					ext = File.extname(path)
					mime = Rack::Mime.mime_type(ext)
					#puts "LOOKING UP MIME: #{ext} #{mime}"
				end
				result = mime.split('/').shift if mime
				__cache_set_info(path, 'type', result) if result 
			end
		end
		result
	end
	def self.__cache_get_info file_path, type
		raise "bad parameters #{file_path}, #{type}" unless type and file_path and (not (type.empty? or file_path.empty?))
		result = nil
		if File.exists?(file_path) then
			info_file = __cache_meta_path type, file_path
			if File.exists? info_file then
				result = File.read info_file
			else
				check = Hash.new
				case type
				when 'type', 'http', 'ffmpeg', 'sox' 
					# do nothing if file doesn't already exist
				when 'dimensions'
					check[:ffmpeg] = true
				when 'ffmpegduration'
					check[:ffmpeg] = true
					type = 'duration'
				when 'soxduration'
					check[:sox] = true
					type = 'duration'
				when 'duration'
					check[TypeAudio == __cache_file_type(file_path) ? :sox : :ffmpeg] = true
				when 'fps', TypeAudio # only from FFMPEG
					check[:ffmpeg] = true
				end
				if check[:ffmpeg] then
					data = __cache_get_info(file_path, 'ffmpeg')
					if not data then
						cmd = " -i #{file_path}"
						data = __ffmpeg_command cmd
						__cache_set_info file_path, 'ffmpeg', data
					end
					result = __cache_info_from_ffmpeg(type, data) if data
				elsif check[:sox] then
					data = __cache_get_info(file_path, 'sox')
					if not data then
						cmd = "#{CONFIG['path_sox']} --i #{file_path}"
						#puts "CMD #{cmd}"
						data = __shell_command cmd
						__cache_set_info(file_path, 'sox', data)
					end
					result = __cache_info_from_ffmpeg(type, data) if data
				end
				# try to cache the data for next time
				__cache_set_info(file_path, type, result) if result
			end
		end
		result
	end
	def self.__cache_info_from_ffmpeg type, ffmpeg_output
		result = nil
		case type
		when TypeAudio
			/Audio: ([^,]+),/.match(ffmpeg_output) do |match|
				if 'none' != match[1] then
					result = 1
				end
			end
		when 'dimensions'
			/, ([\d]+)x([\d]+)/.match(ffmpeg_output) do |match|
				result = match[1] + 'x' + match[2]
			end
		when 'duration'
			/Duration\s*:\s*([\d]+):([\d]+):([\d\.]+)/.match(ffmpeg_output) do |match|
				result = 60 * 60 * match[1].to_i + 60 * match[2].to_i + match[3].to_f
			end
		when 'fps'
			match = / ([\d\.]+) fps/.match(ffmpeg_output)
			match = / ([\d\.]+) tb/.match(ffmpeg_output) unless match 
			result = match[1].to_f.round	
		end
		result
	end
	def self.__cache_input job, input, base_source = nil, input_url = nil
		puts "__cache_input #{input}, #{base_source}, #{input_url} "
		input_url = __input_url(job, input, base_source) unless input_url
		cache_url_path = nil
		if input_url then
			cache_url_path = __cache_url_path input_url
			unless File.exists? cache_url_path then
				source = input[:source]
				if source.is_a? String then
					if source == input_url then
						source = __source_from_uri(URI input_url)
					else 
						# base_source must have changed it
						new_source = Marshal.load(Marshal.dump(base_source))
						new_source[:name] = source
						source = new_source
					end
				end
				raise "no source for #{input_url}" unless source
				__cache_source job, source, cache_url_path
				raise "could not cache #{input_url}" unless File.exists? cache_url_path
			end
			puts "cached_file #{cache_url_path} #{input}"
			input[:cached_file] = cache_url_path
			case input[:type]
			when TypeVideo
				input[:duration] = __cache_get_info(cache_url_path, 'duration').to_f unless input[:duration] and float_gtr(input[:duration], FLOAT_ZERO)
				input[:no_audio] = ! __cache_get_info(cache_url_path, TypeAudio)
				input[:dimensions] = __cache_get_info(cache_url_path, 'dimensions')
				input[:no_video] = ! input[:dimensions]
			when TypeAudio
				input[:duration] = __cache_get_info(cache_url_path, 'duration').to_f unless input[:duration] and float_gtr(input[:duration], FLOAT_ZERO)
			when TypeImage 
				input[:dimensions] = __cache_get_info(cache_url_path, 'dimensions')
				#puts "INPUT DIMENSIONS #{input[:dimensions]} for #{input_url}"
				raise "could not determine image dimensions" unless input[:dimensions]
			end
		else
			raise "could not produce an input_url #{input}"
		end
		cache_url_path
	end
	def self.__cache_job_mash job, input
		mash = input[:source]
		base_source = (input[:base_source] || job[:base_source])
		mash[:media].each do |media|
			puts "__cache_job_mash media #{media[:type]} #{media}"
			case media[:type]
			when TypeVideo, TypeAudio, TypeImage, TypeFont
				__cache_input job, media, base_source
			end
		end
	end
	def self.__cache_source job, source, out_file
		FileUtils.mkdir_p(File.dirname(out_file))
		case source[:type]
		when SourceTypeFile
			source_file = __directory_path_name job, source
			__transfer_file source[:mode], source_file, out_file
		when SourceTypeHttp, SourceTypeHttps
			url = "#{source[:type]}://#{source[:host]}"
			path = __directory_path_name job, source
			url += '/' unless path.start_with? '/'
			url += path
			uri = URI url
			uri.port = source[:port] if source[:port]
			#params = { :limit => 10, :page => 3 }
			#uri.query = URI.encode_www_form(params)
			Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
				request = Net::HTTP::Get.new uri
				http.request request do |response|
					open out_file, 'w' do |io|
						response.read_body do |chunk|
							io.write chunk
						end
					end
				end
			end
		when SourceTypeS3
			bucket = S3.buckets[source[:bucket]]
			bucket_key = __directory_path_name job, source
    		object = bucket.objects[bucket_key]
			object_read_data = object.read
			File.open(out_file, 'w') { |file| file.write(object_read_data) }
		end
		out_file
	end
	def self.__cache_switch(value, prefix = '', suffix = '')
		switch = ''
		value = value.to_s.strip
		if value and not value.empty? then
			switch += ' ' # always add a leading space
			if value.start_with? '-' then # it's a switch, just include and ignore rest
				switch += value 
			else # prepend value with prefix and space
				switch += '-' unless prefix.start_with? '-'
				switch += prefix + ' ' + value
				switch += suffix unless switch.end_with? suffix # note lack of space!
			end
		end
		switch
	end
	def self.__cache_time seconds, precision = 3
		divisor = (precision * 10).to_f
		(seconds.to_f * divisor).floor / divisor
	end
	def self.__cache_url_path url
		path = CONFIG['path_cache']
		if not path.end_with?('/') then
			path += '/' 
		end
		path += __hash url
		path += '/cached'
		path += File.extname(url)
		path
	end
	def self.__change_keys_to_symbols! hash
		if hash 
			if hash.is_a? Hash then
				hash.keys.each do |k|
					v = hash[k]
					if k.is_a? String then
						k_sym = k.to_sym
						hash[k_sym] = v
						hash.delete k
					end
					__change_keys_to_symbols! v
				end
			elsif hash.is_a? Array then
				hash.each do |v|
					__change_keys_to_symbols! v
				end
			end
		end
		hash
	end
	def self.__clip_has_audio clip
		has = false
		case clip[:type]
		when TypeAudio
			has = (:volume)
		when TypeVideo
			has = ((MASH_VOLUME_MUTE != clip[:volume]) and (0 != clip[:audio]))
		when TypeTheme, TypeTransition, TypeEffect
			#puts "TODO: __clip_has_audio for #{clip[:type]} clips"
		end
		has
	end
	def self.__directory_path_name job, source
		url = source[:key]
		if not url then
			bits = Array.new
			bit = source[:directory]
			if bit then
				bit = bit[0...-1] if bit.end_with? '/'
				bits << bit
			end
			bit = source[:path]
			if bit then
				bit['/'] = '' if bit.start_with? '/'
				bits << bit
			end
			url = bits.join '/'
			url = __transfer_file_name job, source, url
		end
		url
	end
	def self.__ffmpeg_command(cmd, out_file = '', duration = nil, app = 'ffmpeg')
		#puts "__ffmpeg_command #{app}"
		whole_cmd = CONFIG["path_#{app}"]
		whole_cmd += ' ' + cmd
		if not out_file.empty? then
			FileUtils.mkdir_p(File.dirname(out_file))
			whole_cmd += " #{out_file}"
		end # -v debug 
		puts whole_cmd
		result = __shell_command whole_cmd
		if not out_file.empty? then	
			raise "Failed to generate file #{result}\n#{cmd.gsub(';', ";\n")}" unless File.exists?(out_file)
			raise "Generated zero length file #{result}" unless File.size?(out_file)
			if duration then
				file_duration = __cache_get_info(out_file, 'ffmpegduration')
				raise "could not determine duration of #{out_file} #{result}" unless file_duration
				raise "generated file with incorrect duration #{duration} != #{file_duration} #{result}" unless float_cmp(duration, file_duration.to_f, 1)
			end
		end 
		result
	end
	
	
	def self.__filter_scope_map scope, stack, key
		parameters = stack[key]
		if parameters then
			parameters.map! do |param|
				raise "__filter_scope_map #{key} got empty param #{stack} #{param}" unless param and not param.empty?
				__filter_scope_call scope, param
			end
		end
		((parameters and (not parameters.empty?)) ? parameters : nil)
	end
	def self.__filter_scope_call scope, stack
		raise "__filter_scope_call got false stack #{scope}" unless stack
		result = ''
		if stack.is_a? String then
			result = stack
		else
			array = __filter_scope_map scope, stack, :params
			if array then
				raise "WTF" if array.empty?
				if stack[:function] then
					func_sym = stack[:function].to_sym
					if FilterHelpers.respond_to? func_sym then
						result = FilterHelpers.send func_sym, array, scope
						raise "got false from  #{stack[:function]}(#{array.join ','})" unless result
						
						result = result.to_s unless result.is_a? String
						raise "got empty from #{stack[:function]}(#{array.join ','})" if result.empty?
					else
						result = "#{stack[:function]}(#{array.join ','})"
					end
				else
					result = "(#{array.join ','})"
				end
			end
			array = __filter_scope_map scope, stack, :prepend
			result = array.join('') + result if array
			array = __filter_scope_map scope, stack, :append
			result += array.join('') if array
		end
			raise "__filter_scope_call has no result #{stack}" if result.empty?
		result
	end 
	def self.__filter_parse_scope_value scope, value_str
		#puts "value_str = #{value_str}"
	 	level = 0
		deepest = 0
		esc = '.'
		# expand variables
		value_str = value_str.dup
		value_str.gsub!(RegexVariables) do |match|
			match_str = match.to_s
			match_sym = match_str.to_sym
			if scope[match_sym] then
				scope[match_sym].to_s 
			else
				match_str
			end
		end
		#puts "value_str = #{value_str}"

	 	value_str.gsub!(/[()]/) do |paren|
	 		result = paren.to_s
	 		case result
	 		when '('
	 			level += 1
	 			deepest = [deepest, level].max
	 			result = result + level.to_s + esc
	 		when ')'
	 			result = result + level.to_s + esc
	 			level -= 1
	 		end
	 		result
	 	end
	 	#puts "value_str = #{value_str}"
	 	while 0 < deepest
			value_str.gsub!(Regexp.new("([a-z_]+)[(]#{deepest}[.]([^)]+)[)]#{deepest}[.]")) do |m|
				#puts "level #{level} #{m}"
				method = $1
				param_str = $2
				params = param_str.split(',')
				params.each do |param|
					param.strip!
					param.gsub!(/([()])[0-9]+[.]/) {$1}
				end
				func_sym = method.to_sym
				if FilterHelpers.respond_to? func_sym then
					result = FilterHelpers.send func_sym, params, scope
					raise "got false from  #{method}(#{params.join ','})" unless result
					
					result = result.to_s unless result.is_a? String
					raise "got empty from #{method}(#{params.join ','})" if result.empty?
				else
					result = "#{method}(#{params.join ','})"
				end
				result			
			end
			deepest -= 1
	 		#puts "value_str = #{value_str}"
	 	end
	 	# remove any lingering markers
	 	value_str.gsub!(/([()])[0-9]+[.]/) { $1 }
	 	# remove whitespace
	 	value_str.gsub!(/\s/, '')
	 	#puts "value_str = #{value_str}"
	 	value_str
	end
	def self.__filter_scope_binding scope
		bind = binding
		scope.each do |k,v|
			bind.eval "#{k.id2name}='#{v}'"
		end
		bind
	end
	def self.__filter_scope_value scope, value
		#puts "__filter_scope_value #{value}"
		result = nil
		if value.is_a? String 
			result = __filter_parse_scope_value scope, value
		else
			bind = __filter_scope_binding scope
			condition_is_true = false
			value.each do |conditional|
				condition_is_true = bind.eval(conditional[:condition])
				if condition_is_true then
					
					result = __filter_parse_scope_value scope, conditional[:value]
					#puts "__filter_scope_value\n#{conditional[:value]}\n#{result}"
					break
				end
			end
			raise "no conditions were true" unless condition_is_true
		end
		result
	end
	
	def self.__filter_graphs_audio inputs
		graphs = Array.new
		start_counter = FLOAT_ZERO
		inputs.each do |input|
			next if input[:no_audio]
			#puts "INPUT: #{input}\n"
			case input[:type]
			when TypeVideo, TypeAudio
				data = Hash.new
				data[:type] = input[:type]
				data[:trim_seconds] = __get_trim input
				data[:length_seconds] = __get_length input
				data[:start_seconds] = input[:start]	
				data[:cached_file] = input[:cached_file]
				data[:volume] = input[:volume]
				data[:loops] = input[:loops]
				graphs << data
			when TypeMash
				quantize = input[:source][:quantize]
				audio_clips = __mash_clips_having_audio input[:source]
				audio_clips.each do |clip|
					unless clip[:cached_file] then
						media = mash_search mash, clip[:id]
						raise "could not find media for clip #{clip[:id]}" unless media
						clip[:cached_file] = media[:cached_file] || raise("could not find cached file")
					end
					data = Hash.new
					data[:type] = clip[:type]
					data[:trim_seconds] = clip[:trim_seconds]
					data[:length_seconds] = clip[:length_seconds]
					#puts "start_seconds = #{input[:start]} + #{quantize} * #{clip[:frame]}"
					data[:start_seconds] = input[:start].to_f + clip[:frame].to_f / quantize.to_f
					data[:cached_file] = clip[:cached_file]
					data[:volume] = clip[:volume]
					data[:loops] = clip[:loops]
					graphs << data
				end
			end
		end
		graphs
	end
	def self.__filter_graphs_concat output, graphs
		cmds = Array.new
		intermediate_output = __output_intermediate
		graphs.length.times do |index|
			graph = graphs[index]
			duration = graph.duration
			cmd = graph.command output
			raise "Could not build complex filter" if cmd.empty?
			cmd += ",format=pix_fmts=yuv420p"
			cmd = " -filter_complex '#{cmd}' -t #{duration}"
			cmd += __output_command intermediate_output, AVVideo
			out_file = CONFIG['path_temporary']
			out_file += '/' unless out_file.end_with? '/'
			out_file += output[:identifier] + '/' if output[:identifier]
			out_file += "concat-#{cmds.length}.#{intermediate_output[:extension]}"
			cmd = '-y' + cmd
			__ffmpeg_command cmd, out_file			
			cmds << "movie=filename=#{out_file}[concat#{cmds.length}]"
		end
		cmd = ''
		cmds.length.times do |i|
			cmd += "[concat#{i}]"
		end
		cmd += "concat=n=#{cmds.length}" #,format=pix_fmts=yuv420p
		cmds << cmd
		cmds.join ';'
	end
	def self.__filter_graphs_video inputs
		graphs = Array.new
		raise "__filter_graphs_video already called" unless 0 == graphs.length
		inputs.each do |input|
			#puts "input #{input}"
			next if input[:no_video]
			case input[:type]
			when TypeMash
				mash = input[:source]
				all_ranges = __mash_video_ranges mash
				all_ranges.each do |range|
					#put "mash Graph.new #{range.inspect}"
					graph = Graph.new input, range, mash[:backcolor]
					clips = __mash_clips_in_range mash, range, TrackTypeVideo
					if 0 < clips.length then
						transition_layer = nil
						transitioning_clips = Array.new
						clips.each do |clip|
							case clip[:type]
							when TypeVideo, TypeImage
								# media properties were copied to clip BEFORE file was cached, so repeat now
								media = mash_search mash, clip[:id]
								raise "could not find media for clip #{clip[:id]}" unless media
								clip[:cached_file] = media[:cached_file] || raise("could not find cached file")
								clip[:dimensions] = media[:dimensions] || raise("could not find dimensions #{clip} #{media}")
							end	
							if TypeTransition == clip[:type] then
								raise "found two transitions within #{range.inspect}" if transition_layer
								transition_layer = graph.create_layer clip
							elsif 0 == clip[:track] then
								transitioning_clips << clip
							end
						end
						if transition_layer then
							#puts "transitioning_clips[0][:frame] #{transitioning_clips[0][:frame]}" if 0 < transitioning_clips.length
							#puts "transitioning_clips[1][:frame] #{transitioning_clips[1][:frame]}" if 1 < transitioning_clips.length
							raise "too many clips on track zero" if 2 < transitioning_clips.length
							if 0 < transitioning_clips.length then
								transitioning_clips.each do |clip| 
									#puts "graph.new_layer clip"
									transition_layer.layers << graph.new_layer(clip)
								end 
							end
						end
						clips.each do |clip|
							next if transition_layer and 0 == clip[:track] 
							case clip[:type]
							when TypeVideo, TypeImage, TypeTheme
								#puts "graph.create_layer clip"
								graph.create_layer clip
							end
						end
					end
					graphs << graph
				end
			when TypeVideo, TypeImage
				#puts "Graph.new #{input[:range].inspect}"
				graph = Graph.new input, input[:range]
				graph.create_layer(input)
				graphs << graph
			end
		end
		graphs
	end
  	def self.__filter_init id, parameters = Hash.new
  		filter = Hash.new
		filter[:id] = id
		filter[:out_labels] = Array.new
		filter[:in_labels] = Array.new
		filter[:parameters] = parameters
		filter
  	end
	
	def self.__filter_merger_default
		filter_config = Hash.new
		filter_config[:type] = TypeMerger
		filter_config[:filters] = Array.new
		overlay_config = Hash.new
		overlay_config[:id] = 'overlay'
		overlay_config[:parameters] = Array.new
		overlay_config[:parameters] << {:name => 'x', :value => '0'}
		overlay_config[:parameters] << {:name => 'y', :value => '0'}
		filter_config[:filters] << overlay_config
		filter_config
	end
	def self.__filter_scaler_default
		filter_config = Hash.new
		filter_config[:type] = TypeScaler
		filter_config[:filters] = Array.new
		scale_config = Hash.new
		scale_config[:id] = 'scale'
		scale_config[:parameters] = Array.new
		scale_config[:parameters] << {:name => 'width', :value => 'mm_width'}
		scale_config[:parameters] << {:name => 'height', :value => 'mm_height'}
		filter_config[:filters] << scale_config
		filter_config
	end

	def self.__get_length output
		__get_time output, :length
	end
	def self.__get_range input
		range = FrameRange.new(input[:start], 1, 1)
		range(input[:fps]) if TypeVideo == input[:type]
		range
	end	
	def self.__get_time output, key
		length = FLOAT_ZERO
		if float_gtr(output[key], FLOAT_ZERO) then
			sym = "#{key.id2name}_is_relative".to_sym
			if output[sym] then
				if float_gtr(output[:duration], FLOAT_ZERO) then
					if '%' == output[sym] then
						length = (output[key] * output[:duration]) / FLOAT_HUNDRED
					else 
						length = output[:duration] - output[key]
					end
				end
			else 
				length = output[key]
			end
		elsif :length == key and float_gtr(output[:duration], FLOAT_ZERO) then
			output[key] = output[:duration] - __get_trim(output)
			length = output[key]
		end
		length
	end
	def self.__get_trim output
		__get_time output, :trim
	end
	
	def self.__get_trim_range_simple output
		range = FrameRange.new __get_trim(output), 1, 1
		range.length = __get_length output
		range
	end
	def self.__hash s
		Digest::SHA2.new(256).hexdigest s
	end
	def self.__has_desired? has, desired
		(AVBoth == desired) or (AVBoth == has) or (desired == has) 
	end
	def self.__init_clip input, mash, track_index, track_type
		__init_clip_media input, mash
		input[:frame] = (input[:frame] ? input[:frame].to_f : FLOAT_ZERO)
		# TODO: allow for no start or length in video clips
		# necessitating caching of media if its duration unknown
		raise "mash clips must have length" unless input[:length] and 0 < input[:length]
		input[:range] = FrameRange.new input[:frame], input[:length], mash[:quantize]
		input[:length_seconds] = input[:range].length_seconds unless input[:length_seconds]
		input[:track] = track_index if track_index 
		case input[:type]
		when TypeFrame
			input[:still] = 0 unless input[:still]
			input[:fps] = mash[:quantize] unless input[:fps]
			if 2 > input[:still] + input[:fps] then
				input[:quantized_frame] = 0
			else 
				input[:quantized_frame] = mash[:quantize] * (input[:still].to_f / input[:fps].to_f).round
			end
		when TypeTransition
			input[:to] = Hash.new unless input[:to]
			input[:from] = Hash.new unless input[:from]
			input[:to][:merger] = __filter_merger_default unless input[:to][:merger]
			input[:to][:scaler] = __filter_scaler_default unless input[:to][:scaler] or input[:to][:fill]
			input[:from][:merger] = __filter_merger_default unless input[:from][:merger]
			input[:from][:scaler] = __filter_scaler_default unless input[:from][:scaler] or input[:from][:fill]
		when TypeVideo, TypeAudio
			input[:trim] = 0 unless input[:trim]
			input[:trim_seconds] = input[:trim].to_f / mash[:quantize] unless input[:trim_seconds]
		end
		__init_raw_input input
		# this is done for real inputs during __set_timing
		__init_input_ranges input
		input
  	end
  	def self.__init_input_ranges input
		input[:effects].each do |effect|
			effect[:range] = input[:range]
		end
		input[:merger][:range] = input[:range] if input[:merger] 	
		input[:scaler][:range] = input[:range] if input[:scaler]
  	end
	def self.__init_clip_media clip, mash
		if clip[:id] then
			media = mash_search mash, clip[:id]
			if media then
				media.each do |k,v|
					clip[k] = v unless clip[k]
				end 
			else
				media = Marshal.load(Marshal.dump(clip))
				mash[:media] << media
			end
		end
	end
	def self.__init_input input
		__init_time input, :trim
		__init_key input, :start, FLOAT_NEG_ONE
		__init_key input, :track, 0
		__init_key input, :duration, FLOAT_ZERO
		case input[:type]
		when TypeImage
			__init_key input, :length, 1
		when TypeAudio
		end	
		__init_time input, :length # image will already be one by default
		__init_raw_input input
		# this is done for real inputs during __set_timing
		__init_input_ranges input
		input
	end
	def self.__init_input_mash input
		if __is_a_mash? input[:source] then
			__init_mash input[:source]
			input[:duration] = __mash_duration(input[:source]) if float_cmp(input[:duration], FLOAT_ZERO)
			input[:no_audio] = ! __mash_has_audio?(input[:source])
			input[:no_video] = ! __mash_has_video?(input[:source])
		end
	end
	def self.__init_key output, key, default
		output[key] = output[key] || ''
		output[key] = default if ((not output[key]) or output[key].to_s.empty?)
		if default.is_a?(Float) then
			output[key] = output[key].to_f
		else
			output[key] = output[key].to_i if default.is_a?(Integer) 
		end
	end
	def self.__init_mash mash
		mash[:quantize] = (mash[:quantize] ? mash[:quantize].to_f : FLOAT_ONE)
		mash[:media] = Array.new unless mash[:media] and mash[:media].is_a? Array
		mash[:tracks] = Array.new unless mash[:tracks] and mash[:tracks].is_a? Hash
		longest = FLOAT_ZERO
		TrackTypes.each do |track_type|
			track_sym = track_type.to_sym
			mash[:tracks][track_sym] = Array.new unless mash[:tracks][track_sym] and mash[:tracks][track_sym].is_a? Array
			tracks = mash[:tracks][track_sym]
			track_index = 0
			tracks.each do |track|
				track[:clips] = Array.new unless track[:clips] and track[:clips].is_a? Array
				track[:clips].each do |clip|
					__init_clip clip, mash, track_index, track_type
					__init_clip_media(clip[:merger], mash) if clip[:merger]
					__init_clip_media(clip[:scaler], mash) if clip[:scaler]
					clip[:effects].each do |effect|
						__init_clip_media effect, mash
					end
				end
				clip = track[:clips].last
				if clip then
					longest = float_max(longest, clip[:range].get_end)
				end
				track_index += 1
			end
		end
		mash[:length] = longest
	end
	def self.__init_output output
		__init_key output, :type, TypeVideo
		output[:desires] = __output_desires output
		output[:filter_graphs] = Hash.new
		output[:filter_graphs][:video] = Array.new unless AVAudio == output[:desires]
		output[:filter_graphs][:audio] = Array.new unless AVVideo == output[:desires]
		
		output[:identifier] = UUID.new.generate
		__init_key output, :basename, output[:type]
		__init_key output, :switches, ''
		case output[:type]
		when TypeVideo
			__init_key output, :backcolor, 'black'
			__init_key output, :fps, 30
			__init_key output, :extension, 'flv'
			__init_key output, :video_codec, 'flv'
			__init_key output, :audio_bitrate, '224'
			__init_key output, :audio_codec, 'libmp3lame'
			__init_key output, :dimensions, '512x288'
			__init_key output, :fill, MASH_FILL_NONE
			__init_key output, :volume, MASH_VOLUME_NONE
			__init_key output, :video_frequency, '44100'
			__init_key output, :video_bitrate, '4000'
		when TypeSequence
			__init_key output, :backcolor, 'black'
			__init_key output, :fps, 10
			__init_key output, :extension, 'jpg'
			__init_key output, :dimensions, '256x144'
			__init_key output, :quality, '1'
			output[:no_audio] = true
		when TypeImage
			__init_key output, :backcolor, 'black'
			__init_key output, :quality, '1'							
			__init_key output, :extension, 'jpg'
			__init_key output, :dimensions, '256x144'
			output[:no_audio] = true
		when TypeAudio
			__init_key output, :audio_bitrate, '224'
			__init_key output, :audio_codec, 'libmp3lame'
			__init_key output, :extension, 'mp3'
			__init_key output, :audio_frequency, '44100'
			__init_key output, :volume, MASH_VOLUME_NONE
			output[:no_video] = true
		when TypeWaveform
			__init_key output, :backcolor, 'FFFFFF'
			__init_key output, :dimensions, '8000x32'
			__init_key output, :forecolor, '000000'
			__init_key output, :extension, 'png'
			output[:no_video] = true
		end
		output				
	end
	def self.__init_raw_input input
	
		input[:effects] = Array.new unless input[:effects] and input[:effects].is_a? Array
		input[:merger] = __filter_merger_default unless input[:merger]
		input[:scaler] = __filter_scaler_default unless input[:scaler] or input[:fill]
		
		input_type = input[:type]
		is_av = [TypeVideo, TypeAudio].include? input_type
		is_v = [TypeVideo, TypeImage, TypeFrame].include? input_type
		
		# set volume with default of none (no adjustment)
		__init_key(input, :volume, MASH_VOLUME_NONE) if is_av
		
		__init_key(input, :fill, MASH_FILL_STRETCH) if is_v
		
		# set source from url unless defined
		case input_type
		when TypeVideo, TypeImage, TypeFrame, TypeAudio
			input[:source] = input[:url] unless input[:source]
		end		
		
		# set no_* when we know for sure
		case input_type
		when TypeMash
			__init_input_mash input
		when TypeVideo
			input[:speed] = (input[:speed] ? FLOAT_ONE : input[:speed].to_f) 
			# audio of zero for video is effectively same as volume of mute
			input[:volume] = MASH_VOLUME_MUTE if input[:audio] and 0 == input[:audio]
		when TypeSequence, TypeImage, TypeFrame
			input[:no_audio] = true
		when TypeAudio
			__init_key input, :loops, 1
			input[:no_video] = true
		end		
		input[:no_audio] = true if is_av and (MASH_VOLUME_MUTE == input[:volume])
		input
	end
	def self.__init_time input, key
		if input[key] then
			if input[key].is_a? String then
				input["#{key.id2name}_is_relative".to_sym] = '%'
				input[key]['%'] = ''
			end
			input[key] = input[key].to_f
			if float_gtr(FLOAT_ZERO, input[key]) then
				input["#{key.id2name}_is_relative".to_sym] = '-'
				input[key] = FLOAT_ZERO - input[key]
			end
		else 
			input[key] = FLOAT_ZERO
		end
	end

	def self.__input_dimensions job
		dimensions = nil
		found_mash = false
		job[:inputs].each do |input|
			case input[:type]
			when TypeMash
				found_mash = true
			when TypeImage, TypeVideo
				dimensions = input[:dimensions]
			end
			break if dimensions
		end
		dimensions = -1 if ((! dimensions) && found_mash) 
		dimensions
	end
	def self.__input_has input
		case input[:type]
		when TypeAudio
			AVAudio
		when TypeImage
			AVVideo
		when TypeVideo, TypeMash
			(input[:no_audio] ? AVVideo : input[:no_video] ? AVAudio : AVBoth)
		end
	end
	def self.__input_url job, input, base_source = nil
		url = nil
		if input[:source] then
			if input[:source].is_a? String then
				url = input[:source]
				if not url.include? '://' then
					# relative url
					base_url = __source_url job, base_source
					if base_url then
						base_url += '/' unless base_url.end_with? '/'
						url = URI.join(base_url, url).to_s
					end
				end
			elsif input[:source].is_a? Hash then
				url = __source_url job, input[:source]
			end
		end
		url
	end
	def self.__is_a_mash? hash
		isa = false
		if hash.is_a?(Hash) and hash[:media] and hash[:media].is_a?(Array) then
			if hash[:tracks] and hash[:tracks].is_a? Hash then
				if hash[:tracks][:video] and hash[:tracks][:video].is_a? Array then
					isa = true
				end
			end
		end
		isa
	end
	def self.__mash_clips_having_audio mash
		clips = Array.new
		TrackTypes.each do |track_type|
			mash[:tracks][track_type.to_sym].each do |track|
				track[:clips].each do |clip|
					clips << clip if __clip_has_audio(clip)
				end
			end
		end
		clips
	end
	def self.__mash_clips_in_range mash, range, track_type
		clips_in_range = Array.new
		#puts "__mash_clips_in_range #{range.inspect} #{mash[:tracks][track_type.to_sym].length}"
				
		mash[:tracks][track_type.to_sym].each do |track|
			#puts "__mash_clips_in_range clips length #{track[:clips].length}"
			track[:clips].each do |clip|
				if range.intersection(clip[:range]) then
					clips_in_range << clip 
				else
					#puts "__mash_clips_in_range #{range.inspect} #{clip[:range].inspect}"
				end
			end
		end
		clips_in_range.sort! { |a,b| ((a[:track] == b[:track]) ? (a[:frame] <=> b[:frame]) : (a[:track] <=> b[:track]))}
		clips_in_range
	end
	def self.__mash_duration mash
		mash[:length] / mash[:quantize]
	end
	def self.__mash_has_audio? mash
		TrackTypes.each do |track_type|
			mash[:tracks][track_type.to_sym].each do |track|
				track[:clips].each do |clip|
					return true if __clip_has_audio clip
				end
			end
		end
		false
	end
	def self.__mash_has_video? mash
		TrackTypes.each do |track_type|
			next if TrackTypeAudio == track_type
			mash[:tracks][track_type.to_sym].each do |track|
				track[:clips].each do |clip|
					return true
				end
			end
		end
		false
	end
	def self.mash_search(mash, id, key = :media)
		mash[key].each do |item|
			return item if id == item[:id]
		end
		nil
	end
	def self.__mash_trim_frame clip, start, stop, fps = 44100
		result = Hash.new
		fps = fps.to_i
		orig_clip_length = clip[:length]
		speed = clip[:speed].to_f
		media_duration = (clip[:duration] * fps.to_f).floor.to_i
		media_duration = clip[:length] if (media_duration <= 0) 
		media_duration = (media_duration.to_f * speed).floor.to_i
		orig_clip_start = clip[:start]
		unless TypeVideo == clip[:type] and 0 == clip[:track] then
			start -= orig_clip_start
			stop -= orig_clip_start
			orig_clip_start = 0
		end
		orig_clip_end = orig_clip_length + orig_clip_start
		clip_start = [orig_clip_start, start].max
		clip_length = [orig_clip_end, stop].min - clip_start
		orig_clip_trimstart = clip[:trim] || 0
		clip_trimstart = orig_clip_trimstart + (clip_start - orig_clip_start)
		clip_length = [clip_length, media_duration - clip_trimstart].min if 0 < media_duration 
		result[:offset] = 0
		if 0 < clip_length then
			result[:offset] = (clip_start - orig_clip_start)
			result[:trimstart] = clip_trimstart
			result[:trimlength] = clip_length
		end
		result
	end
	def self.__mash_video_ranges mash
		quantize = mash[:quantize]
		frames = Array.new
		frames << 0
		frames << mash[:length]
		mash[:tracks][:video].each do |track|
			track[:clips].each do |clip|
				frames << clip[:range].frame
				frames << clip[:range].get_end
			end
		end
		all_ranges = Array.new
		
		frames.uniq!
		frames.sort!
		#puts "__mash_video_ranges #{frames}"
		frame = nil
		frames.length.times do |i|
			#raise "got out of sequence frames #{frames[i]} <= #{frame}" unless frames[i] > frame
			#puts "__mash_video_ranges #{i} #{frame} #{frames[i]}"
			all_ranges << FrameRange.new(frame, frames[i] - frame, quantize) if frame
			frame = frames[i]
		end
		all_ranges
	end
	def self.__output_command output, av_type
		#puts "__output_command #{av_type}"
		cmd = ''
		unless AVVideo == av_type then
			cmd += __cache_switch(output[:audio_bitrate], 'b:a', 'k')
			cmd += __cache_switch(output[:audio_frequency], 'ar')
			cmd += __cache_switch(output[:audio_codec], 'c:a')
		end
		unless AVAudio == av_type then
			cmd += __cache_switch(output[:dimensions], 's')
			cmd += __cache_switch(output[:video_format], 'f:v') if output[:video_format]
			cmd += __cache_switch(output[:video_codec], 'c:v') 
			cmd += __cache_switch(output[:video_bitrate], 'b:v', 'k')
			cmd += __cache_switch(output[:fps], 'r')
		end
		cmd
	end
	def self.__output_desires output
		case output[:type]
		when TypeAudio, TypeWaveform
			AVAudio
		when TypeImage, TypeSequence
			AVVideo
		when TypeVideo
			AVBoth
		end
	end
	def self.__output_intermediate
		output = Hash.new 
		output[:type] = TypeVideo
		output[:video_format] = PIPE_VIDEO_FORMAT
		output[:extension] = PIPE_VIDEO_EXTENSION
		output
		#final_output
	end
	def self.output_path output
		out_file = CONFIG['path_temporary']
		out_file += '/' unless out_file.end_with? '/'
		out_file += output[:identifier] + '/' if output[:identifier]	
	end
	def self.__output_path job, output, index = nil
		out_file = output_path output
		__transfer_file_name job, output, out_file, index
	end
	def self.__set_timing job
		start_audio = FLOAT_ZERO
		start_video = FLOAT_ZERO
		job[:inputs].each do |input|
			if float_cmp(input[:start], FLOAT_NEG_ONE) then
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
			start_video = input[:start] + __get_length(input) unless input[:no_video]
			start_audio = input[:start] + __get_length(input) unless input[:no_audio]
			input[:range] = __get_trim_range_simple(input)
			__init_input_ranges input
		end
		output_duration = float_max(start_video, start_audio)
		job[:duration] = output_duration
		job[:outputs].each do |output|
			output[:duration] = output_duration
		end
	end
	def self.__shell_command cmd
		#puts cmd
		stdin, stdout, stderr = Open3.capture3 cmd
		#puts "stdin #{stdin}"
		#puts "stdout #{stdout}"
		#puts "stderr #{stderr}"
		output = stdin.to_s + "\n" + stdout.to_s + "\n" + stderr.to_s
		#puts output
		output
	end
	def self.__source_from_uri uri
		source = Hash.new
		source[:type] = uri.scheme #=> "http"
		source[:host] = uri.host #=> "foo.com"
		source[:path] = uri.path #=> "/posts"
		source[:port] = uri.port
		#uri.query #=> "id=30&limit=5"
		#uri.fragment #=> "time=1305298413"
		source
	end
	def self.__source_url job, source
		url = nil
		if source then
			if source[:url] then
				url = source[:url]
			else
				url = "#{source[:type]}://"
				case source[:type]
				when SourceTypeFile
					url += __directory_path_name job, source
				when SourceTypeHttp, SourceTypeHttps
					url += source[:host] if source[:host]
					path = __directory_path_name job, source
					url += '/' unless path.start_with? '/'
					url += path
				when SourceTypeS3
					url += "#{source[:bucket]}." if source[:bucket]
					url += 's3'
					url += "-#{source[:region]}" if source[:region]
					url += '.amazonaws.com'
					path = __directory_path_name job, source
					url += '/' unless path.start_with? '/'
					url += path
				else
					url = nil
				end
			end
		end
		url
	end
	def self.__transfer_file mode, source_file, out_file
		#puts "__transfer_file #{mode}, #{source_file}, #{out_file}"
		case mode
		when SourceModeSymlink
			FileUtils.symlink source_file, out_file
		when SourceModeCopy
			FileUtils.copy source_file, out_file
		when SourceModeMove
			FileUtils.move source_file, out_file
		end
		raise "could not #{mode} #{source_file} to #{out_file}" unless File.exists? out_file
	end
	def self.__transfer_file_destination job, file, destination
		mime_type = __cache_get_info file, 'Content-Type'
		file_name = File.basename file
		source_file = __directory_path_name job, destination
		source_file += '/' unless source_file.end_with? '/'
		source_file += file_name
		case destination[:type]
		when SourceTypeFile
			FileUtils.mkdir_p(File.dirname(source_file))
			__transfer_file destination[:mode], file, source_file
		when SourceTypeHttp, SourceTypeHttps
			url = "#{destination[:type]}://#{destination[:host]}"
			path = __directory_path_name job, destination
			url += '/' unless path.start_with? '/'
			url += path
			uri = URI(url)
			uri.port = destination[:port].to_i if destination[:port]
			File.open(file) do |io|
				req = Net::HTTP::Post::Multipart.new uri.path, "key" => path, "file" => UploadIO.new(io, mime_type, file_name)
				res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
					http.request(req)
				end
			end
		when SourceTypeS3
			bucket = S3.buckets[destination[:bucket]]
			bucket.objects[source_file].write(Pathname.new(file), :content_type => mime_type)
		end
	end
	def self.__transfer_file_name job, source, url, index = nil	
		name = source[:name] || source[:basename]
		if name then
			split_name = eval_split name
			if 1 < split_name.length then
				name = ''
				is_static = true
				#puts "name is split #{split_name.inspect}"
				split_name.each do |bit|
					if is_static then
						name += bit
					else
						case bit
						when 'job_id'
							name += job[:id]
						else
							name += "{#{bit}}"
						end
					end
					is_static = ! is_static
				end
			else
				#puts "name is not split #{name} #{split_name.inspect}"
			end
			url += '/' unless url.end_with? '/'
			url += name
			url += '-' + index.to_s if index
			url += '.' + source[:extension] if source[:extension]
		end
		url
	end
	def self.__transfer_job_output job, output
		if output[:rendering] then
			destination = output[:destination] || job[:destination]
			raise "output #{output[:identifier]} has no destination" unless destination 
			file = output[:rendering]
			if destination[:archive] || output[:archive] then
				raise "TODO: __transfer_job_output needs support for archive option"
			end
			__transfer_file_destination job, file, destination
		else
			raise "output #{output[:identifier]} was not generated" if output[:required]
		end
	end
	def self.__trigger job, type
		sym = "#{type}_triggered".to_sym
		if not job[sym] then
			job[sym] = true
			puts "TODO: __trigger should send out #{type} notification"
		end
	end
end
