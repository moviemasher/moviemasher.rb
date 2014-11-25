
module MovieMasher
# An element in Job#inputs representing media to be included in the mashup, 
# which is eventually rendered into each Output format and uploaded. Inputs are 
# generally combined together in the order they appear, though audio can be 
# mixed by specifying #start times. 
# 
# There are four types of inputs: TypeAudio, TypeImage and TypeVideo (the three 
# raw types) plus TypeMash, which allows a Mash to be included like normal 
# audio/video. Mashes can be generated in a web browser utilizing 
# {moviemasher.js}[https://github.com/moviemasher/moviemasher.js] or 
# {angular-moviemasher}[https://github.com/moviemasher/angular-moviemasher] 
# and can include raw elements composited on multiple tracks along with titling, 
# effects and transformations over time.
#
# Relevant keys depend on #type, though all inputs have #av, #source and #length 
# keys. After downloading, relevant inputs are probed and will have their 
# #duration set if it's not already. The #no_audio or #no_video keys might 
# change to, as well as #av which relies on them (for instance, from AV::Both to 
# AV::Video for a video that is found to contain no audio track). 
#
#   Input.create {
#   	:type => Input::TypeVideo,
#   	:source => 'video.mp4',
#   	:fill => 'crop',        # remove pixels outside output's aspect ratio
#   	:gain => 0.8,           # reduce volume by 20%
#   	:offset => 10,          # remove first ten seconds
#   	:length => 50,          # remove everything after the first minute 
#   }
#
	class Input < Asset
		TypeAudio = 'audio'
		TypeImage = 'image'
		TypeMash = 'mash'
		TypeVideo = 'video'
# Returns a new instance.
		def self.create hash = nil
			(hash.is_a?(Input) ? hash : Input.new(hash))
		end
		
		def self.init_hash input
			__init_time input, :offset
			Hashable._init_key input, :start, FloatUtil::NegOne
			Hashable._init_key input, :duration, FloatUtil::Zero
			Hashable._init_key(input, :length, 1.0) if Input::TypeImage == input[:type]
			__init_time input, :length # ^ image will already be one by default, others zero
			input[:base_source] = Transfer.create_if input[:base_source]
			input[:module_source] = Transfer.create_if input[:module_source]
			
			Mash.init_input input
			#puts "Input.init_hash #{input}"
			input
			#Input.create input
		end
		
		def self.__init_time input, key
			if input[key] then
				if input[key].is_a? String then
					input["#{key.id2name}_is_relative".to_sym] = '%'
					input[key]['%'] = ''
				end
				input[key] = input[key].to_f
				if FloatUtil.gtr(FloatUtil::Zero, input[key]) then
					input["#{key.id2name}_is_relative".to_sym] = '-'
					input[key] = FloatUtil::Zero - input[key]
				end
			else 
				input[key] = FloatUtil::Zero
			end
		end


# Transfer - Resolves relative URLs.
# Default - Job#base_source
# Types - Just TypeMash.
		def base_source
			_get __method__
		end

		def fill
			_get __method__
		end
# String - How to size in relation to Output#dimensions.
# Constant - Fill::Crop, Fill::None, Fill::Scale or Fill::Stretch.
# Default - Fill::Stretch.
# Types - TypeImage and TypeVideo.
		def fill=(value)
			_set __method__, value
		end
		
		def initialize hash = nil
			#puts "Input#initialize #{hash}"
			self.class.init_hash hash
			super
		end
		def length
			_get __method__
		end
# Float - Seconds the input appears in the mashup.
# Default - #duration - #offset
		def length=(value)
			_set __method__, value
		end

		def mash
			_get __method__
		end
# Mash - The mash to include in rendering.
# Default - nil
# Types - Just TypeMash.
		def mash=(value)
			_set __method__, value
		end

# Transfer - Resolves relative font URLs for modules.
# Default - Job#module_source
# Types - Just TypeMash.
		def module_source
			_get __method__
		end
		
		def offset
			_get __method__
		end
# Float - Seconds to remove from beginning of input.
# Default - 0.0 means nothing removed.
# Types - TypeAudio and TypeVideo.
		def offset=(value)
			_set __method__, value
		end
		def preflight job = nil
			super
			mash.preflight job if mash
		end
		def start
			_get __method__
		end
# Float - Seconds from start of mashup to introduce the input.
# Default - -1.0 means after previous audio in mashup completes.
# Types - Just TypeAudio.
		def start=(value)
			_set __method__, value
		end
		
	end
end