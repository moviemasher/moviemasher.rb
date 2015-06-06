module MovieMasher
	module ShellHelper
		def self.execute options
			logs = Array.new
			cmd = options[:command]
			out_file = options[:file] || ''
			duration = options[:duration]
			precision = options[:precision] || 1
			app = options[:app] || 'ffmpeg'
			outputs_file = ((not out_file.empty?) and ('/dev/null' != out_file))
			whole_cmd = MovieMasher.configuration["#{app}_path".to_sym]
			whole_cmd = app unless whole_cmd and not whole_cmd.empty?
			whole_cmd += ' ' + cmd
			FileHelper.safe_path File.dirname(out_file) if outputs_file
			whole_cmd += " #{out_file}" if out_file and not out_file.empty?
			
			logs << {:debug => (Proc.new { whole_cmd })}
			result = Open3.capture3(whole_cmd).join "\n"
			# make sure result is utf-8 encoded
			enc_options = Hash.new
			enc_options[:invalid] = :replace
			enc_options[:undef] = :replace
			enc_options[:replace] = '?'
			#enc_options[:universal_newline] = true
			result.encode!(Encoding::UTF_8, enc_options)
			
			if outputs_file and not out_file.include?('%') then	
				unless File.exists?(out_file) and File.size?(out_file)
					logs << {:debug => (Proc.new { result }) }
					raise Error::JobRender.new result
				end
				if duration
				  
					audio_data = execute :command => "--i #{out_file}", :app => 'sox'
					video_data = execute :command => out_file, :app => 'ffprobe'
					audio_duration = Info.parse('duration', audio_data)
					video_duration = Info.parse('duration', video_data)
					logs << {:debug => (Proc.new { "rendered file with audio_duration: #{audio_duration} video_duration: #{video_duration}" }) }
					unless audio_duration or video_duration
						raise Error::JobRender.new result, "could not determine if #{duration} == duration of #{out_file}" 
					end
					unless FloatUtil.cmp(duration, video_duration.to_f, precision) or FloatUtil.cmp(duration, audio_duration.to_f, precision)
						logs << {:warn => (Proc.new { result }) }
						msg = "generated file with incorrect duration #{duration} != #{audio_duration} or #{video_duration} #{out_file}" 
						if -1 < precision
						  raise Error::JobRender.new result, msg
						else
						  logs << {:warn => (Proc.new { msg }) }
						end
					end
				end
			end 
			logs << {:debug => (Proc.new { result }) }
			#puts `ps aux | awk '{ print $8 " " $2 }' | grep -w Z`
			return result unless options[:log]
			return [result, whole_cmd, logs]
		end

	end
end
