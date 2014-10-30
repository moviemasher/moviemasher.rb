
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
	class Input
		include JobHash
		TypeAudio = 'audio'
		TypeImage = 'image'
		TypeMash = 'mash'
		TypeVideo = 'video'
# Returns a new instance.
		def self.create hash
			Input.new hash
		end
# String - The AV type.
# Constant - AV::Audio, AV::Video, AV::Both, or AV::Neither if an error was encountered while probing. 
# Types - All, but TypeMash reflects its nested elements. 
# Default - Initially based on #type and #no_audio, but might change after probing.
		def av; _get __method__; end

# Transfer - Resolves relative URLs.
# Default - Job#base_source
# Types - Just TypeMash.
		def base_source; _get __method__; end
		
		def dimensions; _get __method__; end
# String - WIDTHxHEIGHT of element.
# Default - Probed from downloaded.
# Types - TypeImage and TypeVideo.
		def dimensions=(value); _set __method__, value; end
		
		def duration; _get __method__; end
# Float - Seconds of input available for presentation.
# Default - Probed from downloaded.
# Types - All except TypeImage.
		def duration=(value); _set __method__, value; end
		
		def fill; _get __method__; end
# String - How to size in relation to Output#dimensions.
# Constant - Fill::Crop, Fill::None, Fill::Scale or Fill::Stretch.
# Default - Fill::Stretch.
# Types - TypeImage and TypeVideo.
		def fill=(value); _set __method__, value; end
		
		def gain; _get __method__; end
# Float - Multiplier to adjust volume of audio when mixed into mashup. 
# Array - Duple Float values signifying element offset and multiplier for arbitrary volume fading over time. For instance, [0.0, 0.0, 0.1, 1.0, 0.9, 1.0, 1.0, 0.0] would fade volume in over the first 10% of the element's length and out over the last 10%.
# Default - Gain::None (1.0) means no change in volume.
# Types - TypeAudio and TypeVideo.
		def gain=(value); _set __method__, value; end
		
		def length; _get __method__; end
# Float - Seconds the input appears in the mashup.
# Default - #duration - #offset
		def length=(value); _set __method__, value; end
		
		def loop; _get __method__; end
# Integer - Number of times to loop input. 
# Types - Just TypeAudio.
		def loop=(value); _set __method__, value; end

# Transfer - Resolves relative font URLs for modules.
# Default - Job#module_source
# Types - Just TypeMash.
		def module_source; _get __method__; end
		
		def no_audio; _get __method__; end
# Boolean - If true, audio in input will be ignored.
# Default - Initially based on #type, but could change after probing.
# Types - TypeMash and TypeVideo, but accessible for others.
		def no_audio=(value); _set __method__, value; end

		def no_video; _get __method__; end
# Boolean - If true, video in input will be ignored.
# Default - Initially based on #type, but could change after probing.
# Types - TypeMash and TypeVideo, but accessible for others.
		def no_video=(value); _set __method__, value; end

		def offset; _get __method__; end
# Float - Seconds to remove from beginning of input.
# Default - 0.0 means nothing removed.
# Types - TypeAudio and TypeVideo.
		def offset=(value); _set __method__, value; end
		
		def source; _get __method__; end
# Describes the download request for the element, as either a URL or 
# Hash/Source. If the URL is relative it's based from Job#base_source. Inputs of 
# TypeMash can point to anything that responds with a JSON formatted mash. After 
# download they will pass the parsed Hash to Mash.new and reset their #source to 
# the returned instance. Alternatively, #source can be initially set to a 
# Hash/Mash so as to avoid download.
#
# String - A HTTP or HTTPS URL to element, converted to appropriate Source. 
# Hash - Can describe either a download request or, for TypeMash inputs, a JSON formatted Mash. The former is sent to Source.create while the later is sent to Mash.new. 
# Returns - A Source object or, for TypeMash inputs after downloading, a Mash object.
		def source=(value); _set __method__, value; end
		
		def start; _get __method__; end
# Float - Seconds from start of mashup to introduce the input.
# Default - -1.0 means after previous audio in mashup completes.
# Types - Just TypeAudio.
		def start=(value); _set __method__, value; end
		
		def type; _get __method__; end
# String - The kind of input.
# Constant - TypeAudio, TypeImage, TypeMash or TypeVideo.
# Default - Probed from downloaded.
		def type=(value); _set __method__, value; end
	end
end