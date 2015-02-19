
module MovieMasher
	module Info
		Audio = 'audio'
		Dimensions = 'dimensions'
		Duration = 'duration'
		VideoDuration = 'video_duration'
		AudioDuration = 'audio_duration'
		Type = 'type'
		FPS = 'fps'
		Extension = 'txt'
		At = 'at'
		Downloaded = 'downloaded'
		def self.get path, type
			raise Error::Parameter.new "false or empty path or type #{path}, #{type}" unless type and path and (not (type.empty? or path.empty?))
			result = nil
			data = nil
			if File.size?(path) then
				info_file = meta_path type, path
				if File.exists? info_file then
					result = File.read info_file
				else
					check = Hash.new
					case type
					when 'ffmpeg', 'sox' 
						check[type.to_sym] = true
					when Info::Type, 'http' 
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
						check[Info::Audio == Info.type(path) ? :sox : :ffmpeg] = true
					when Info::FPS, Info::Audio # only from FFMPEG
						check[:ffmpeg] = true
					end
					if check[:ffmpeg] then
						data = get(path, 'ffmpeg') if 'ffmpeg' != type
						unless data
							data = ShellHelper.execute :command => path, :app => 'ffprobe'
							if 'ffmpeg' == type
								result = data
								data = nil
							else
								Info.set path, 'ffmpeg', data
							end
						end
						result = parse(type, data) if data
					elsif check[:sox] then
						data = get(path, 'sox') if 'sox' != type
						unless data
							data = ShellHelper.execute :command => "--i #{path}", :app => 'sox'
							if 'sox' == type
								result = data
								data = nil					
							else
								Info.set(path, 'sox', data)
							end
						end
						result = parse(type, data) if data
					end
					# try to cache the data for next time
					Info.set(path, type, result) if result
				end
			end
			result
		end

		def self.meta_path type, path
			Path.concat File.dirname(path), "#{File.basename path, '.*'}.#{type}.#{Info::Extension}"
		end
		def self.parse type, ffmpeg_output
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
		def self.set path, type, data
			File.open(Info.meta_path(type, path), 'w') {|f| f.write(data) } if type and path
		end
		def self.type path
			result = nil
			if path then
				result = Info.get path, 'type'
				if not result then
					mime = Info.get path, 'Content-Type'
					if not mime then
						type = MIME::Types.of(path).first
						if type 
							mime = type.simplified
						#else
						#	mime = Rack::Mime.mime_type(File.extname(path))
						end
						#puts "LOOKING UP MIME: #{ext} #{mime}"
						Info.set(path, 'Content-Type', mime) if mime
					end
					result = mime.split('/').shift if mime
					Info.set(path, 'type', result) if result
				end
			end
			result
		end
	end
end
