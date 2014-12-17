
module MovieMasher
# Represents a single rendered version of the mashup, including all formatting 
# parameters and quality settings. 
#
# There are five types of outputs: TypeAudio, TypeImage and TypeVideo (the three 
# raw types) as well as TypeSequence which outputs a folder full of image files 
# from the video in the mashup, and TypeWaveform which outputs an image file 
# from the audio in the mashup. 
#
# If outputs need to be uploaded to different locations then each should have 
# its own #destination, otherwise they will all share Job#destination. Typically 
# #name is set to define the filename that's ultimately uploaded, but this can 
# be overridden by #destination. It's important to set #extension regardless 
# though since this generally determines the container format used during 
# rendering. 
# 
# By default outputs are optional, unless #required is true. Optional outputs will 
# not halt job processing if there's a problem rendering them. Instead of setting 
# Job#error the problem is added to Job#log as a warning. 
#
#   Output.create {
#   	:type => Input::TypeVideo,
#   	:name => "video.mp4",                       # extension implies format
#   	:dimensions => "512x288",                   # ffmpeg -s switch
#   	:video_rate => 30,                          # ffmpeg -r:v switch
#   	:video_codec => "libx264 -preset medium",   # ffmpeg -c:v switch
#   	:video_bitrate => "2000K",                  # ffmpeg -b:v switch
#   }

	class Output < Hashable
		TypeAudio = 'audio'
		TypeImage = 'image'
		TypeSequence = 'sequence'
		TypeVideo = 'video'
		TypeWaveform = 'waveform'
# Returns a new instance.
		def self.create hash = nil
			(hash.is_a?(Output) ? hash : Output.new(hash))
		end
		def self.init_hash output
			Hashable._init_key output, :type, Output::TypeVideo
			output[:av] = __av_type_for_output output
			Hashable._init_key output, :name, (Output::TypeSequence == output[:type] ? '' : output[:type])	
			case output[:type]
			when Output::TypeVideo
				Hashable._init_key output, :audio_bitrate, 224
				Hashable._init_key output, :audio_codec, 'aac -strict experimental'
				Hashable._init_key output, :audio_rate, 44100
				Hashable._init_key output, :backcolor, 'black'
				Hashable._init_key output, :dimensions, '512x288'
				Hashable._init_key output, :extension, 'mp4'
				Hashable._init_key output, :fill, Fill::None
				Hashable._init_key output, :video_rate, 30
				Hashable._init_key output, :gain, Gain::None
				Hashable._init_key output, :precision, 1
				Hashable._init_key output, :video_bitrate, 2000
				Hashable._init_key output, :video_codec, 'libx264 -level 41 -movflags faststart'
			when Output::TypeSequence
				Hashable._init_key output, :backcolor, 'black'
				Hashable._init_key output, :video_rate, 10
				Hashable._init_key output, :extension, 'jpg'
				Hashable._init_key output, :dimensions, '256x144'
				Hashable._init_key output, :quality, 1
				output[:no_audio] = true
			when Output::TypeImage
				Hashable._init_key output, :video_rate, 1
				Hashable._init_key output, :backcolor, 'black'
				Hashable._init_key output, :quality, 1						
				Hashable._init_key output, :extension, 'jpg'
				Hashable._init_key output, :dimensions, '256x144'
				output[:no_audio] = true
			when Output::TypeAudio
				Hashable._init_key output, :audio_bitrate, 224
				Hashable._init_key output, :precision, 0
				Hashable._init_key output, :audio_codec, 'libmp3lame'
				Hashable._init_key output, :extension, 'mp3'
				Hashable._init_key output, :audio_rate, 44100
				Hashable._init_key output, :gain, Gain::None
				output[:no_video] = true
			when Output::TypeWaveform
				Hashable._init_key output, :backcolor, 'FFFFFF'
				Hashable._init_key output, :precision, 0
				Hashable._init_key output, :dimensions, '8000x32'
				Hashable._init_key output, :forecolor, '000000'
				Hashable._init_key output, :extension, 'png'
				output[:no_video] = true
			end
			output
		end
		def self.__av_type_for_output output
			case output[:type]
			when Output::TypeAudio, Output::TypeWaveform
				AV::Audio
			when Output::TypeImage, Output::TypeSequence
				AV::Video
			when Output::TypeVideo
				AV::Both
			end
		end

		def audio_bitrate
			_get __method__
		end
# String - FFmpeg -b:a switch, placed before #audio_rate. 
# Integer - The character 'k' will be appended.
# Default - 224
# Types - TypeAudio, TypeWaveform and TypeVideo containing audio.
		def audio_bitrate=(value)
			_set __method__, value
		end
		
		def audio_codec
			_get __method__
		end
# String - FFmpeg -c:a switch, placed after #audio_rate. 
# Default - aac -strict experimental
# Types - TypeAudio, TypeWaveform and TypeVideo containing audio.
		def audio_codec=(value)
			_set __method__, value
		end
		
		def audio_rate
			_get __method__
		end
