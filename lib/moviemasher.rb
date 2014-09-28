
module MovieMasher
	@@codecs = nil
	@@configuration = Hash.new
	@@formats = nil
	@@job = nil
	@@queue = nil
	def self.app_exec(cmd, out_file = '', duration = nil, precision = 1, app = 'ffmpeg')
		#puts "app_exec #{app}"
		outputs_file = (out_file and (not out_file.empty?) and ('/dev/null' != out_file))
		whole_cmd = configuration["path_#{app}".to_sym]
		whole_cmd += ' ' + cmd
		FileUtils.mkdir_p(File.dirname(out_file)) if outputs_file
		whole_cmd += " #{out_file}" if out_file and not out_file.empty?
		#puts whole_cmd
		if @@job
			@@job[:commands] << whole_cmd 
			__log(:debug) { whole_cmd }
		end
		result = Open3.capture3(whole_cmd).join "\n"
		if outputs_file and not out_file.include?('%') then	
			unless File.exists?(out_file) and File.size?(out_file)
				__log(:debug) { result }
				raise "failed to generate file #{cmd.gsub(';', ";\n")}" 
			end
			if duration then
				audio_duration = cache_get_info(out_file, 'audio_duration')
				video_duration = cache_get_info(out_file, 'video_duration')
				__log(:debug) { "audio_duration: #{audio_duration} video_duration: #{video_duration}" }
				unless audio_duration or video_duration
					__log(:debug) { result }
					raise "could not determine if #{duration} == duration of #{out_file}" 
				end
				unless Float.cmp(duration, video_duration.to_f, precision) or Float.cmp(duration, audio_duration.to_f, precision)
					__log(:debug) { result }
					raise "generated file with incorrect duration #{duration} != #{audio_duration} or #{video_duration} #{out_file}" 
				end
			end
		end 
		result
	end
	def self.codecs
		@@codecs = app_exec('-codecs') unless @@codecs
		@@codecs
	end
	def self.configuration
		configure
		@@configuration
	end
	def self.configure config = nil
		if @@configuration.empty?
			config = CONFIG unless config
			@@configuration = Hash.new
			if config and not config.empty? then
				# grab all keys in configuration starting with aws_, to pass to AWS
				aws_config = Hash.new
				config.each do |key_str,v|
					key_str = key_str.id2name if v.is_a? Symbol
					key_sym = key_str.to_sym
					@@configuration[key_sym] = v
					if key_str.start_with? 'aws_' then
						key_str['aws_'] = ''
						aws_config[key_str.to_sym] = v
					end
				end
				[:dir_cache, :dir_error, :dir_log, :dir_queue, :dir_temporary].each do |sym|
					if @@configuration[sym] and not @@configuration[sym].empty? then
						# expand directory and create if needed
						@@configuration[sym] = File.expand_path(@@configuration[sym])
						@@configuration[sym] += '/' unless @@configuration[sym].end_with? '/'
						FileUtils.mkdir_p(@@configuration[sym]) unless File.directory?(@@configuration[sym])
						if :dir_log == sym then
							aws_config[:logger] = Logger.new "#{@@configuration[sym]}/aws.log"
							@@log = Logger.new("#{@@configuration[sym]}/transcoder.log", 7, 1048576 * 100)
							@@log.level = ('production' == ENV['RACK_ENV'] ? Logger::DEBUG : Logger::INFO)
						end
					end
				end
				AWS.config(aws_config)
			end
		end
	end
	def self.formats
		@@formats = app_exec('-formats') unless @@formats
		@@formats
	end
	def self.output_path dont_append_slash = nil
		raise "output_path called without active job and output" unless @@job and @@output
		path = __path_job
		path += @@output[:identifier]
		path += '/' unless dont_append_slash
		path
	end
	def self.process orig_job
		#puts "MovieMasher.process"
		raise "job false or not a Hash" unless orig_job and orig_job.is_a? Hash 
		job = Marshal.load(Marshal.dump(orig_job))
		begin
			@@job = job
			hash_keys_to_symbols! @@job
			# create internal identifier for job
			@@job[:identifier] = UUID.new.generate
			# create directory for job (uses identifier)
			path_job = __path_job
			FileUtils.mkdir_p path_job
			# copy orig_job to job directory
			File.open(path_job + 'job_orig.json', 'w') { |f| f.write(orig_job.to_json) }
			# create log for job and set log level
			@@job[:logger] = Logger.new(path_job + 'log.txt')
			log_level = @@job[:log_level]
			log_level = configuration[:log_level] unless log_level and not log_level.empty?
			log_level = 'info' unless log_level and not log_level.empty?
			log_level = log_level.upcase
			#puts "log_level #{log_level} #{Logger.const_defined?(log_level)}"
			log_level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
			@@job[:logger].level = log_level
			__init_job
			# copy job to job directory
			File.open(path_job + 'job.json', 'w') { |f| f.write(@@job.to_json) }
			
			unless @@job[:error]
				__log(:debug) { "job parsed and initialized" }
				input_ranges = Array.new
				copy_files = Hash.new # key is value of input[:copy] (basename for copied input)
				video_outputs = 0
				audio_outputs = 0
				# start to figure steps needed for progress
				@@job[:callbacks].each do |callback|
					@@job[:progress][:triggering] += 1 unless 'progress' == callback[:trigger]
				end
				@@job[:outputs].each do |output|
					video_outputs += 1 unless Type::Audio == output[:desires]
					audio_outputs += 1 unless Type::Video == output[:desires]
					@@job[:progress][:rendering] += 1
					@@job[:progress][:uploading] += 1
				end
				outputs_desire = (0 < video_outputs ? (0 < audio_outputs ? Type::Both : Type::Video) : Type::Audio)
				downloading_urls = Array.new
				@@job[:inputs].each do |input|
					input_urls = Array.new
					base_source = (input[:base_source] || @@job[:base_source])
					input_url = __input_url input, base_source
					if input_url then
						input[:input_url] = input_url
						input_urls << input_url
					elsif Type::Mash == input[:type] then
						input_urls = __input_urls input[:source], outputs_desire, base_source
						input[:input_urls] = input_urls
					end
					input_urls.each do |input_url|
						@@job[:progress][:downloading] += 1		
						unless downloading_urls.include? input_url then
							downloading_urls << input_url
						end
					end
				end
				#TODO: add outputs to progress
				__trigger :initiate
				
				@@job[:inputs].each do |input|
					break if @@job[:error]
					input_url = input[:input_url]
					if input_url then
						# if it's a mash we don't yet know whether it has desired content types
						if (Type::Mash == input[:type]) or __has_desired?(__input_has(input), outputs_desire) then
							base_source = (input[:base_source] || @@job[:base_source])
							@@job[:cached][input_url] = __cache_input input, base_source, input_url
							@@job[:progress][:downloaded] += 1	
							__trigger :progress
							# TODO: handle copy flag in input
							copy_files[input[:copy]] = @@job[:cached][input_url] if input[:copy]
						end
						if (Type::Mash == input[:type]) then
							input[:source] = JSON.parse(File.read(@@job[:cached][input_url])) 
							__init_input_mash input
							input_urls = __input_urls input[:source], outputs_desire, base_source
							input[:input_urls] = input_urls
							input_urls.each do |input_url|
								@@job[:progress][:downloading] += 1		
								unless downloading_urls.include? input_url then
									downloading_urls << input_url
								end
							end
						end
					end
					if (Type::Mash == input[:type]) and __has_desired?(__input_has(input), outputs_desire) then
						__cache_job_mash input, outputs_desire
					end
				end
				# everything that needs to be cached is now cached
				__set_timing
				if 0 < video_outputs then
					# make sure visual outputs have dimensions, using input's for default
					input_dimensions = __input_dimensions
					@@job[:outputs].each do |output|
						next if Type::Audio == output[:desires]
						next if output[:dimensions]
						output[:dimensions] = input_dimensions 
					end
				end
				video_graphs = ((0 == video_outputs) ? Array.new : __filter_graphs_video(@@job[:inputs]))
				audio_graphs = ((0 == audio_outputs) ? Array.new : __filter_graphs_audio(@@job[:inputs]))
				@@job[:progress][:rendering] += @@job[:outputs].length * (video_graphs.length + audio_graphs.length)		
				@@job[:outputs].each do |output|
					@@output = output
					__build_output video_graphs, audio_graphs
					@@job[:progress][:rendered] += 1 + (video_graphs.length + audio_graphs.length)
					@@job[:progress][:uploading] += ((output[:fps].to_f * output[:duration]).floor - 1) if Type::Sequence == output[:type]
					__trigger :progress
				end
				@@job[:outputs].each do |output|
					@@output = output
					__transfer_job_output
				end
			end
		rescue Exception => e
			__log(:debug) { e.backtrace.join "\n" }
			__log(:error) { e.message }
			__trigger :error
		end
		begin
			__trigger :complete
		rescue Exception => e
			__log(:debug) { e.backtrace.join "\n" }
			__log(:error) { e.message }
		ensure
			if @@job[:error] and configuration[:dir_error] and not configuration[:dir_error].empty? then
				FileUtils.mv path_job, configuration[:dir_error] + File.basename(path_job)
			else
				FileUtils.rm_r path_job unless configuration[:keep_temporary_files]
			end
			@@output = nil
			@@job = nil
		end
		flush_cache_files configuration[:dir_cache], configuration[:cache_gigs]
		job
	end
	def self.process_queues rake_args
		run_seconds = configuration[:process_queues_seconds]
		start = Time.now
		oldest_file = nil
		working_file = "#{configuration[:dir_queue]}/working.json"
		while run_seconds > (Time.now - start)
			if File.exists? working_file
				# if this process didn't create it, we must have crashed on it in a previous run
				puts "#{Time.now} MovieMasher.process_queues found active job:\n#{File.read working_file}" unless oldest_file
				File.delete working_file
			end
			#puts "looking for job in #{configuration[:dir_queue]}"
			oldest_file = Dir["#{configuration[:dir_queue]}/*.json"].sort_by{ |f| File.mtime(f) }.first
			if oldest_file then
				puts "started #{oldest_file}"
				File.rename oldest_file, working_file
				json_str = File.read working_file
				job = nil
				begin
					job = JSON.parse json_str
					unless job and job.is_a? Hash 
						puts "parsed job was false or not a Hash: #{oldest_file} #{json_str}" 
						job = nil
					end
				rescue JSON::ParserError
					puts "job could not be parsed as json: #{oldest_file} #{json_str}" 
				end
				process job if job
				puts "finished #{oldest_file}"
				File.delete working_file
				sleep 1
			else # see if there's one in the queue
				__sqs_request(run_seconds, start) if configuration[:queue_url]
			end
		end
	end
	def self.__assure_sequence_complete
		dir_path = @@output[:rendering]
		if File.directory? dir_path then
			
			first_frame = @@output[:begin]
			frame_count = (@@output[:increment].to_f * @@output[:fps].to_f * @@output[:duration]).floor.to_i
			padding = (first_frame + frame_count).to_s.length
			last_file = nil
			frame_count.times do |frame|
				file_frame = frame + first_frame
				file_path = "#{dir_path}/#{file_frame.to_s.rjust padding, '0'}.#{@@output[:extension]}"
				if File.exists? file_path then
					last_file = file_path
				else
					if last_file then
						puts "MovieMasher.__assure_sequence_complete creating #{file_path}"
						File.symlink last_file, file_path
					else
						raise "NO sequence files found"
						break
					end
				end
			end
		else
			puts "NOT DIR: #{dir_path}"
		end
	end
	def self.__audio_from_file path
		raise "__audio_from_file with invalid path" unless path and (not path.empty?) and File.exists? path
		out_file = "#{File.dirname path}/#{File.basename path}-intermediate.#{Intermediate::AudioExtension}"
		unless File.exists? out_file then
			cmds = Array.new
			cmds << shell_switch(path, 'i')
			cmds << shell_switch(2, 'ac')
			cmds << shell_switch(44100, 'ar')
			app_exec cmds.join(' '), out_file
		end
		out_file
	end
	def self.__build_output video_graphs, audio_graphs
		unless @@output[:rendering] then
			avb = __output_desires @@output
			cmds = Array.new
			video_duration = Float::Zero
			audio_duration = Float::Zero
			out_path = __render_path
			@@output[:rendering] = ( Type::Sequence == @@output[:type] ? File.dirname(out_path) : out_path)
			unless Type::Audio == avb then # we've got video
				if 0 < video_graphs.length then
					if 1 == video_graphs.length then
						graph = video_graphs[0]
						video_duration = graph.duration
						cmd = graph.command @@output
						raise "Could not build complex filter" if cmd.empty?
					else 
						cmd = __filter_graphs_concat @@output, video_graphs
						raise "Could not build complex filter" if cmd.empty?
						video_graphs.each do |graph|
							video_duration += graph.duration
						end
					end
					cmds << shell_switch("'#{cmd}'", 'filter_complex')
				else avb = Type::Audio
				end
			end
			unless Type::Video == avb then # we've got audio
				audio_graphs_count = audio_graphs.length
				if 0 < audio_graphs_count then
					data = audio_graphs[0]
					if 1 == audio_graphs_count and 1 == data[:loop] and (not Mash.gain_changes(data[:gain])) and Float.cmp(data[:start_seconds], Float::Zero) then
						# just one non-looping graph, starting at zero with no gain change
						raise "zero length #{data.inspect}" unless Float.gtr(data[:length_seconds], Float::Zero)
						audio_duration = data[:length_seconds]
						data[:waved_file] = __audio_from_file(data[:cached_file]) unless data[:waved_file]
					else 
						# merge audio and feed resulting file to ffmpeg
						audio_cmd = ''
						counter = 1
						start_counter = Float::Zero
						audio_graphs_count.times do |audio_graphs_index|
							data = audio_graphs[audio_graphs_index]
							loops = data[:loop] || 1
							volume = data[:gain]
							start = data[:start_seconds]
							raise "negative start time" unless Float.gtre(start, Float::Zero)
							raise "zero length #{data.inspect}" unless Float.gtr(data[:length_seconds], Float::Zero)
							data[:waved_file] = __audio_from_file(data[:cached_file]) unless data[:waved_file]
							audio_cmd += " -a:#{counter} -i "
							counter += 1
							audio_cmd += 'audioloop,' if 1 < loops
							audio_cmd += "playat,#{data[:start_seconds]},"
							audio_cmd += "select,#{data[:trim_seconds]},#{data[:length_seconds]}"
							audio_cmd += ",#{data[:waved_file]}"
							audio_cmd += " -t:{Float.string data[:length_seconds]}" if 1 < loops
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
									pos = (data[:length_seconds] * loops.to_f * pos) if (Float.gtr(pos, Float::Zero)) 									
									audio_cmd += ",#{Float.precision(start + pos)},#{val}"
								end
							end
							#puts "audio_duration #{data[:start_seconds]} + #{data[:length_seconds]}"
							audio_duration = Float.max(audio_duration, data[:start_seconds] + data[:length_seconds])
						end
						audio_cmd += ' -a:all -z:mixmode,sum'
						audio_cmd += ' -o'
						audio_path = "#{output_path}audio-#{Digest::SHA2.new(256).hexdigest(audio_cmd)}.#{Intermediate::AudioExtension}"
						unless File.exists? audio_path then
							app_exec(audio_cmd, audio_path, audio_duration, 5, 'ecasound')
						end
						data = Hash.new
						data[:type] = Type::Audio
						data[:trim_seconds] = Float::Zero
						data[:length_seconds] = audio_duration
						data[:waved_file] = audio_path
					end
					# data is now just one wav file - audio_duration may be less or more than video_duration
					if Type::Waveform == @@output[:type] then
						dimensions = @@output[:dimensions].split 'x'
						cmds << shell_switch(data[:waved_file], '--input')
						cmds << shell_switch(dimensions.first, '--width')
						cmds << shell_switch(dimensions.last, '--height')
						cmds << shell_switch(@@output[:forecolor], '--linecolor')
						cmds << shell_switch(@@output[:backcolor], '--backgroundcolor')
						cmds << shell_switch('0', '--padding')
						cmds << shell_switch('', '--output')
						app_exec cmds.join, out_path, nil, nil, 'wav2png'
						cmds = Array.new
					else
						cmds << shell_switch(data[:waved_file], 'i')
						unless Float.cmp(data[:trim_seconds], Float::Zero) and Float.cmp(data[:length_seconds], data[:duration_seconds]) then
							cmds << shell_switch("'atrim=start=#{data[:trim_seconds]}:duration=#{audio_duration},asetpts=expr=T-STARTT'", 'af') 
						end
				
					end
				else
					avb = Type::Video
				end
			end
			unless cmds.empty? then # we've got audio and/or video
				type_is_video_or_audio = ( (Type::Video == @@output[:type]) or (Type::Audio == @@output[:type]) )
				duration = Float.max(audio_duration, video_duration)
				cmds << shell_switch(Float.string(duration), 't') if type_is_video_or_audio
				cmd = cmds.join
				cmd += __output_command @@output, avb, duration
				cmd = '-y ' + cmd
				duration = nil if Type::Image == @@output[:type] or Type::Sequence == @@output[:type]
				raise "duration does not match length #{duration} != #{@@job[:duration]}" if duration and not Float.cmp(duration, @@job[:duration])
				#puts "DURATIONS\nduration:\n#{duration}\nvideo: #{video_duration}\naudio: #{audio_duration}\noutput: #{@@output[:duration]}\njob: #{@@job[:duration]}"
				do_single_pass = (not type_is_video_or_audio)
				unless do_single_pass then
					pass_log_file = "#{File.dirname @@output[:rendering]}/#{@@output[:identifier]}"
					cmd_pass_1 = "#{cmd} -pass 1 -passlogfile #{pass_log_file} -f #{@@output[:extension]}"
					cmd_pass_2 = "#{cmd} -pass 2 -passlogfile #{pass_log_file}"
					begin
						app_exec cmd_pass_1, '/dev/null'
						app_exec cmd_pass_2, out_path, duration, @@output[:precision]
					rescue Exception => e
						__log(:debug) { e.message }
						__log(:warn) { "unable to encode in two passes, retrying in one" }
						do_single_pass = true
					end
				end
				if do_single_pass then
					app_exec cmd, out_path, duration, @@output[:precision]
					__assure_sequence_complete if Type::Sequence == @@output[:type]
				end
			end
		end
	end
	def self.__cache_input input, base_source = nil, input_url = nil
		#puts "__cache_input #{input}, #{base_source}, #{input_url} "
		input_url = __input_url(input, base_source) unless input_url
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
				__cache_source source, cache_url_path
				raise "could not cache #{input_url}" unless File.exists? cache_url_path
			end
			#puts "cached_file #{cache_url_path} #{input}"
			input[:cached_file] = cache_url_path
			case input[:type]
			when Type::Video
				input[:duration] = cache_get_info(cache_url_path, 'duration').to_f unless input[:duration] and Float.gtr(input[:duration], Float::Zero)
				input[:no_audio] = ! cache_get_info(cache_url_path, Type::Audio)
				input[:dimensions] = cache_get_info(cache_url_path, 'dimensions')
				input[:no_video] = ! input[:dimensions]
			when Type::Audio
				input[:duration] = cache_get_info(cache_url_path, 'audio_duration').to_f unless input[:duration] and Float.gtr(input[:duration], Float::Zero)
				#TODO: should we be converting to wav to get accurate duration??
				input[:duration] = cache_get_info(cache_url_path, 'video_duration').to_f unless Float.gtr(input[:duration], Float::Zero)
			when Type::Image 
				input[:dimensions] = cache_get_info(cache_url_path, 'dimensions')
				#puts "INPUT DIMENSIONS #{input[:dimensions]} for #{input_url}"
				raise "could not determine image dimensions" unless input[:dimensions]
			end
		else
			raise "could not produce an input_url #{input}"
		end
		cache_url_path
	end
	def self.__cache_job_mash input, outputs_desire
		mash = input[:source]
		base_source = (input[:base_source] || @@job[:base_source])
		mash[:media].each do |media|
			#puts "__cache_job_mash media #{media[:type]} #{media}"
			case media[:type]
			when Type::Video, Type::Audio, Type::Image, Type::Font
				if __has_desired?(__input_has(media), outputs_desire) then
					input_url = __input_url media, base_source
					if input_url then
						@@job[:cached][input_url] = __cache_input media, base_source, input_url
						@@job[:progress][:downloaded] += 1
						__trigger :progress
					end
				end
			end
		end
	end
	def self.__cache_source source, out_file
		FileUtils.mkdir_p(File.dirname(out_file))
		case source[:type]
		when Type::File
			source_path = __directory_path_name_source source
			__transfer_file(source[:method], source_path, out_file) if File.exists? source_path
		when Type::Http, Type::Https
			url = "#{source[:type]}://#{source[:host]}"
			path = __directory_path_name_source source
			url += '/' unless path.start_with? '/'
			url += path
			uri = URI url
			uri.port = source[:port] if source[:port]
			#params = { :limit => 10, :page => 3 }
			#uri.query = URI.encode_www_form(params)
			Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
				request = Net::HTTP::Get.new uri
				http.request request do |response|
					if '200' == response.code then
						File.open(out_file, 'wb') do |io|
							response.read_body do |chunk|
								io.write chunk
							end
						end
					else
						puts "got #{response.code} response code"
					end
				end
			end
		when Type::S3
			bucket = __s3_bucket source
			bucket_key = __directory_path_name_source source
    		object = bucket.objects[bucket_key]
    		if configuration[:s3_read_at_once] then
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
		out_file
	end
	def self.__cache_url_path url
		configuration[:dir_cache] + __hash(url) + '/cached' + File.extname(url)
	end
	def self.__directory_path_name_source source
		key = source[:key]
		unless key
			key = __transfer_directory source
			file_name = __transfer_file_name source
			unless file_name.empty?
				key += '/' unless key.end_with? '/'
				key += file_name
			end
		end
		key
	end
	def self.__directory_path_name_destination destination
		key = destination[:key]
		unless key 
			file_name = __transfer_file_name destination
			file_name = __transfer_file_name(@@output) if file_name.empty? 
			key = __transfer_directory destination
			unless file_name.empty?
				key += '/' unless key.end_with? '/'
				key += file_name
			end
		end
		eval_value key, __eval_scope
	end
	def self.__eval_scope
		scope = Hash.new
		scope[:job] = @@job
		scope[:output] = @@output
		scope[:log] = Proc.new { File.read(__path_job + 'log.txt') }
		scope
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
		esc = '~'
		# expand variables
		value_str = value_str.dup
		value_str.gsub!(Regexes::Variables) do |match|
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
			value_str.gsub!(Regexp.new("([a-z_]+)[(]#{deepest}[#{esc}]([^)]+)[)]#{deepest}[#{esc}]")) do |m|
				#puts "level #{level} #{m}"
				method = $1
				param_str = $2
				params = param_str.split(',')
				params.each do |param|
					param.strip!
					param.gsub!(Regexp.new("([()])[0-9]+[#{esc}]")) {$1}
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
	 	value_str.gsub!(Regexp.new("([()])[0-9]+[#{esc}]")) { $1 }
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
	def self.__filter_graphs_audio inputs
		graphs = Array.new
		start_counter = Float::Zero	
		inputs.each do |input|
			next if input[:no_audio]
			#puts "INPUT: #{input}\n"
			case input[:type]
			when Type::Video, Type::Audio
				data = Hash.new
				data[:type] = input[:type]
				data[:trim_seconds] = __get_trim input
				data[:length_seconds] = __get_length input
				data[:start_seconds] = input[:start]	
				data[:cached_file] = input[:cached_file]
				data[:duration_seconds] = input[:duration]
				data[:gain] = input[:gain]
				data[:loop] = input[:loop]
				graphs << data
			when Type::Mash
				quantize = input[:source][:quantize]
				audio_clips = Mash.clips_having_audio input[:source]
				audio_clips.each do |clip|
					unless clip[:cached_file] then
						media = Mash.search input[:source], clip[:id]
						raise "could not find media for clip #{clip[:id]}" unless media
						clip[:cached_file] = media[:cached_file] || raise("could not find cached file")
						clip[:duration] = media[:duration]
					end
					data = Hash.new
					data[:type] = clip[:type]
					data[:trim_seconds] = clip[:trim_seconds]
					data[:length_seconds] = clip[:length_seconds]
					#puts "start_seconds = #{input[:start]} + #{quantize} * #{clip[:frame]}"
					data[:start_seconds] = input[:start].to_f + clip[:frame].to_f / quantize.to_f
					data[:cached_file] = clip[:cached_file]
					data[:gain] = clip[:gain]
					data[:duration_seconds] = clip[:duration]
					data[:loop] = clip[:loop]
					graphs << data
				end
			end
		end
		graphs
	end
	def self.__filter_graphs_concat output, graphs
		cmds = Array.new
		intermediate_output = __output_intermediate
		intermediate_output[:fps] = output[:fps]
		intermediate_output[:dimensions] = output[:dimensions]
		graphs.length.times do |index|
			graph = graphs[index]
			duration = graph.duration
			cmd = graph.command output
			raise "Could not build complex filter" if cmd.empty?
			# yuv444p, yuv422p, yuv420p, yuv411p
			cmd += ",format=pix_fmts=yuv420p"
			#,fps=fps=#{output[:fps]}
			cmd = " -filter_complex '#{cmd}' -t #{duration}"
			cmd += __output_command intermediate_output, Type::Video
			out_file = "#{output_path}concat-#{cmds.length}.#{intermediate_output[:extension]}"
			cmd = '-y' + cmd
			app_exec cmd, out_file			
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
			when Type::Mash
				mash = input[:source]
				all_ranges = Mash.video_ranges mash
				all_ranges.each do |range|
					#puts "mash Graph.new #{range.inspect}"
					graph = Graph.new input, range, mash[:backcolor]
					clips = Mash.clips_in_range mash, range, Type::TrackVideo
					if 0 < clips.length then
						transition_layer = nil
						transitioning_clips = Array.new
						clips.each do |clip|
							case clip[:type]
							when Type::Video, Type::Image
								# media properties were copied to clip BEFORE file was cached, so repeat now
								media = Mash.search mash, clip[:id]
								raise "could not find media for clip #{clip[:id]}" unless media
								clip[:cached_file] = media[:cached_file] || raise("could not find cached file #{media}")
								clip[:dimensions] = media[:dimensions] || raise("could not find dimensions #{clip} #{media}")
							end	
							if Type::Transition == clip[:type] then
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
							when Type::Video, Type::Image, Type::Theme
								#puts "graph.create_layer clip"
								graph.create_layer clip
							end
						end
					end
					graphs << graph
				end
			when Type::Video, Type::Image
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
		filter_config[:type] = Type::Merger
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
		filter_config[:type] = Type::Scaler
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
		range(input[:fps]) if Type::Video == input[:type]
		range
	end	
	def self.__get_time output, key
		length = Float::Zero
		duration = output[:duration].to_f
		if Float.gtr(output[key], Float::Zero) then
			sym = "#{key.id2name}_is_relative".to_sym
			if output[sym] then
				if Float.gtr(duration, Float::Zero) then
					if '%' == output[sym] then
						length = (output[key] * duration) / Float::Hundred
					else 
						length = duration - output[key]
					end
				end
			else 
				length = output[key]
			end
		elsif :length == key and Float.gtr(duration, Float::Zero) then
			output[key] = duration - __get_trim(output)
			length = output[key]
		end
		length = Float.precision length
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
		(Type::Both == desired) or (Type::Both == has) or (desired == has) 
	end
  	def self.__init_callback callback
  		case callback[:trigger]
  		when 'progress'
  			__init_key callback, :progress_seconds, 10	
  		end
  		callback
  	end
	def self.__init_clip input, mash, track_index, track_type
		__init_clip_media input, mash
		input[:frame] = (input[:frame] ? input[:frame].to_f : Float::Zero)
		# TODO: allow for no start or length in video clips
		# necessitating caching of media if its duration unknown
		raise "mash clips must have length" unless input[:length] and 0 < input[:length]
		input[:range] = FrameRange.new input[:frame], input[:length], mash[:quantize]
		input[:length_seconds] = input[:range].length_seconds unless input[:length_seconds]
		input[:track] = track_index if track_index 
		case input[:type]
		when Type::Frame
			input[:still] = 0 unless input[:still]
			input[:fps] = mash[:quantize] unless input[:fps]
			if 2 > input[:still] + input[:fps] then
				input[:quantized_frame] = 0
			else 
				input[:quantized_frame] = mash[:quantize] * (input[:still].to_f / input[:fps].to_f).round
			end
		when Type::Transition
			input[:to] = Hash.new unless input[:to]
			input[:from] = Hash.new unless input[:from]
			input[:to][:merger] = __filter_merger_default unless input[:to][:merger]
			input[:to][:scaler] = __filter_scaler_default unless input[:to][:scaler] or input[:to][:fill]
			input[:from][:merger] = __filter_merger_default unless input[:from][:merger]
			input[:from][:scaler] = __filter_scaler_default unless input[:from][:scaler] or input[:from][:fill]
		when Type::Video, Type::Audio
			input[:trim] = 0 unless input[:trim]
			input[:trim_seconds] = input[:trim].to_f / mash[:quantize] unless input[:trim_seconds]
		end
		__init_raw_input input
		# this is done for real inputs during __set_timing
		__init_input_ranges input
		input
  	end
	def self.__init_clip_media clip, mash
		if clip[:id] then
			media = Mash.search mash, clip[:id]
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
  	def self.__init_destination destination
  		__init_key destination, :identifier, UUID.new.generate	
  		__init_key(destination, :acl, 'public-read') if Type::S3 == destination[:type]
  		
  	end
	def self.__init_input input
		__init_time input, :trim
		__init_key input, :start, Float::NegOne
		__init_key input, :track, 0
		__init_key input, :duration, Float::Zero
		__init_key(input, :length, 1) if Type::Image == input[:type]
		__init_time input, :length # ^ image will already be one by default
		__init_raw_input input
		# this is done for real inputs during __set_timing
		__init_input_ranges input
		input
	end
 	def self.__init_input_mash input
		if Mash.hash? input[:source] then
			__init_mash input[:source]
			input[:duration] = Mash.duration(input[:source]) if Float.cmp(input[:duration], Float::Zero)
			input[:no_audio] = ! Mash.has_audio?(input[:source])
			input[:no_video] = ! Mash.has_video?(input[:source])
		end
	end
 	def self.__init_input_ranges input
		input[:effects].each do |effect|
			effect[:range] = input[:range]
		end
		input[:merger][:range] = input[:range] if input[:merger] 	
		input[:scaler][:range] = input[:range] if input[:scaler]
  	end
	def self.__init_job
		if @@job[:inputs] and @@job[:inputs].is_a?(Array) and not @@job[:inputs].empty? then
			if @@job[:outputs] and @@job[:outputs].is_a?(Array) and not @@job[:outputs].empty? then
				@@job[:id] = UUID.new.generate unless @@job[:id]
				@@job[:callbacks] = Array.new unless @@job[:callbacks]
				@@job[:cached] = Hash.new
				@@job[:calledback] = Hash.new
				@@job[:progress] = Hash.new() { 0 }
				
				@@job[:commands] = Array.new
				
				@@job[:inputs].each do |input| 
					__init_input input
				end
				@@job[:callbacks].each do |callback|
					__init_callback callback
				end
				found_destination = !! @@job[:destination]
				__init_destination @@job[:destination] if found_destination
				@@job[:outputs].each do |output| 
					__init_output output
					destination = output[:destination]
					if destination then
						__init_destination destination
						found_destination = true
					end
				end
				__log(:error) { 'job destination invalid' } unless found_destination
			else
				__log(:error) { 'job outputs invalid' }
			end
		else
			__log(:error) { 'job inputs invalid' }
		end
		
	end
	def self.__init_key output, key, default
		output[key] = default if ((not output[key]) or output[key].to_s.empty?)
