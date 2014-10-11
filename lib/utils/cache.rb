def cache_meta_path type, file_path
	parent_dir = File.dirname file_path
	base_name = File.basename file_path
	parent_dir + '/' + base_name + '.' + type + '.txt'
end
def cache_set_info(path, key_or_hash, data = nil)
	result = nil
	if key_or_hash and path then
		hash = Hash.new
		if key_or_hash.is_a?(Hash) then
			hash = key_or_hash
		else
			hash[key_or_hash] = data
		end
		hash.each do |k, v|
			info_file_path = cache_meta_path(k, path)
			File.open(info_file_path, 'w') {|f| f.write(v) }
		end
	end
end
def cache_file_mime path, dont_set = nil
	mime = cache_get_info path, 'Content-Type'
	if not mime then
		type = MIME::Types.of(path).first
		if type 
			mime = type.simplified
		else
			mime = Rack::Mime.mime_type(File.extname(path))
		end
		#puts "LOOKING UP MIME: #{ext} #{mime}"
		cache_set_info(path, 'Content-Type', mime) if mime and not dont_set
	end
	mime
end
def cache_file_type path, dont_set = nil
	result = nil
	if path then
		result = cache_get_info path, 'type'
		if not result then
			mime = cache_file_mime path, dont_set
			result = mime.split('/').shift if mime
			cache_set_info(path, 'type', result) if result and not dont_set
		end
	end
	result
end
def cache_get_info file_path, type
	raise Error::Parameter.new "false or empty file_path or type #{file_path}, #{type}" unless type and file_path and (not (type.empty? or file_path.empty?))
	result = nil
	if File.exists?(file_path) then
		info_file = cache_meta_path type, file_path
		if File.exists? info_file then
			result = File.read info_file
		else
			check = Hash.new
			case type
			when 'type', 'http', 'ffmpeg', 'sox' 
				# do nothing if file doesn't already exist
			when 'dimensions'
				check[:ffmpeg] = true
			when 'video_duration'
				check[:ffmpeg] = true
				type = 'duration'
			when 'audio_duration'
				check[:sox] = true
				type = 'duration'
			when 'duration'
				check[MovieMasher::Type::Audio == cache_file_type(file_path) ? :sox : :ffmpeg] = true
			when 'fps', MovieMasher::Type::Audio # only from FFMPEG
				check[:ffmpeg] = true
			end
			if check[:ffmpeg] then
				data = cache_get_info(file_path, 'ffmpeg')
				if not data then
					cmd = " -i #{file_path}"
					data = MovieMasher.app_exec cmd
					cache_set_info file_path, 'ffmpeg', data
				end
				result = cache_info_from_ffmpeg(type, data) if data
			elsif check[:sox] then
				data = cache_get_info(file_path, 'sox')
				if not data then
					cmd = "--i #{file_path}"
					data = MovieMasher.app_exec cmd, nil, nil, nil, 'sox'
					cache_set_info(file_path, 'sox', data)
				end
				result = cache_info_from_ffmpeg(type, data) if data
			end
			# try to cache the data for next time
			cache_set_info(file_path, type, result) if result
		end
	end
	result
end
def cache_info_from_ffmpeg type, ffmpeg_output
	result = nil
	case type
	when MovieMasher::Type::Audio
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

#def cache_aspect_ratio dimensions
#	result = dimensions
#	if dimensions then
#		wants_string = dimensions.is_a?(String)
#		dimensions = dimensions.split('x') if wants_string
#		w = dimensions[0].to_i
#		h = dimensions[1].to_i
#		gcf = cache_gcf(w, h)
#		result = [w / gcf, h / gcf]
#		result = result.join('x') if wants_string
#	end
#	result
#end
#	
#def cache_gcf a, b 
#	 ( ( b == 0 ) ? a : cache_gcf(b, a % b) )
#end
