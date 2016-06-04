
module MovieMasher
  # Represents a single rendered version of the mashup, including all formatting
  # parameters and quality settings.
  #
  # There are five types of outputs: Type::AUDIO, Type::IMAGE and Type::VIDEO
  # (the three raw types) as well as Type::SEQUENCE which outputs a folder full
  # of image files from the video in the mashup, and Type::WAVEFORM which
  # outputs an image file from the audio in the mashup.
  #
  # If outputs need to be uploaded to different locations then each should have
  # its own #destination, otherwise they will all share Job#destination.
  # Typically
  # #name is set to define the filename that's ultimately uploaded, but this can
  # be overridden by #destination. It's important to set #extension regardless
  # though since this generally determines the container format used during
  # rendering.
  #
  # By default outputs are optional, unless #required is true. Optional outputs
  # will not halt job processing if there's a problem rendering them. Instead of
  # setting Job#error the problem is added to Job#log as a warning.
  #
  #   Output.create {
  #     type: Type::VIDEO,
  #     name: "video.mp4",                       # extension implies format
  #     dimensions: "512x288",                   # ffmpeg -s switch
  #     video_rate: 30,                          # ffmpeg -r:v switch
  #     video_codec: "libx264 -preset medium",   # ffmpeg -c:v switch
  #     video_bitrate: "2000K",                  # ffmpeg -b:v switch
  #   }
  class Output < Hashable
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Output) ? hash : Output.new(hash))
    end
    def self.init_hash(output)
      Hashable._init_key output, :type, Type::VIDEO
      output[:av] = __av_type_for_output(output)
      output_type = (Type::SEQUENCE == output[:type] ? '' : output[:type])
      Hashable._init_key output, :name, output_type
      case output[:type]
      when Type::VIDEO
        Hashable._init_key output, :audio_bitrate, 224
        Hashable._init_key output, :audio_codec, 'aac'
        Hashable._init_key output, :audio_rate, 44_100
        Hashable._init_key output, :backcolor, 'black'
        Hashable._init_key output, :dimensions, '512x288'
        Hashable._init_key output, :extension, 'mp4'
        Hashable._init_key output, :fill, Fill::NONE
        Hashable._init_key output, :video_rate, 30
        Hashable._init_key output, :gain, Gain::None
        Hashable._init_key output, :precision, 1
        Hashable._init_key output, :video_bitrate, 2_000
        lib_264 = 'libx264 -level 41 -movflags faststart'
        Hashable._init_key output, :video_codec, lib_264
      when Type::SEQUENCE
        Hashable._init_key output, :backcolor, 'black'
        Hashable._init_key output, :video_rate, 10
        Hashable._init_key output, :extension, 'jpg'
        Hashable._init_key output, :dimensions, '256x144'
        Hashable._init_key output, :quality, 1
        output[:no_audio] = true
      when Type::IMAGE
        Hashable._init_key output, :video_rate, 1
        Hashable._init_key output, :backcolor, 'black'
        Hashable._init_key output, :quality, 1
        Hashable._init_key output, :extension, 'jpg'
        Hashable._init_key output, :dimensions, '256x144'
        Hashable._init_time output, :offset
        output[:no_audio] = true
      when Type::AUDIO
        Hashable._init_key output, :audio_bitrate, 224
        Hashable._init_key output, :precision, 0
        Hashable._init_key output, :audio_codec, 'libmp3lame'
        Hashable._init_key output, :extension, 'mp3'
        Hashable._init_key output, :audio_rate, 44_100
        Hashable._init_key output, :gain, Gain::None
        output[:no_video] = true
      when Type::WAVEFORM
        Hashable._init_key output, :backcolor, 'FFFFFF'
        Hashable._init_key output, :precision, 0
        Hashable._init_key output, :dimensions, '8000x32'
        Hashable._init_key output, :forecolor, '000000'
        Hashable._init_key output, :extension, 'png'
        output[:no_video] = true
      end
      output
    end
    def self.sequence_complete(output)
      dir_path = output[:rendered_file]
      ok = false
      if File.directory?(dir_path)
        first_frame = 1
        frame_count = (output[:video_rate].to_f * output[:duration]).floor.to_i
        padding = (first_frame + frame_count).to_s.length
        last_file = nil
        frame_count.times do |frame_number|
          ok = true
          file_frame = frame_number + first_frame
          f_name = "#{output[:name]}#{file_frame.to_s.rjust(padding, '0')}"
          file_path = Path.concat(dir_path, "#{f_name}.#{output[:extension]}")
          if File.exist?(file_path)
            last_file = file_path
          elsif last_file
            FileUtils.copy(last_file, file_path)
          else
            ok = false
            break
          end
        end
      end
      ok
    end
    def self.__av_type_for_output(output)
      case output[:type]
      when Type::AUDIO, Type::WAVEFORM
        AV::AUDIO_ONLY
      when Type::IMAGE, Type::SEQUENCE
        AV::VIDEO_ONLY
      when Type::VIDEO
        AV::BOTH
      end
    end
    def audio_bitrate
      _get __method__
    end
    # String - FFmpeg -b:a switch, placed before #audio_rate.
    # Integer - The character 'k' will be appended.
    # Default - 224
    # Types - Type::AUDIO, Type::WAVEFORM and Type::VIDEO containing audio.
    def audio_bitrate=(value)
      _set __method__, value
    end
    def audio_codec
      _get __method__
    end
    # String - FFmpeg -c:a switch, placed after #audio_rate.
    # Default - aac -strict experimental
    # Types - Type::AUDIO, Type::WAVEFORM and Type::VIDEO containing audio.
    def audio_codec=(value)
      _set __method__, value
    end
    def audio_rate
      _get __method__
    end
    # String - FFmpeg -r:a switch, placed between #audio_bitrate & #audio_codec.
    # Default - 44_100
    # Types - Type::AUDIO, Type::WAVEFORM and Type::VIDEO containing audio.
    def audio_rate=(value)
      _set __method__, value
    end
    # String - The AV type.
    # Constant - AV::AUDIO_ONLY, AV::VIDEO_ONLY or AV::BOTH.
    # Default - Based on #type and #no_audio.
    def av
      _get __method__
    end
    def backcolor
      _get __method__
    end
    # String - Six character hex, rgb(0,0,0) or standard color name.
    # Default - FFFFFF for Type::WAVEFORM, black for others.
    # Types - All except Type::AUDIO, but Type::WAVEFORM only accepts hex.
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
    # Default - 512x288 for Type::VIDEO, 8000x32 for Type::WAVEFORM, or 256x144.
    # Types - All except Type::AUDIO.
    def dimensions=(value)
      _set __method__, value
    end
    def error?
      err = nil
      err = destination.error? if destination
      unless err
        if name.to_s.include? '/'
          err = "output name contains slash - use path instead #{name}"
        end
      end
      err
    end
    def extension
      _get __method__
    end
    # String - Extension for rendered file, also implies format.
    # Default - Removed from #name if present, otherwise mp4 for Type::VIDEO,
    # mp3 for Type::AUDIO, png for Type::WAVEFORM and jpg for others.
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
    # Types - Only Type::WAVEFORM.
    def forecolor=(value)
      _set __method__, value
    end
    def initialize(hash)
      self.class.init_hash hash
      super
    end
    def metadata
      (self[:rendered_file] ? MetaReader.new(self[:rendered_file]) : {})
    end
    def name
      _get __method__
    end
    # String - Basename for rendered file.
    # Default - #type, or empty for Type::SEQUENCE.
    # Types - All, but Type::SEQUENCE appends the frame number to each file.
    def name=(value)
      _set __method__, value
    end
    def no_audio
      _get __method__
    end
    # Boolean - If true, audio in inputs will not be included.
    # Default - FALSE
    # Types - Just Type::VIDEO, but accessible for others.
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
    # Integer - Number of decimal places that Job#duration and #duration must
    # match by for successful rendering - use negative number to skip duration
    # check.
    # Default - 1 for Type::VIDEO, 0 for others.
    # Types - Type::VIDEO, Type::AUDIO, Type::WAVEFORM (Type::SEQUENCE copies
    # last frame repeatedly to match).
    def precision=(value)
      _set __method__, value
    end
    def preflight(_job)
      self.destination = Destination.create_if destination # must say self. =
      unless extension
        # try to determine from name if it has one
        output_name_extension = File.extname name
        unless output_name_extension.to_s.empty?
          self.name = File.basename(name, output_name_extension)
          self.extension = output_name_extension.delete('.')
        end
      end
    end
    def quality
      _get __method__
    end
    # Integer - FFmpeg -q:v switch, 1 (best) to 32 (worst).
    # Default - 1
    # Types - Type::IMAGE and Type::SEQUENCE.
    def quality=(value)
      _set __method__, value
    end
    def required
      _get __method__
    end
    # Boolean - Whether or not Job should halt if output fails render or upload.
    # Default - nil
    def required=(value)
      _set __method__, value
    end
    def type
      _get __method__
    end
    # String - The kind of output.
    # Constant - Type::AUDIO, Type::IMAGE, Type::SEQUENCE, Type::VIDEO or
    # Type::WAVEFORM.
    # Default - Type::VIDEO.
    def type=(value)
      _set __method__, value
    end
    def video_bitrate
      _get __method__
    end
    # String - FFmpeg -b:v switch, placed between #video_codec & #video_rate.
    # Integer - The character 'k' will be appended.
    # Default - 2000
    # Types - Only Type::VIDEO.
    def video_bitrate=(value)
      _set __method__, value
    end
    def video_codec
      _get __method__
    end
    # String - FFmpeg -c:v switch, between #video_format & #video_bitrate.
    # Default - libx264 -level 41 -movflags faststart
    # Types - Only Type::VIDEO.
    def video_codec=(value)
      _set __method__, value
    end
    def video_format
      _get __method__
    end
    # String - FFmpeg -f:v switch, placed between #dimensions & #video_codec.
    # Default - nil
    # Types - Only Type::VIDEO.
    def video_format=(value)
      _set __method__, value
    end
    def video_rate
      _get __method__
    end
    # String - FFmpeg -r:v switch, placed after #video_bitrate.
    # Default - 30
    # Types - Type::SEQUENCE and Type::VIDEO.
    def video_rate=(value)
      _set __method__, value
    end
  end
end
