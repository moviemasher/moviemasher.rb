
module MovieMasher
	class MetaReader < Hashable
		def initialize path 
			path = Dir[Path.concat path, '*'].first if File.directory? path # true for sequence outputs
			@path = path
			super Hash.new
		end
		def audio
			_info __method__
		end
		def dimensions
			_info __method__
		end
		def duration
			_info __method__
		end
		def video_duration
			_info __method__
		end
		def audio_duration
			_info __method__
		end
		def type
			_info __method__
		end
		def fps
			_info __method__
		end
		def ffmpeg
			_info __method__
		end
		
		def sox
			_info __method__
		end
		def http
			_info __method__
		end
		def [] symbol
			if @hash[symbol].nil?
				@hash[symbol] = _meta symbol
			end
			super
		end
		def _meta symbol
			s = ffmpeg
			metas = s.split 'Metadata:'
			metas.shift
			unless metas.empty?
				sym_str = symbol.id2name
				metas.each do |meta|
					lines = meta.split "\n"
					lines.shift if lines.first.strip.empty?
					first_line = lines.first
					pad = first_line.match(/([\s]+)[\S]/)[1]
					lines.each do |line|
						break unless line.start_with? pad
						pair = line.split(':').map { |s| s.strip }
						return pair.last if pair.first == sym_str
					end
				end
			end
			''
		end
		def _info symbol
			result = Job.get_info @path, symbol.id2name
			#puts "_info: #{symbol} #{result}"
			result
		end
	end
end