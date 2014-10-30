
module MovieMasher
	module Error
		class Runtime < RuntimeError
			def initialize msg = nil
				@msg = msg if msg
			end
			def to_s
				@msg ? @msg : ''
			end
		end

		# job related errors		
		class Job < Runtime; end
		class JobOutput < Job; end
		class JobRender < JobOutput
			def initialize ffmpeg_result, msg = "failed to render"
				error_lines = Array.new
				error_lines << msg if msg
				if ffmpeg_result
					lines = ffmpeg_result.split "\n"
					failure_words = ['Error', 'Invalid', 'Failed']
					lines.reverse.each do |line|
						failure_words.each do |failure_word|
							if line.include? failure_word
								error_lines << line.split(/^\[.*\] /).last.strip
								break
							end
						end
					end
				end
				@msg = error_lines.join "\n" unless error_lines.empty?
			end
		end
		class JobUpload < Job; end
		class JobSource < Job; end
		class JobInput < Job; end
		class Todo < Job; end
		
		# serious code errors
		class Critical < Runtime; end
		class Parameter < Critical; end
		class Configuration < Critical; end
		class Object < Critical; end
		class State < Critical; end
	end
end