#		if default.is_a?(Float) then
#			output[key] = output[key].to_f if 
#		else
#			output[key] = output[key].to_i if default.is_a?(Integer) 
#		end
	end
	def self.__init_mash mash
		mash[:quantize] = (mash[:quantize] ? mash[:quantize].to_f : Float::One)
		mash[:media] = Array.new unless mash[:media] and mash[:media].is_a? Array
		mash[:tracks] = Hash.new unless mash[:tracks] and mash[:tracks].is_a? Hash
		longest = Float::Zero
		Type::Tracks.each do |track_type|
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
					longest = Float.max(longest, clip[:range].get_end)
				end
				track_index += 1
			end
		end
		mash[:length] = longest
	end
	def self.__init_output output
		__init_key output, :type, Type::Video
		output[:desires] = __output_desires output
		output[:filter_graphs] = Hash.new
		output[:filter_graphs][:video] = Array.new unless Type::Audio == output[:desires]
		output[:filter_graphs][:audio] = Array.new unless Type::Video == output[:desires]
		output[:identifier] = UUID.new.generate
		__init_key output, :name, ((Type::Sequence == output[:type]) ? '{output.sequence}' : output[:type])
		case output[:type]
		when Type::Video
			__init_key output, :backcolor, 'black'
			__init_key output, :fps, 30
			__init_key output, :precision, 1
			__init_key output, :extension, 'flv'
			__init_key output, :video_codec, 'flv'
			__init_key output, :audio_bitrate, 224
			__init_key output, :audio_codec, 'libmp3lame'
			__init_key output, :dimensions, '512x288'
			__init_key output, :fill, Mash::FillNone
			__init_key output, :gain, Mash::VolumeNone
			__init_key output, :audio_frequency, 44100
			__init_key output, :video_bitrate, 4000
		when Type::Sequence
			__init_key output, :backcolor, 'black'
			__init_key output, :fps, 10
			__init_key output, :begin, 1
			__init_key output, :increment, 1
			__init_key output, :extension, 'jpg'
			__init_key output, :dimensions, '256x144'
			__init_key output, :quality, 1
			output[:no_audio] = true
		when Type::Image
			__init_key output, :backcolor, 'black'
			__init_key output, :quality, 1						
			__init_key output, :fps, 1							
			__init_key output, :extension, 'jpg'
			__init_key output, :dimensions, '256x144'
			output[:no_audio] = true
		when Type::Audio
			__init_key output, :audio_bitrate, 224
			__init_key output, :precision, 0
			__init_key output, :audio_codec, 'libmp3lame'
			__init_key output, :extension, 'mp3'
			__init_key output, :audio_frequency, 44100
			__init_key output, :gain, Mash::VolumeNone
			output[:no_video] = true
		when Type::Waveform
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
		is_av = [Type::Video, Type::Audio].include? input_type
		is_v = [Type::Video, Type::Image, Type::Frame].include? input_type
		
		# set volume with default of none (no adjustment)
		__init_key(input, :gain, Mash::VolumeNone) if is_av
		__init_key(input, :fill, Mash::FillStretch) if is_v
		
		# set source from url unless defined
		case input_type
		when Type::Video, Type::Image, Type::Frame, Type::Audio
			input[:source] = input[:url] unless input[:source]
			if input[:source].is_a? Hash then
				__init_key(input[:source], :type, 'http')
			end
		end		
		
		# set no_* when we know for sure
		case input_type
		when Type::Mash
			__init_input_mash input
		when Type::Video
			input[:speed] = (input[:speed] ? Float::One : input[:speed].to_f) 
			input[:no_audio] = ! Float.cmp(Float::One, input[:speed])
			input[:no_video] = false
		when Type::Audio
			__init_key input, :loop, 1
			input[:no_video] = true
		when Type::Image
			input[:no_video] = false
			input[:no_audio] = true
		else
			input[:no_audio] = true
		end		
		input[:no_audio] = ! Mash.clip_has_audio(input) if is_av and not input[:no_audio]
		input
	end
	def self.__init_time input, key
		if input[key] then
			if input[key].is_a? String then
				input["#{key.id2name}_is_relative".to_sym] = '%'
				input[key]['%'] = ''
			end
			input[key] = input[key].to_f
			if Float.gtr(Float::Zero, input[key]) then
				input["#{key.id2name}_is_relative".to_sym] = '-'
				input[key] = Float::Zero - input[key]
			end
		else 
			input[key] = Float::Zero
		end
	end
	def self.__input_dimensions
		dimensions = nil
		found_mash = false
		@@job[:inputs].each do |input|
			case input[:type]
			when Type::Mash
				found_mash = true
			when Type::Image, Type::Video
				dimensions = input[:dimensions]
			end
			break if dimensions
		end
		dimensions = -1 if ((! dimensions) && found_mash) 
		dimensions
	end
	def self.__input_has input
		case input[:type]
		when Type::Audio
			Type::Audio
		when Type::Image, Type::Font, Type::Frame
			Type::Video
		when Type::Video, Type::Mash
			(input[:no_audio] ? Type::Video : input[:no_video] ? Type::Audio : Type::Both)
		end
	end
	def self.__input_urls mash, outputs_desire, base_source
		input_urls = Array.new
		mash[:media].each do |media|
			if __has_desired?(__input_has(media), outputs_desire) then
				input_url = __input_url(media, base_source) 
				next unless input_url
				input_urls << input_url unless input_urls.include? input_url
			end
		end
		input_urls
	end
	def self.__input_url input, base_source = nil
		url = nil
		if input[:source] then
			if input[:source].is_a? String then
				url = input[:source]
				if not url.include? '://' then
					# relative url
					base_url = __source_url base_source
					if base_url then
						base_url += '/' unless base_url.end_with? '/'
						url = URI.join(base_url, url).to_s
					end
				end
			elsif input[:source].is_a? Hash then
				url = __source_url input[:source]
			end
		end
		url
	end
	def self.__log type, &proc
		raise "__log called with no active job" unless @@job
		if :error == type then
			@@job[:error] = proc.call
		end
		@@job[:logger].send(type, proc.call) if @@job[:logger].send((type.id2name + '?').to_sym) 
	end
	def self.__log_transcoder type, &proc
		if @@log and @@log.send((type.id2name + '?').to_sym) then
			@@log.send(type, proc.call)
		end
	end
	def self.__output_command output, av_type, duration = nil
		cmds = Array.new
		unless Type::Video == av_type then # we have audio output
			cmds << shell_switch(output[:audio_bitrate], 'b:a', 'k') if output[:audio_bitrate]
			cmds << shell_switch(output[:audio_frequency], 'ar') if output[:audio_frequency]
			cmds << shell_switch(output[:audio_codec], 'c:a') if output[:audio_codec]
		end
		unless Type::Audio == av_type then # we have visual output
			case output[:type]
			when Type::Video
				cmds << shell_switch(output[:dimensions], 's') if output[:dimensions]
				cmds << shell_switch(output[:video_format], 'f:v') if output[:video_format]
				cmds << shell_switch(output[:video_codec], 'c:v') if output[:video_codec]
				cmds << shell_switch(output[:video_bitrate], 'b:v', 'k') if output[:video_bitrate]
				cmds << shell_switch(output[:fps], 'r') if output[:fps]
			when Type::Image
				cmds << shell_switch(output[:quality], 'quality') if output[:quality]
			when Type::Sequence
				cmds << shell_switch(output[:quality], 'quality') if output[:quality]
				cmds << shell_switch(output[:fps], 'r') if output[:fps]
			end
		end
		cmds.join
	end
	def self.__output_desires output
		case output[:type]
		when Type::Audio, Type::Waveform
			Type::Audio
		when Type::Image, Type::Sequence
			Type::Video
		when Type::Video
			Type::Both
		end
	end
	def self.__output_intermediate
		output = Hash.new 
		output[:type] = Type::Video
		output[:video_format] = Intermediate::VideoFormat
		output[:extension] = Intermediate::VideoExtension
		#output[:video_codec] = 'libx264 -preset ultrafast -level 41'
		#output[:extension] = 'mp4'
		output[:video_bitrate] = '-vb 200M'
		output
		#final_output
	end
	def self.__path_job
		raise "__path_job called with no active job" unless @@job
		path = configuration[:dir_temporary]
		path += @@job[:identifier] + '/'
		path
	end
	def self.__render_path
		raise "__render_path called without active job and output" unless @@job and @@output
		out_file = output_path true
		out_file += '/' + @@output[:sequence] if Type::Sequence == @@output[:type]
		out_file += '.' + @@output[:extension]
		out_file
	end
	def self.__set_timing
		start_audio = Float::Zero
		start_video = Float::Zero
		@@job[:inputs].each do |input|
			if Float.cmp(input[:start], Float::NegOne) then
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
		output_duration = Float.max(start_video, start_audio)
		@@job[:duration] = output_duration
		@@job[:outputs].each do |output|
			output[:duration] = output_duration
			if Type::Sequence == output[:type] then
				padding = (output[:begin] + (output[:increment].to_f * output[:fps].to_f * output_duration).floor.to_i).to_s.length
				output[:sequence] = "%0#{padding}d"
			end
		end
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
	def self.__source_url input_source
		url = nil
		if input_source then
			if input_source[:url] then
				url = input_source[:url]
			else
				url = "#{input_source[:type]}://"
				case input_source[:type]
				when Type::File
					url += __directory_path_name_source input_source
				when Type::Http, Type::Https
					url += input_source[:host] if input_source[:host]
					path = __directory_path_name_source input_source
					url += '/' unless path.start_with? '/'
					url += path
				when Type::S3
					url += "#{input_source[:bucket]}." if input_source[:bucket] and not input_source[:bucket].empty?
					url += 's3'
					url += "-#{input_source[:region]}" if input_source[:region] and not input_source[:region].empty?
					url += '.amazonaws.com'
					path = __directory_path_name_source input_source
					url += '/' unless path.start_with? '/'
					url += path
				else
					url = nil
				end
			end
		end
		url
	end
	def self.__sqs
		((configuration[:queue_region] and not configuration[:queue_region].empty?) ? AWS::SQS.new(:region => configuration[:queue_region]) : AWS::SQS.new)
	end
	def self.__sqs_request run_seconds, start
		unless @@queue then
			sqs = __sqs
			# queue will be nil if their URL is not defined in config.yml
			@@queue = sqs.queues[configuration[:queue_url]]
		end
		wait_time = configuration[:queue_receive_wait_seconds] || 0
		if @@queue and run_seconds > (Time.now + wait_time - start) then
			message = @@queue.receive_message(:wait_time_seconds => wait_time)
			if message then
				job = nil
				begin
					job = JSON.parse(message.body)
					begin
						job['id'] = message.id unless job['id']
						File.open("#{configuration[:dir_queue]}/#{message.id}.json", 'w') { |file| file.write(job.to_json) } 
						message.delete
					rescue Exception => e
						puts "job could not be written to: #{configuration[:dir_queue]}" 
					end
				rescue Exception => e
					puts "job could not be parsed as json: #{message.body}" 
					message.delete
				end
			end
		end
	end
	def self.__s3 source
		((source[:region] and not source[:region].empty?) ? AWS::S3.new(:region => source[:region]) : AWS::S3.new)
	end
	def self.__s3_bucket source
		s3 = __s3 source
		s3.buckets[source[:bucket]]
	end
	def self.__transfer_directory transfer
		bits = Array.new
		bits << '' # so it starts with slash when we join at end
		bit = transfer[:directory]
		if bit then
			bit['/'] = '' if bit.start_with?('/') or bit.end_with?('/')
			bits << bit
		end
		bit = transfer[:path]
		if bit then
			bit['/'] = '' if bit.start_with?('/') or bit.end_with?('/')
			bits << bit
		end
		bits.join '/'
	end
	def self.__transfer_file mode, source_path, out_file
		source_path = "/#{source_path}" unless source_path.start_with? '/'
		if File.exists? source_path
			out_file = "/#{out_file}" unless out_file.start_with? '/'
			case mode
			when Method::Symlink
				FileUtils.symlink source_path, out_file
			when Method::Copy
				FileUtils.copy source_path, out_file
			when Method::Move
				FileUtils.move source_path, out_file
			end
			raise "could not #{mode} #{source_path} to #{out_file}" unless File.exists? out_file
		else
			raise 
		end
	rescue 
		puts "could not #{mode} #{source_path} to #{out_file}"
		raise
	end
	def self.__transfer_file_from_data file
		unless file.is_a? String then
			file_path = "#{output_path}trigger_data-#{UUID.new.generate}.json"
			File.open(file_path, 'w') { |f| f.write(file.to_json) }
			file = file_path
		end
		file
	end
	def self.__transfer_file_destination file, destination
		
		# just use directory if we output a sequence
		file = File.dirname(file) + '/' if file.include? '%'

		destination_path = __directory_path_name_destination destination
		destination_path = File.dirname(destination_path) + '/' if destination_path.include? '%'
		case destination[:type]
		when Type::File
			FileUtils.mkdir_p(File.dirname(destination_path))
			destination[:file] = destination_path
			__transfer_file destination[:method], file, destination_path
			@@job[:progress][:uploaded] += (File.directory?(file) ? Dir.entries(file).length : 1)
			__trigger :progress
		when Type::S3
			files = Array.new
			uploading_directory = File.directory?(file)
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
				bucket_key = destination_path
				bucket_key += File.basename(file) if bucket_key.end_with? '/'
				mime_type = cache_file_mime file, true
				bucket = __s3_bucket destination
				#puts "destination: #{destination.inspect}"
				#puts "bucket_key: #{bucket_key}"
				bucket_object = bucket.objects[bucket_key]
				options = Hash.new
				options[:acl] = destination[:acl].to_sym if destination[:acl]
				options[:content_type] = mime_type
				#puts "write options: #{options}"
				bucket_object.write(Pathname.new(file), options)
				@@job[:progress][:uploaded] += 1
				__trigger :progress
			end
		when Type::Http, Type::Https
				files.each do |file|
					bucket_key = destination_path
					bucket_key += File.basename(file) if bucket_key.end_with? '/'
					mime_type = __cache_get_info file, 'Content-Type'
					bucket = __s3_bucket destination
					puts "destination: #{destination.inspect}"
					puts "bucket_key: #{bucket_key}"
					bucket_object = bucket.objects[bucket_key]
					options = Hash.new
					options[:acl] = destination[:acl].to_sym if destination[:acl]
					options[:content_type] = mime_type
					puts "write options: #{options}"
					bucket_object.write(Pathname.new(file), options)
				end
			end
		when SourceTypeHttp, SourceTypeHttps
			url = "#{destination[:type]}://#{destination[:host]}"
			url += '/' unless destination_path.start_with? '/'
			url += destination_path
			uri = URI(url)
			uri.port = destination[:port].to_i if destination[:port]
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
				mime_type = cache_file_mime file, true
				io = File.open(file)
				raise "could not open file #{file}" unless io
				req = Net::HTTP::Post::Multipart.new(uri.path, "key" => destination_path, "file" => UploadIO.new(io, mime_type, file_name))
				raise "could not construct request" unless req
				req.basic_auth(destination[:user], destination[:pass]) if destination[:user] and destination[:pass]
				res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
					result = http.request(req)
					__log(:debug) {"uploaded #{file}\n#{result.body}"}
				end
				io.close 
				@@job[:progress][:uploaded] += 1
				__trigger :progress
			end
		end
	end
	def self.__transfer_file_name transfer	
		name = transfer[:name] || ''
		name += '.' + transfer[:extension] if transfer[:extension]
		name
	end
	def self.__transfer_job_output
		destination = @@output[:destination] || @@job[:destination]
		raise "output #{output[:identifier]} has no destination" unless destination 
		file = @@output[:rendering]
		if File.exists?(file) then
			if destination[:archive] || @@output[:archive] then
				raise "TODO: __transfer_job_output needs support for archive option"
			end
			__transfer_file_destination file, destination
		else
			__log(:warn) { "file was not rendered #{file}" }
			__log(:error) { "required output not rendered" } if @@output[:required]
		end
	end
	def self.__trigger type
		dont_trigger = false
		unless :progress == type then
			dont_trigger = @@job[:calledback][type]
			@@job[:calledback][type] = true unless dont_trigger
		end
		unless dont_trigger then
			type_str = type.id2name
			@@job[:callbacks].each do |callback|
				next unless type_str == callback[:trigger]
				if :progress == type then
					last_triggered = @@job[:calledback][type]
					next if last_triggered and last_triggered + callback[:progress_seconds] > Time.now
					@@job[:calledback][type] = Time.now
				end
				data = callback[:data] || nil
				if data then
					if data.is_a?(Hash) or data.is_a?(Array) then
						data = Marshal.load(Marshal.dump(data)) 
						eval_recursively data, __eval_scope
					else # only arrays and hashes supported
						data = nil  
					end
				end
				trigger_error = __trigger_transfer data, callback
				@@job[:progress][:triggered] += 1 unless :progress == type
				__log(:error) { trigger_error } if trigger_error and callback[:required]
			end
		end
	end
	def self.__trigger_transfer data, destination
		err = nil
		destination_path = __directory_path_name_source destination
		case destination[:type]
		when Type::File
			FileUtils.mkdir_p(File.dirname(destination_path))
			destination[:file] = destination_path
			if data then
				file = __transfer_file_from_data data
				__transfer_file destination[:method], file, destination_path
			end
		when Type::Http, Type::Https
			url = "#{destination[:type]}://#{destination[:host]}"
			path = __directory_path_name_source destination
			url += '/' unless path.start_with? '/'
			url += path
			uri = URI(url)
			uri.port = destination[:port].to_i if destination[:port]
			req = nil
			if data and not data.empty? then
				req = Net::HTTP::Post.new(uri)
				__log(:debug) {"posting callback #{uri.to_s} #{data.to_json}"}
				req.body = data.to_json
			else # simple get request
				__log(:debug) {"getting callback #{uri.to_s}"}
				req = Net::HTTP::Get.new(uri)
			end
			req.basic_auth(destination[:user], destination[:pass]) if destination[:user] and destination[:pass]
			res = Net::HTTP.start(uri.host, uri.port, :use_ssl => (uri.scheme == 'https')) do |http|
				result = http.request(req)
				if '200' == result.code then
					__log(:debug) {"callback OK response: #{result.body}"}
				else
					err = "callback ERROR #{result.code} response: #{result.body}"
				end
			end
		else
			err = "unsupported destination type #{destination[:type]}"
		end
		__log(:warn) { err } if err
		err
	end
end
