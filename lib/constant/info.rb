
module MovieMasher
  # get and set meta information about a file
  module Info
    AT = 'at'.freeze
    AUDIO = 'audio'.freeze
    AUDIO_DURATION = 'audio_duration'.freeze
    DIMENSIONS = 'dimensions'.freeze
    DOWNLOADED = 'downloaded'.freeze
    DURATION = 'duration'.freeze
    EXTENSION = 'txt'.freeze
    FPS = 'fps'.freeze
    TYPE = 'type'.freeze
    VIDEO_DURATION = 'video_duration'.freeze
    DURATION_REGEX = /Duration\s*:\s*([\d]+):([\d]+):([\d\.]+)/
    FPS_REGEX = / ([\d\.]+) fps/
    FPS_TB_REGEX = / ([\d\.]+) tb/
    AUDIO_REGEX = /Audio: ([^,]+),/
    DIMENSIONS_REGEX = /, ([\d]+)x([\d]+)/
    def self.get(path, type)
      result = nil
      __raise_if_empty(path, type)
      if File.size?(path)
        meta = meta_path(type, path)
        result = (File.exist?(meta) ? File.read(meta) : __get(path, type))
      end
      result
    end
    def self.__get(path, type)
      result = nil
      check = {}
      case type
      when 'ffmpeg', 'sox'
        check[type.to_sym] = true
      when TYPE, 'http'
        # do nothing if file doesn't already exist
      when DIMENSIONS
        check[:ffmpeg] = true
      when VIDEO_DURATION
        check[:ffmpeg] = true
        type = DURATION
      when AUDIO_DURATION
        check[:sox] = true
        type = DURATION
      when DURATION
        check[__app_for_path(path)] = true
      when FPS, AUDIO # only from FFMPEG
        check[:ffmpeg] = true
      end
      if check[:ffmpeg]
        result = __check_ffmpeg(path, type)
      elsif check[:sox]
        result = __check_sox(path, type)
      end
      set_if(path, type, result)
      result
    end
    def self.__raise_if_empty(path, type)
      if type.to_s.empty? || path.to_s.empty?
        raise(Error::Parameter, "path or type empty: #{path}, #{type}")
      end
    end
    def self.__app_for_path(path)
      (AUDIO == type(path) ? :sox : :ffmpeg)
    end
    def self.__check_ffmpeg(path, type)
      result = nil
      data = nil
      data = get(path, 'ffmpeg') if 'ffmpeg' != type
      unless data
        data = ShellHelper.execute(command: path, app: 'ffprobe')
        if 'ffmpeg' == type
          result = data
          data = nil
        else
          set(path, 'ffmpeg', data)
        end
      end
      result = parse(type, data) if data
      result
    end
    def self.set_if(path, type, result)
      set(path, type, result) if result
    end
    def self.__check_sox(path, type)
      result = nil
      data = nil
      data = get(path, 'sox') if 'sox' != type
      unless data
        data = ShellHelper.execute(command: "--i #{path}", app: 'sox')
        if 'sox' == type
          result = data
          data = nil
        else
          set(path, 'sox', data)
        end
      end
      result = parse(type, data) if data
      result
    end
    def self.meta_path(type, path)
      file_name = "#{File.basename(path, '.*')}.#{type}.#{EXTENSION}"
      Path.concat(File.dirname(path), file_name)
    end
    def self.parse(type, ffmpeg_output)
      result = nil
      unless ffmpeg_output.to_s.empty?
        case type
        when AUDIO
          AUDIO_REGEX.match(ffmpeg_output) do |match|
            result = 1 if 'none' != match[1]
          end
        when DIMENSIONS
          DIMENSIONS_REGEX.match(ffmpeg_output) do |match|
            result = match[1] + 'x' + match[2]
          end
        when DURATION
          DURATION_REGEX.match(ffmpeg_output) do |match|
            result = 60 * 60 * match[1].to_i
            result += 60 * match[2].to_i
            result = result.to_f + match[3].to_f
          end
        when FPS
          match = FPS_REGEX.match(ffmpeg_output)
          match = FPS_TB_REGEX.match(ffmpeg_output) unless match
          result = match[1].to_f.round
        end
      end
      result
    end
    def self.set(path, type, data)
      if type && path
        File.open(meta_path(type, path), 'w') { |f| f.write(data) }
      end
      data
    end
    def self.type(path)
      result = nil
      if path
        result = get(path, 'type')
        unless result
          mime = get(path, 'Content-Type')
          mime = __mime(path) unless mime
          result = mime.split('/').shift if mime
          set(path, 'type', result) if result
        end
      end
      result
    end
    def self.__mime(path)
      type = MIME::Types.of(path).first
      mime = type.simplified if type
      set(path, 'Content-Type', mime) if mime
      mime
    end
  end
end
