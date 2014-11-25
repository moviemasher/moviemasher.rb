
module MovieMasher

	class Clip < Asset
		TypeAudio = 'audio'
		TypeImage = 'image'
		TypeVideo = 'video'
		TypeTheme = 'theme'
# Returns a new instance.
		def self.create hash = nil
			(hash.is_a?(Clip) ? hash : Clip.new(hash))
		end

# Transfer - Resolves relative URLs.
# Default - Job#base_source
# Types - Just TypeMash.
		def base_source
			_get __method__
		end
		
		def duration
			_get __method__
		end
# Float - Seconds of Clip available for presentation.
# Default - Probed from downloaded.
# Types - All except TypeImage.
		def duration=(value)
			_set __method__, value
		end
		
		def error?
			nil
		end
		
		
		def length
			_get __method__
		end
# Float - Seconds the Clip appears in the mashup.
# Default - #duration - #offset
		def length=(value)
			_set __method__, value
		end
		
		def loop
			_get __method__
		end
# Integer - Number of times to loop Clip. 
# Types - Just TypeAudio.
		def loop=(value)
			_set __method__, value
		end

# Transfer - Resolves relative font URLs for modules.
# Default - Job#module_source
# Types - Just TypeMash.
		def module_source
			_get __method__
		end

		def start
			_get __method__
		end
# Float - Seconds from start of mashup to introduce the Clip.
# Default - -1.0 means after previous audio in mashup completes.
# Types - Just TypeAudio.
		def start=(value)
			_set __method__, value
		end
		
	end
end