# String - FFmpeg -r:a switch, placed after #audio_bitrate and before #audio_codec. 
# Default - 44100
# Types - TypeAudio, TypeWaveform and TypeVideo containing audio.
		def audio_rate=(value)
			_set __method__, value
		end
		
# String - The AV type.
# Constant - AV::Audio, AV::Video or AV::Both. 
# Default - Based on #type and #no_audio.
		def av
			_get __method__
		end
		
		def backcolor
			_get __method__
		end
# String - Six character hex, rgb(0,0,0) or standard color name.
# Default - FFFFFF for TypeWaveform, black for others.
# Types - All except TypeAudio, but TypeWaveform only accepts hex colors.

		def backcolor=(value)
			_set __method__, value
		end
		
		def destination
			_get __method__
		end
# Transfer - Describes where to upload this output.
# Default - Job#destination
		def destination=(value)
			_set __method__, value
		end

		def dimensions
			_get __method__
		end
# String - Output pixel size formatted as WIDTHxHEIGHT.
# Default - 512x288 for TypeVideo, 8000x32 for TypeWaveform and 256x144 for others. 
# Types - All except TypeAudio.
		def dimensions=(value)
			_set __method__, value
		end
		
		def error?	
			err = nil
			err = destination.error? if destination
			unless err
				err = "output name contains slash - use path instead #{name}" if name.to_s.include? '/'
			end		
			err
		end
			
		def extension
			_get __method__
		end
# String - Extension for rendered file, also implies format.
# Default - Removed from #name if present, otherwise mp4 for TypeVideo, mp3 for TypeAudio, png for TypeWaveform and jpg for others.
		def extension=(value)
			_set __method__, value
		end
		def file_name
			fn = Path.strip_slashes name
			fn += '.' + extension if extension
			fn
		end
		
		def forecolor
			_get __method__
		end
# String - Six character Hex color.
# Default - 000000
# Types - Only TypeWaveform.
		def forecolor=(value)
			_set __method__, value
		end
		
		def initialize hash 
			self.class.init_hash hash
			super
		end
		
		def metadata
			(self[:rendered_file] ? MetaReader.new(self[:rendered_file]) : Hash.new)
		end

		def name
			_get __method__
		end
# String - Basename for rendered file.
# Default - #type, or empty for TypeSequence.
# Types - All, but TypeSequence will append the frame number to each image file. 
		def name=(value)
			_set __method__, value
		end

		def no_audio
			_get __method__
		end
# Boolean - If true, audio in inputs will not be included.
# Default - FALSE
# Types - Just TypeVideo, but accessible for others.
		def no_audio=(value)
			_set __method__, value
		end
		
		def path
			_get __method__
		end
# String - Prepended to #name during upload.
# Default - empty
		def path=(value)
			_set __method__, value
		end

		def precision
			_get __method__
		end
# Integer - Number of decimal places that Job#duration and #duration must match by for successful rendering. 
# Default - 1 for TypeVideo, 0 for others.
# Types - TypeVideo, TypeAudio, TypeWaveform (TypeSequence copies last frame repeatedly to match). 
		def precision=(value)
			_set __method__, value
		end
		
		def preflight job
			self.destination = Destination.create_if destination # must say self. = here
			unless extension # try to determine from name if it has one
				output_name_extension = File.extname name
				if output_name_extension and not output_name_extension.empty?
					self.name = File.basename name, output_name_extension
					extension = output_name_extension.delete '.'
				end
			end
		end

		def quality
			_get __method__
		end
# Integer - FFmpeg -q:v switch, 1 (best) to 32 (worst).
# Default - 1
# Types - TypeImage and TypeSequence.
		def quality=(value)
			_set __method__, value
		end
	
		def required
			_get __method__
		end
# Boolean - Whether or not Job should halt if output cannot be rendered or uploaded.
# Default - nil
		def required=(value)
			_set __method__, value
		end
		
		def type
			_get __method__
		end
# String - The kind of output.
# Constant - TypeAudio, TypeImage, TypeSequence, TypeVideo or TypeWaveform.
# Default - TypeVideo.
		def type=(value)
			_set __method__, value
		end

		def video_bitrate
			_get __method__
		end
# String - FFmpeg -b:v switch, placed after #video_codec and before #video_rate. 
# Integer - The character 'k' will be appended.
# Default - 2000
# Types - Only TypeVideo.
		def video_bitrate=(value)
			_set __method__, value
		end
		
		def video_codec
			_get __method__
		end
# String - FFmpeg -c:v switch, placed after #video_format and before #video_bitrate. 
# Default - libx264 -level 41 -movflags faststart
# Types - Only TypeVideo.
		def video_codec=(value)
			_set __method__, value
		end
		
		def video_format
			_get __method__
		end
# String - FFmpeg -f:v switch, placed after #dimensions and before #video_codec. 
# Default - nil
# Types - Only TypeVideo.
		def video_format=(value)
			_set __method__, value
		end

		def video_rate
			_get __method__
		end
# String - FFmpeg -r:v switch, placed after #video_bitrate. 
# Default - 30
# Types - TypeSequence and TypeVideo.
		def video_rate=(value)
			_set __method__, value
		end
		
	end
end