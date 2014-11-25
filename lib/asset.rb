
module MovieMasher

	class Asset < Hashable
		TypeAudio = 'audio'
		TypeImage = 'image'
		TypeMash = 'mash'
		TypeVideo = 'video'
# Returns a new instance.
		def self.create hash = nil
			(hash.is_a?(Asset) ? hash : Asset.new(hash))
		end

		def self.av_type input
			case input[:type]
			when Input::TypeAudio
				AV::Audio
			when Mash::Image, Mash::Font, Mash::Frame
				AV::Video
			when Input::TypeVideo, Input::TypeMash
				(input[:no_audio] ? AV::Video : input[:no_video] ? AV::Audio : AV::Both)
			end
		end

	

# String - The AV type.
# Constant - AV::Audio, AV::Video, AV::Both, or AV::Neither if an error was encountered while probing. 
# Types - All, but TypeMash reflects its nested elements. 
# Default - Initially based on #type and #no_audio, but might change after probing.
		def av
			_get __method__
		end

		def dimensions
			_get __method__
		end
# String - WIDTHxHEIGHT of element.
# Default - Probed from downloaded.
# Types - TypeImage and TypeVideo.
		def dimensions=(value)
			_set __method__, value
		end
		
		def duration
			_get __method__
		end
# Float - Seconds of Asset available for presentation.
# Default - Probed from downloaded.
# Types - All except TypeImage.
		def duration=(value)
			_set __method__, value
		end
		
		def error?
			nil
		end
		
		def gain
			_get __method__
		end
# Float - Multiplier to adjust volume of audio when mixed into mashup. 
# Array - Duple Float values signifying element offset and multiplier for arbitrary volume fading over time. For instance, [0.0, 0.0, 0.1, 1.0, 0.9, 1.0, 1.0, 0.0] would fade volume in over the first 10% of the element's length and out over the last 10%.
# Default - Gain::None (1.0) means no change in volume.
# Types - TypeAudio and TypeVideo.
		def gain=(value)
			_set __method__, value
		end
		
		def length
			_get __method__
		end
# Float - Seconds the Asset appears in the mashup.
# Default - #duration - #offset
		def length=(value)
			_set __method__, value
		end
		
		def loop
			_get __method__
		end
# Integer - Number of times to loop Asset. 
# Types - Just TypeAudio.
		def loop=(value)
			_set __method__, value
		end
		
		def no_audio
			_get __method__
		end
# Boolean - If true, audio in Asset will be ignored.
# Default - Initially based on #type, but could change after probing.
# Types - TypeMash and TypeVideo, but accessible for others.
		def no_audio=(value)
			_set __method__, value
		end

		def no_video
			_get __method__
		end
# Boolean - If true, video in Asset will be ignored.
# Default - Initially based on #type, but could change after probing.
# Types - TypeMash and TypeVideo, but accessible for others.
		def no_video=(value)
			_set __method__, value
		end

		def offset
			_get __method__
		end
# Float - Seconds to remove from beginning of Asset.
# Default - 0.0 means nothing removed.
# Types - TypeAudio and TypeVideo.
		def offset=(value)
			_set __method__, value
		end
		
		def preflight job = nil
			if source then
				self.source = Source.create_if source
				if job
					base_src = base_source || job.base_source
					module_src = module_source || job.module_source
					
					self[:input_url] = url(base_src, module_src) unless TypeMash == type and @hash[:mash]
				end
			end
			#puts "preflight #{self.class.name} URL: #{self[:input_url]}"
		end
		
		def source
			s = _get __method__
			s
		end
		
# Describes the download request for the element, as either a URL or 
# Hash/Source. If the URL is relative it's based from Job#base_source. Assets of 
# TypeMash can point to anything that responds with a JSON formatted mash. After 
# download they will pass the parsed Hash to Mash.new and reset their #source to 
# the returned instance. Alternatively, #source can be initially set to a 
# Hash/Mash so as to avoid download.
#
# String - A HTTP or HTTPS URL to element, converted to appropriate Source. 
# Hash - Can describe either a download request or, for TypeMash Assets, a JSON formatted Mash. The former is sent to Source.create while the later is sent to Mash.new. 
# Returns - A Source object or, for TypeMash Assets after downloading, a Mash object.
		def source=(value)
			_set __method__, value
		end
		
		def type
			_get __method__
		end
# String - The kind of Asset.
# Constant - TypeAudio, TypeImage, TypeMash or TypeVideo.
# Default - Probed from downloaded.
		def type=(value)
			_set __method__, value
		end
		
		def url base_src = nil, module_src = nil
			u = nil
			if source and source.is_a?(Source) 
				u = source.url
				if source.relative?
					# relative url
					case type
					when Mash::Theme, Mash::Font, Mash::Effect
						base_src = module_src if module_src
					end
					if base_src then
						base_url = base_src.url
						base_url = Path.add_slash_end base_url
						u = Path.strip_slash_start u
						if Transfer::TypeFile == base_src[:type]
							u = Path.concat base_url, u
						else
							u = URI.join(base_url, u).to_s
						end
					end
				end
			end
			#puts "#{self.class.name}#url URL: #{u}"
			u
		end
	end
end