require 'digest/sha2'
require 'fileutils'
require 'logger'  
require 'mime/types'
require 'net/http'
require 'net/http/post/multipart'
require 'open3'
require 'rack'
require 'require_all'
require 'uri'
require 'uuid'
require 'yaml'
require 'json'

require_all __dir__

module MovieMasher
	PathConfiguration = "#{__dir__}/../config/config.yml"
	@@codecs = nil
	@@configuration = Hash.new
	@@formats = nil
	@@job = nil
	@@output = nil
	@@log = nil
	@@queue = nil
	def self.app_exec(cmd, out_file = '', duration = nil, precision = 1, app = 'ffmpeg')
		#puts "app_exec #{app}"
		outputs_file = (out_file and (not out_file.empty?) and ('/dev/null' != out_file))
		whole_cmd = configuration["path_#{app}".to_sym]
		whole_cmd += ' ' + cmd
		file_safe(File.dirname(out_file)) if outputs_file
		whole_cmd += " #{out_file}" if out_file and not out_file.empty?
		#puts whole_cmd
		
		@@job[:commands] << whole_cmd if @@job
		__log(:debug) { whole_cmd }
		
		result = Open3.capture3(whole_cmd).join "\n"
		if outputs_file and not out_file.include?('%') then	
			unless File.exists?(out_file) and File.size?(out_file)
				__log(:debug) { result }
				raise Error::JobRender.new result
			end
			if duration then
				audio_duration = cache_get_info(out_file, 'audio_duration')
				video_duration = cache_get_info(out_file, 'video_duration')
				__log(:debug) { "rendered file with audio_duration: #{audio_duration} video_duration: #{video_duration}" }
				unless audio_duration or video_duration
					__log(:warn) { result }
					raise Error::JobRender.new result, "could not determine if #{duration} == duration of #{out_file}" 
				end
				unless Float.cmp(duration, video_duration.to_f, precision) or Float.cmp(duration, audio_duration.to_f, precision)
					__log(:warn) { result }
					raise Error::JobRender.new result, "generated file with incorrect duration #{duration} != #{audio_duration} or #{video_duration} #{out_file}" 
				end
			end
		end 
		__log(:debug) { result }
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
	def self.configure config_file_or_data = nil
		if @@configuration.empty? or config_file_or_data # allow reconfiguration
			config_file_or_data = PathConfiguration unless config_file_or_data
			config = nil
			if config_file_or_data.is_a? Hash
				config = config_file_or_data
			elsif config_file_or_data.is_a? String
				if File.exists? config_file_or_data
					config = YAML::load(File.open(config_file_or_data))
				end
			end
			raise Error::Configuration.new "could not open configuration file #{config_file_or_data} #{config}" unless config and config.is_a?(Hash) and not config.empty?
			@@configuration = Hash.new
		
			# grab all keys in configuration starting with aws_, to pass to AWS if needed
			aws_config = Hash.new
			config.each do |key_str,v|
				key_str = key_str.id2name if v.is_a? Symbol
				key_str = key_str.dup
				key_sym = key_str.to_sym
				@@configuration[key_sym] = v
				if key_str.start_with? 'aws_' then
					key_str['aws_'] = ''
					aws_config[key_str.to_sym] = v
				end
			end
			[:dir_cache, :dir_error, :dir_log, :dir_queue, :dir_temporary].each do |sym|
				is_defined = @@configuration[sym] and not @@configuration[sym].empty?
				case sym
				when :dir_error, :dir_log 
					# optional
				else
					raise Error::Configuration.new "#{sym.id2name} must be defined" unless is_defined
				end
				if is_defined then
					# expand directory and create if needed
					@@configuration[sym] = File.expand_path(@@configuration[sym])
					@@configuration[sym] += '/' unless @@configuration[sym].end_with? '/'
					file_safe(@@configuration[sym]) unless File.directory?(@@configuration[sym])
					if :dir_log == sym then
						aws_config[:logger] = Logger.new "#{@@configuration[sym]}/moviemasher.rb.aws.log"
						@@log = Logger.new("#{@@configuration[sym]}/moviemasher.rb.log", 7, 1048576 * 100)
						log_level = (@@configuration[:log_level] || 'info').upcase
						@@log.level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
					end
				end
			end
			unless aws_config.empty? and @@configuration[:queue_url].empty?
				require 'aws-sdk' unless defined? AWS
				AWS.config(aws_config) unless aws_config.empty?
			end
		end
	end
	def self.file_safe path = nil
		options = Hash.new
		options[:mode] = configuration[:chmod_dir_new] if configuration[:chmod_dir_new]
		FileUtils.makedirs path, options
	end
	def self.formats
		@@formats = app_exec('-formats') unless @@formats
		@@formats
	end
	def self.output_path dont_append_slash = nil
		raise Error::State.new "output_path called without active job and output" unless @@job and @@output
		path = __path_job
		path += @@output[:identifier]
		path += '/' unless dont_append_slash
		path
	end
	def self.process orig_job
		rescued_exception = nil
		begin
			__log_transcoder(:debug) { "process called" }
			raise Error::JobInput.new "job false or not a Hash" unless orig_job and orig_job.is_a? Hash 
			job = Marshal.load(Marshal.dump(orig_job))
			@@job = job
			hash_keys_to_symbols! @@job
			# create internal identifier for job
			@@job[:identifier] = UUID.new.generate
			# create directory for job (uses identifier)
			path_job = __path_job
			file_safe path_job
			# copy orig_job to job directory
			File.open(path_job + 'job_orig.json', 'w') { |f| f.write(orig_job.to_json) }
			# create log for job and set log level
			@@job[:logger] = Logger.new(path_job + 'log.txt')
			log_level = @@job[:log_level]
			log_level = configuration[:log_level] unless log_level and not log_level.empty?
			log_level = 'info' unless log_level and not log_level.empty?
			log_level = log_level.upcase
			log_level = (Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO)
			@@job[:logger].level = log_level
			__init_job
			# copy job to job directory
			File.open(path_job + 'job.json', 'w') { |f| f.write(@@job.to_json) }
			
			unless @@job[:error]
				__log(:info) { "job parsed and initialized" }
				input_ranges = Array.new
				copy_files = Hash.new # key is value of input[:copy] (name for copied input)
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
					module_source = (input[:module_source] || @@job[:module_source])
					input_url = __input_url input, base_source, module_source
					if input_url then
						input[:input_url] = input_url
						input_urls << input_url
					elsif Type::Mash == input[:type] then
						input_urls = __input_urls input[:source], outputs_desire, base_source, module_source
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
			end
			unless @@job[:error]
				__log(:info) { "job initiated" }
				@@job[:inputs].each do |input|
					input_url = input[:input_url]
					if input_url then
						# if it's a mash we don't yet know whether it has desired content types
						if (Type::Mash == input[:type]) or __has_desired?(__input_has(input), outputs_desire) then
							base_source = (input[:base_source] || @@job[:base_source])
							module_source = (input[:module_source] || @@job[:module_source])
							@@job[:cached][input_url] = __cache_input input, input_url, base_source, module_source
							@@job[:progress][:downloaded] += 1	
							__trigger :progress
							# TODO: handle copy flag in input
							copy_files[input[:copy]] = @@job[:cached][input_url] if input[:copy]
						end
						if (Type::Mash == input[:type]) then
							input[:source] = JSON.parse(File.read(@@job[:cached][input_url])) 
							__init_input_mash input
							input_urls = __input_urls input[:source], outputs_desire, base_source, (input[:module_source] || @@job[:module_source])
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
					break if @@job[:error]
				end
			end
			unless @@job[:error]
				__log(:info) { "job cached" }
				# everything that needs to be cached is now cached
				__set_timing
				#puts "video_outputs: #{video_outputs}"
				#puts "audio_outputs: #{audio_outputs}"
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
					begin
						__build_output video_graphs, audio_graphs
					rescue Error::Job => e
						__log(:warn) { "output failed to render: #{e.message}" }
						raise if output[:required]
					rescue Exception => e
						__log_transcoder(:error) {"ERROR: #{e.message}"}
						raise
					end
					@@job[:progress][:rendered] += 1 + (video_graphs.length + audio_graphs.length)
					@@job[:progress][:uploading] += ((output[:fps].to_f * output[:duration]).floor - 1) if Type::Sequence == output[:type]
					__trigger :progress
					break if @@job[:error]
				end
			end
			unless @@job[:error]
				@@job[:outputs].each do |output|
					@@output = output
					__transfer_job_output
					break if @@job[:error]
				end
				__log(:info) { "job transfered" } unless @@job[:error]
			end
		rescue Exception => e
			rescued_exception = e
		end
		begin
			if rescued_exception # raised while processing job
				rescued_exception = __log_exception rescued_exception
				__trigger :error
			end
		rescue Exception => e
			rescued_exception = e
		end
		begin
			rescued_exception = __log_exception(rescued_exception) if rescued_exception
			__trigger :complete
			__log(:info) { "job completed" }
		rescue Exception => e
			rescued_exception = e
		end
		begin
			rescued_exception = __log_exception(rescued_exception) if rescued_exception
			job_path = path_job
			if @@job[:error] and configuration[:dir_error] and not configuration[:dir_error].empty? then
				FileUtils.mv job_path, configuration[:dir_error] + File.basename(job_path)
			else
				FileUtils.rm_r job_path unless configuration[:keep_temporary_files]
			end
		rescue Exception => e
			rescued_exception = e
		ensure
			@@output = nil
			@@job = nil
		end
		rescued_exception = __log_exception(rescued_exception) if rescued_exception
		flush_cache_files configuration[:dir_cache], configuration[:cache_gigs]
		job
	end
	def self.process_queues
		run_seconds = configuration[:process_queues_seconds]
		start = Time.now
		oldest_file = nil
		working_file = "#{configuration[:dir_queue]}working.json"
		while run_seconds > (Time.now - start)
			if File.exists? working_file
				# if this process didn't create it, we must have crashed on it in a previous run
				__log_transcoder(:error) { "deleting previously active job:\n#{File.read working_file}" } unless oldest_file
				File.delete working_file
			end
			oldest_file = Dir["#{configuration[:dir_queue]}*.json"].sort_by{ |f| File.mtime(f) }.first
			if oldest_file then
				__log_transcoder(:info) { "started #{oldest_file}" }
				File.rename oldest_file, working_file
				json_str = File.read working_file
				job = nil
				begin
					job = JSON.parse json_str
					unless job and job.is_a? Hash 
						__log_transcoder(:error) { "parsed job was false or not a Hash: #{oldest_file} #{json_str}" }
						job = nil
					end
				rescue JSON::ParserError
					__log_transcoder(:error) { "job could not be parsed as json: #{oldest_file} #{json_str}" }
				end
				process job if job
				__log_transcoder(:info) { "finished #{oldest_file}" }
				File.delete working_file
				sleep 1
			else # see if there's one in the queue
				__sqs_request(run_seconds, start) if configuration[:queue_url]
			end
		end
	end
	def self.__assure_sequence_complete result
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
						__log(:warn) { "creating #{File.basename file_path} as link to #{File.basename last_file} in sequence" }
						File.symlink last_file, file_path
					else
						raise Error::JobRender.new result, "could not generate any sequence files"
						break
					end
				end
			end
		end
	end
	def self.__audio_from_file path
		#puts "__audio_from_file #{path}"
		raise Error::Parameter.new "__audio_from_file with invalid path" unless path and (not path.empty?) and File.exists? path
		out_file = "#{File.dirname path}/#{File.basename path}-intermediate.#{Intermediate::AudioExtension}"
		unless File.exists? out_file then
			cmds = Array.new
			cmds << shell_switch(path, 'i')
			cmds << shell_switch(2, 'ac')
			cmds << shell_switch(44100, 'ar')
			app_exec cmds.join, out_file
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
					if 1 == video_graphs.length and video_graphs.first.is_a?(RawGraph) then
						graph = video_graphs[0]
						video_duration = graph.duration
						cmd = graph.graph_command @@output
						raise Error::JobInput.new "could not build complex filter" if cmd.empty?
					else 
						cmd = __filter_graphs_concat @@output, video_graphs
						raise Error::JobInput.new "Could not build complex filter" if cmd.empty?
						video_graphs.each do |graph|
							video_duration += graph.duration
						end
					end
					cmds << shell_switch(@@output[:fps], 'r') if @@output[:fps]
					cmds << shell_switch("'#{cmd}'", 'filter_complex')
				else 
					avb = Type::Audio
				end
			end
			#puts "__output_desires #{avb}"
			unless Type::Video == avb then # we've got audio
				audio_graphs_count = audio_graphs.length
				if 0 < audio_graphs_count then
					data = audio_graphs[0]
					if 1 == audio_graphs_count and 1 == data[:loop] and (not Mash.gain_changes(data[:gain])) and Float.cmp(data[:start_seconds], Float::Zero) then
						# just one non-looping graph, starting at zero with no gain change
						raise Error::JobInput.new "zero length #{data.inspect}" unless Float.gtr(data[:length_seconds], Float::Zero)
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
							raise Error::JobInput.new "negative start time #{data.inspect}" unless Float.gtre(start, Float::Zero)
							raise Error::JobInput.new "zero length #{data.inspect}" unless Float.gtr(data[:length_seconds], Float::Zero)
							data[:waved_file] = __audio_from_file(data[:cached_file]) unless data[:waved_file]
							audio_cmd += " -a:#{counter} -i "
							counter += 1
							audio_cmd += 'audioloop,' if 1 < loops
							audio_cmd += "playat,#{data[:start_seconds]},"
							audio_cmd += "select,#{data[:trim_seconds]},#{data[:length_seconds]}"
							audio_cmd += ",typeselect,.raw,#{data[:waved_file]}"
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
							#puts "audio_duration = #{data[:start_seconds]} + #{data[:length_seconds]}"
							audio_duration = Float.max(audio_duration, data[:start_seconds] + data[:length_seconds])
						end
						audio_cmd += ' -a:all -z:mixmode,sum'
						audio_cmd += ' -o'
						audio_path = "#{output_path}audio-#{__hash audio_cmd}.#{Intermediate::AudioExtension}"
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
							cmds << shell_switch("'atrim=start=#{data[:trim_seconds]}:duration=#{audio_duration},asetpts=expr=PTS-STARTPTS'", 'af') 
						end
						cmds << shell_switch(1, 'async')
				
					end
				else
					avb = Type::Video
					#puts "no audio graphs"
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
				raise Error::JobInput.new "graph duration does not match job duration #{duration} != #{@@job[:duration]}" if duration and not Float.cmp(duration, @@job[:duration])
				do_single_pass = (not type_is_video_or_audio)
				unless do_single_pass then
					pass_log_file = "#{File.dirname @@output[:rendering]}/#{@@output[:identifier]}.txt"
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
					result = app_exec cmd, out_path, duration, @@output[:precision]
					__assure_sequence_complete(result) if Type::Sequence == @@output[:type]
				end
			end
		end
	end
	def self.__cache_input input, input_url, base_source = nil, module_source = nil
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
				raise Error::JobInput.new "no source for #{input_url}" unless source
				__cache_source source, input_url, cache_url_path
				raise Error::JobInput.new "could not cache #{input_url}" unless File.exists? cache_url_path
			end
			input[:cached_file] = cache_url_path
			unless input[:type] then
				input[:type] = cache_file_type(cache_url_path)
				__init_input input
			end
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
				raise Error::JobInput.new "could not determine image dimensions" unless input[:dimensions]
			end
		else
			raise Error::JobInput.new "could not produce an input_url #{input}"
		end
		cache_url_path
	end
	def self.__cache_job_mash input, outputs_desire
		mash = input[:source]
		base_source = (input[:base_source] || @@job[:base_source])
		module_source = (input[:module_source] || @@job[:module_source])
		mash[:media].each do |media|
			case media[:type]
			when Type::Video, Type::Audio, Type::Image, Type::Font
				if __has_desired?(__input_has(media), outputs_desire) then
					input_url = __input_url media, base_source, module_source
					if input_url then
						@@job[:cached][input_url] = __cache_input media, input_url, base_source, module_source
						@@job[:progress][:downloaded] += 1
						__trigger :progress
					end
				end
			end
		end
	end
	def self.__cache_source source, input_url, out_file
		file_safe(File.dirname(out_file))
		case source[:type]
		when Type::File
			source_path = input_url.dup
			source_path['file:'] = ''
			#__directory_path_name_source source
			if File.exists? source_path
				__transfer_file(source[:method], source_path, out_file) 
			else
				__log(:error) { "file does not exist #{source_path}" }
			end
		when Type::Http, Type::Https
			uri = URI input_url
			uri.port = source[:port] if source[:port]
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
						puts "MIME: #{mime_type}"
						cache_set_info(out_file, 'Content-Type', mime_type) if mime_type
					else
						__log(:warn) {"got #{response.code} response code from #{input_url}"}
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
			if file_name.empty?
				paths = Array.new
				file_name = Path.strip_slashes @@output[:path]
				paths << file_name unless file_name.empty?
				unless Type::Sequence == @@output[:type]
					# otherwise we mean the directory, since name is something like 0%3d.jpg
					file_name = __transfer_file_name(@@output)
					paths << file_name unless file_name.empty?
				end
				file_name = paths.join '/'
			end
			key = __transfer_directory destination
			unless file_name.empty?
				key += '/' unless key.end_with? '/'
				key += file_name
			end
		end
		Evaluate.value key, __eval_scope
	end
	
	def self.__eval_scope
		scope = Hash.new
		scope[:job] = @@job
		scope[:output] = @@output
		scope[:log] = Proc.new { File.read(__path_job + 'log.txt') }
		scope
	end
	def self.__filter_graphs_audio inputs
		graphs = Array.new
		start_counter = Float::Zero	
		inputs.each do |input|
			next if input[:no_audio]
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
				#puts "audio_clips.length: #{audio_clips.length}"
				audio_clips.each do |clip|
					media = Mash.media input[:source], clip[:id]
					raise Error::JobInput.new "could not find media for clip #{clip[:id]}" unless media
					clip[:cached_file] = media[:cached_file] || raise("could not find cached file")
					clip[:duration] = media[:duration]
					clip[:no_audio] = media[:no_audio] unless clip[:no_audio]
					next if clip[:no_audio]
					data = Hash.new
					data[:type] = clip[:type]
					data[:trim_seconds] = clip[:trim_seconds]
					data[:length_seconds] = clip[:length_seconds]
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
		#intermediate_output = __output_intermediate
		#intermediate_output[:fps] = output[:fps]
		#intermediate_output[:dimensions] = output[:dimensions]
		graphs.length.times do |index|
			graph = graphs[index]
			duration = graph.duration
			cmd = graph.graph_command output
			raise Error::JobInput.new "Could not build complex filter" if cmd.empty?
			# yuv444p, yuv422p, yuv420p, yuv411p
			#cmd += ",format=pix_fmts=yuv420p"
			#cmd += ",format=pix_fmts=rgba"-pix_fmt yuv420p
			#,fps=fps=#{output[:fps]}
			cmd = " -filter_complex '#{cmd}' -t #{duration} "
			cmd += __output_command output, Type::Video
			out_file = "#{output_path}concat-#{cmds.length}.#{output[:extension]}"
			cmd = '-y' + cmd
			app_exec cmd, out_file
			cmd = "movie=filename=#{out_file}"
			cmd += "[concat#{cmds.length}]" if 1 < graphs.length
			cmds << cmd
		end
		if 1 < cmds.length
			cmd = ''
			cmds.length.times do |i|
				cmd += "[concat#{i}]"
			end
			cmd += "concat=n=#{cmds.length}"
			cmds << cmd
		end
		cmds.join ';'
	end
	def self.__filter_graphs_video inputs
		graphs = Array.new
		raise Error::State.new "__filter_graphs_video already called" unless 0 == graphs.length
		inputs.each do |input|
			next if input[:no_video]
			case input[:type]
			when Type::Mash
				mash = input[:source]
				all_ranges = Mash.video_ranges mash
				all_ranges.each do |range|
					graph = MashGraph.new input, range
					clips = Mash.clips_in_range mash, range, Type::TrackVideo
					if 0 < clips.length then
						transition_layer = nil
						transitioning_clips = Array.new
						clips.each do |clip|
							case clip[:type]
							when Type::Video, Type::Image
								# media properties were copied to clip BEFORE file was cached, so repeat now
								media = Mash.media mash, clip[:id]
								raise Error::JobInput.new "could not find media for clip #{clip[:id]}" unless media
								clip[:cached_file] = media[:cached_file] || raise("could not find cached file #{media}")
								clip[:no_video] = media[:no_video] unless clip[:no_video]
								clip[:dimensions] = media[:dimensions] || raise("could not find dimensions #{clip} #{media}")
							end	
							if Type::Transition == clip[:type] then
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
							when Type::Video, Type::Image, Type::Theme
								graph.add_new_layer clip
							end
						end
					end
					graphs << graph
				end
			when Type::Video, Type::Image
				graphs << RawGraph.new(input)
			end
		end
		graphs
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
		raise Error::JobInput.new "mash clips must have length" unless input[:length] and 0 < input[:length]
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
			input[:to][:merger] = Defaults.module_for_type(:merger) unless input[:to][:merger]
			input[:to][:scaler] = Defaults.module_for_type(:scaler) unless input[:to][:scaler] or input[:to][:fill]
			input[:from][:merger] = Defaults.module_for_type(:merger) unless input[:from][:merger]
			input[:from][:scaler] = Defaults.module_for_type(:scaler) unless input[:from][:scaler] or input[:from][:fill]
			__init_clip_media(input[:to][:merger], mash, Type::Merger)
			__init_clip_media(input[:from][:merger], mash, Type::Merger)
			__init_clip_media(input[:to][:scaler], mash, Type::Scaler)
			__init_clip_media(input[:from][:scaler], mash, Type::Scaler)
		when Type::Video, Type::Audio
			input[:trim] = 0 unless input[:trim]
			input[:trim_seconds] = input[:trim].to_f / mash[:quantize] unless input[:trim_seconds]
		end
		__init_raw_input input
		# this is done for real inputs during __set_timing
		__init_input_ranges input
		input
  	end
	def self.__init_clip_media clip, mash, type = nil
		raise Error::JobInput.new "clip has no id #{clip}" unless clip[:id]
		media = Mash.media_search type, clip, mash
		raise Error::JobInput.new "#{clip[:id]} #{type ? type : 'media'} not found in mash" unless media
		media.each do |k,v|
			clip[k] = v unless clip[k]
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
 		if input[:effects] then
			input[:effects].each do |effect|
				effect[:range] = input[:range]
			end
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
		if ((not output[key]) or output[key].to_s.empty?)
			output[key] = default 
		end
	end
	def self.__init_mash mash
		__init_key mash, :backcolor, 'black'
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
					__init_clip_media(clip[:merger], mash, :merger) if clip[:merger]
					__init_clip_media(clip[:scaler], mash, :scaler) if clip[:scaler]
					clip[:effects].each do |effect|
						__init_clip_media effect, mash, :effect
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
	
		input_type = input[:type]
		is_av = [Type::Video, Type::Audio].include? input_type
		is_v = [Type::Video, Type::Image, Type::Frame].include? input_type

		input[:effects] = Array.new unless input[:effects] and input[:effects].is_a? Array
		input[:merger] = Defaults.module_for_type(:merger) unless input[:merger]
		input[:scaler] = Defaults.module_for_type(:scaler) unless input[:scaler] or input[:fill]
	
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
			input[:speed] = (input[:speed] ? input[:speed].to_f : Float::One) 
			input[:no_audio] = ! Float.cmp(Float::One, input[:speed])
			#puts "__init_raw_input #{input[:label]} no_audio: #{input[:no_audio]} #{input[:speed]}"
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
	def self.__input_urls mash, outputs_desire, base_source, module_source
		input_urls = Array.new
		mash[:media].each do |media|
			if __has_desired?(__input_has(media), outputs_desire) then
				input_url = __input_url media, base_source, module_source
				next unless input_url
				input_urls << input_url unless input_urls.include? input_url
			end
		end
		input_urls
	end
	def self.__input_url input, base_source = nil, module_source = nil
		url = nil
		if input[:source] then
			if input[:source].is_a? String then 
				url = input[:source]
				if not url.include? '://' then # it would start with file:/// if a file path
					# relative url
					case input[:type]
					when Type::Theme, Type::Font, Type::Effect
						base_source = module_source if module_source
					end
					base_url = __source_url base_source
					if base_url then
						base_url = Path.add_slash_end base_url
						url = Path.strip_slash_start url
						url = URI.join(base_url, url).to_s
					end
					__log(:warn) { "using source #{base_source} #{base_url} #{url}" }
				end
			elsif input[:source].is_a?(Hash)  then
				unless Type::Mash == input[:type] and Mash.hash?(input[:source]) then
					url = __source_url input[:source]
				end
			end
		end
		url
	end
	def self.__log type, &proc
		if @@job then
			@@job[:error] = proc.call if :error == type
			@@job[:logger].send(type, &proc) 
		end
		__log_transcoder(type, &proc) if 'debug' == configuration[:log_level]
	end
	def self.__log_exception rescued_exception
		unless rescued_exception.is_a? Error::Job
			str =  "#{rescued_exception.backtrace.join "\n"}\n#{rescued_exception.message}" 
			puts str # so it gets in cron log as well
			__log_transcoder(:error) { str }
			
		end
		__log(:debug) { rescued_exception.backtrace.join "\n" }
		__log(:error) { rescued_exception.message }
		nil # so we can assign in a oneliner
	end
	def self.__log_transcoder type, &proc
		@@log.send(type, proc.call) if @@log and @@log.send((type.id2name + '?').to_sym)
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
	def self.__path_job
		raise Error::State.new "__path_job called with no active job" unless @@job
		path = configuration[:dir_temporary]
		path += @@job[:identifier] + '/'
		path
	end
	def self.__render_path
		raise Error::State.new "__render_path called without active job and output" unless @@job and @@output
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
				when Type::Http, Type::Https
					url += input_source[:host] if input_source[:host]
				when Type::S3
					url += "#{input_source[:bucket]}." if input_source[:bucket] and not input_source[:bucket].empty?
					url += 's3'
					url += "-#{input_source[:region]}" if input_source[:region] and not input_source[:region].empty?
					url += '.amazonaws.com'
				end
				path = __directory_path_name_source input_source
				url += '/' unless path.start_with? '/'
				url += path
			end
		end
		url
	end
	def self.__sqs
		require 'aws-sdk' unless defined? AWS
		((configuration[:queue_region] and not configuration[:queue_region].empty?) ? AWS::SQS.new(:region => configuration[:queue_region]) : AWS::SQS.new)
	end
	def self.__sqs_request run_seconds, start
		unless @@queue then
			sqs = __sqs
			# queue will be nil if their URL is not defined in config.yml
			@@queue = sqs.queues[configuration[:queue_url]]
		end
		wait_time = configuration[:queue_wait_time_seconds] || 0
		if @@queue and run_seconds > (Time.now + wait_time - start) then
			message = @@queue.receive_message(:wait_time_seconds => wait_time)
			if message then
				job = nil
				begin
					job = JSON.parse(message.body)
					begin
						job['id'] = message.id unless job['id']
						File.open("#{configuration[:dir_queue]}#{message.id}.json", 'w') { |file| file.write(job.to_json) } 
						message.delete
					rescue Exception => e
						__log_exception e
					end
				rescue Exception => e
					__log_exception e
					__log_transcoder(:error) { "job could not be parsed as json: #{message.body}"  }
					message.delete
				end
			end
		end
	end
	def self.__s3 source
		require 'aws-sdk' unless defined? AWS
		((source[:region] and not source[:region].empty?) ? AWS::S3.new(:region => source[:region]) : AWS::S3.new)
	end
	def self.__s3_bucket source
		s3 = __s3 source
		s3.buckets[source[:bucket]]
	end
	def self.__transfer_directory transfer
		bits = Array.new
		bit = transfer[:directory]
		bits << Path.strip_slashes(bit) if bit
		bit = transfer[:path]
		bits << Path.strip_slashes(bit) if bit
		Path.add_slash_start(bits.join '/')
	end
	def self.__transfer_file mode, source_path, out_file
		source_path = Path.add_slash_start source_path
		if File.exists? source_path
			out_file = Path.add_slash_start out_file
			case mode
			when Method::Copy
				FileUtils.copy source_path, out_file
			when Method::Move
				FileUtils.move source_path, out_file
			else # Method::Symlink
				FileUtils.symlink source_path, out_file
			end
			raise Error::JobDestination.new "could not #{mode} #{source_path} to #{out_file}" unless File.exists? out_file
		else 
			
		end
	rescue Exception => e
		__log_exception e
	end
	
	def self.__transfer_file_name transfer	
		name = Path.strip_slashes transfer[:name]
		name += '.' + transfer[:extension] if transfer[:extension]
		name
	end
	def self.__transfer_job_output
		destination = @@output[:destination] || @@job[:destination]
		output_content_type = @@output[:mime_type]
		raise Error::JobInput.new "output has no destination" unless destination 
		file = @@output[:rendering]
		raise Error::Parameter.new "outpt rendering path with percent sign #{file}" if file.include? '%'
		if File.exists?(file) then
			if destination[:archive] || @@output[:archive] then
				raise Error::Todo.new "__transfer_job_output needs support for archive option"
			end
			destination_path = __directory_path_name_destination destination
			raise Error::Parameter.new "got invalid destination path with percent sign #{destination_path}" if destination_path.include? '%'
			case destination[:type]
			when Type::File
				file_safe(File.dirname(destination_path))
				__transfer_file destination[:method], file, destination_path
				destination[:file] = destination_path # for spec tests to find file...
				@@job[:progress][:uploaded] += (File.directory?(file) ? Dir.entries(file).length : 1)
				__trigger :progress
			when Type::S3
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
					bucket_key += Path.add_slash_start(File.basename(file)) if uploading_directory
					bucket = __s3_bucket destination
					bucket_object = bucket.objects[bucket_key]
					options = Hash.new
					options[:acl] = destination[:acl].to_sym if destination[:acl]
					options[:content_type] = output_content_type if output_content_type
					__log_transcoder(:debug) { "s3 write to #{bucket_key}" }
					bucket_object.write(Pathname.new(file), options)
					@@job[:progress][:uploaded] += 1
					__trigger :progress
				end
		
			when Type::Http, Type::Https
				url = "#{destination[:type]}://#{destination[:host]}"
				url += Path.add_slash_start destination_path
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
					io = File.open(file)
					raise Error::Object.new "could not open file #{file}" unless io
					upload_io = UploadIO.new(io, mime_type, file_name)
					req = Net::HTTP::Post::Multipart.new(uri.path, "key" => destination_path, "file" => upload_io)
					raise Error::JobDestination.new "could not construct multipart POST request" unless req
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
		else
			__log(:warn) { "file was not rendered #{file}" }
			__log(:error) { "required output not rendered" } if @@output[:required]
		end
	end
	def self.__trigger type
		__log_transcoder(:debug) { "__trigger #{type.id2name}" }
			
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
						Evaluate.recursively data, __eval_scope
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
		destination_path = Evaluate.value destination_path, __eval_scope
		case destination[:type]
		when Type::File
			file_safe(File.dirname(destination_path))
			destination[:file] = destination_path
			if data then
				file = "#{__path_job}trigger_data-#{UUID.new.generate}.json"
				File.open(file, 'w') { |f| f.write(data.to_json) }
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
				headers = {"Content-Type" => "application/json"}
				req = Net::HTTP::Post.new(uri, headers)
				__log(:debug) {"posting callback #{uri.to_s}"}
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
