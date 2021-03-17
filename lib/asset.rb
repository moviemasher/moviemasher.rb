# frozen_string_literal: true

module MovieMasher
  # represents a downloadable media asset
  class Asset < Hashable
    class << self
      # Returns a new instance.
      def av_type(input)
        case input[:type]
        when Type::AUDIO
          AV::AUDIO_ONLY
        when Type::IMAGE, Type::FONT, Type::FRAME
          AV::VIDEO_ONLY
        when Type::VIDEO, Type::MASH
          if input[:no_audio]
            AV::VIDEO_ONLY
          else
            (input[:no_video] ? AV::AUDIO_ONLY : AV::BOTH)
          end
        end
      end

      def create(hash = nil)
        (hash.is_a?(Asset) ? hash : Asset.new(hash))
      end

      def download_asset(asset, job)
        path = nil
        url = asset[:input_url].to_s
        unless url.empty?
          path = __download_asset(asset, url, job)
          Info.set(path, Info::AT, Time.now.to_i)
          asset[:cached_file] = path
          __populate_asset_info(asset)
        end
        path
      end

      def url_path(url)
        dir = MovieMasher.configuration[:download_directory]
        dir = MovieMasher.configuration[:render_directory] if dir.to_s.empty?
        hex = Digest::SHA2.new(256).hexdigest(url)
        Path.concat(dir, "#{hex}/#{Info::DOWNLOADED}#{File.extname(url)}")
      end

      private

      def __download_asset(asset, url, job)
        path = url_path(url)
        unless File.exist?(path)
          begin
            FileHelper.safe_path(File.dirname(path))
            asset.download(job: job, path: path)
            raise("zero length #{url}") unless File.size?(path)
          rescue StandardError => e
            puts "CAUGHT #{e.is_a?(Error::Job)} #{e.message} #{e.backtrace}"
            raise(Error::JobInput, e.message)
          end
        end
        path
      end

      def __populate_asset_info(asset)
        path = asset[:cached_file]
        case asset[:type]
        when Type::VIDEO
          unless FloatUtil.nonzero(asset[:duration])
            asset[:duration] = Info.get(path, Info::DURATION).to_f
          end
          asset[:no_audio] = !Info.get(path, Info::AUDIO)
          asset[:dimensions] = Info.get(path, Info::DIMENSIONS)
          asset[:no_video] = !asset[:dimensions]
          asset[:av] = Mash.init_av_input(asset)
        when Type::AUDIO
          unless FloatUtil.nonzero(asset[:duration])
            asset[:duration] = Info.get(path, Info::AUDIO_DURATION).to_f
          end
          unless FloatUtil.gtr(asset[:duration], FloatUtil::ZERO)
            asset[:duration] = Info.get(path, Info::VIDEO_DURATION).to_f
          end
        when Type::IMAGE
          asset[:dimensions] = Info.get(path, Info::DIMENSIONS)
          unless asset[:dimensions]
            raise(Error::JobInput, 'could not determine image dimensions')
          end
        end
      end
    end

    # String - The AV type.
    # Constant - AV::AUDIO_ONLY, AV::VIDEO_ONLY, AV::BOTH, or
    #            AV::NEITHER if an error was encountered while probing.
    # Types - All, but Type::MASH reflects its nested elements.
    # Default - Initially based on #type and #no_audio, but might change
    #           after probing.
    def av
      _get __method__
    end

    def dimensions
      _get __method__
    end

    # String - WIDTHxHEIGHT of element.
    # Default - Probed from downloaded.
    # Types - Type::IMAGE and Type::VIDEO.
    def dimensions=(value)
      _set __method__, value
    end

    def download(options)
      d_source = download_source
      service = Service.downloader(d_source.type)
      raise(Error::Configuration, "no service #{d_source.type}") unless service

      options[:source] = d_source
      options[:asset] = self
      service.download(options)
    end

    def download_source
      d_source = source
      if source.is_a?(Source) && source&.relative?
        # relative url
        case type
        when Type::THEME, Type::FONT, Type::EFFECT
          d_source = module_source || base_source || source
        else
          d_source = base_source || source
        end
      end
      d_source
    end

    def duration
      _get __method__
    end

    # Float - Seconds of Asset available for presentation.
    # Default - Probed from downloaded.
    # Types - All except Type::IMAGE.
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
    # Array - Duple Float values signifying element offset and
    #         multiplier for arbitrary volume fading over time. For instance,
    #         [0.0, 0.0, 0.1, 1.0, 0.9, 1.0, 1.0, 0.0] would fade volume in
    #         over the first 10% of the element's length and out over the last
    #         10%.
    # Default - Gain::None (1.0) means no change in volume.
    # Types - Type::AUDIO and Type::VIDEO.
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
    # Types - Just Type::AUDIO.
    def loop=(value)
      _set __method__, value
    end

    def metadata
      (self[:cached_file] ? MetaReader.new(self[:cached_file]) : {})
    end

    def no_audio
      _get __method__
    end

    # Boolean - If true, audio in Asset will be ignored.
    # Default - Initially based on #type, but could change after probing.
    # Types - Type::MASH and Type::VIDEO, but accessible for others.
    def no_audio=(value)
      _set __method__, value
    end

    def no_video
      _get __method__
    end

    # Boolean - If true, video in Asset will be ignored.
    # Default - Initially based on #type, but could change after probing.
    # Types - Type::MASH and Type::VIDEO, but accessible for others.
    def no_video=(value)
      _set __method__, value
    end

    def offset
      _get __method__
    end

    # Float - Seconds to remove from beginning of Asset.
    # Default - 0.0 means nothing removed.
    # Types - Type::AUDIO and Type::VIDEO.
    def offset=(value)
      _set __method__, value
    end

    def preflight(job = nil)
      return unless source

      self.source = Source.create_if source
      return unless job

      self[:base_source] = job.base_source unless base_source
      self[:module_source] = job.module_source unless module_source
      # puts "base_source: #{base_source}"
      return if Type::MASH == type && @hash[:mash]

      self[:input_url] = url(base_source, module_source)
      # puts "preflight #{self.class.name} URL: #{self[:input_url]}"
    end

    def source
      _get __method__
    end

    # Describes the download request for the element, as either a URL or
    # Hash/Source. If the URL is relative it's based from job's 
    # base_source. Assets of Type::MASH can point to anything that
    # responds with a JSON formatted mash. After download they will pass
    # the parsed Hash to Mash.new and reset their #source to the
    # returned instance. Alternatively, #source can be initially set to
    # a Hash/Mash so as to avoid download.
    #
    # String - A HTTP or HTTPS URL to element, converted to appropriate Source.
    # Hash - Can describe either a download request or, for Type::MASH
    #        Assets, a JSON formatted Mash. The former is sent to Source.create
    #        while the later is sent to Mash.new.
    # Returns - A Source object or, for Type::MASH Assets after
    #           downloading, a Mash object.
    def source=(value)
      _set __method__, value
    end

    def type
      _get __method__
    end

    # String - The kind of Asset.
    # Constant - Type::AUDIO, Type::IMAGE, Type::MASH or Type::VIDEO.
    # Default - Probed from downloaded.
    def type=(value)
      _set __method__, value
    end

    def url(base_src = nil, module_src = nil)
      return unless source.is_a?(Source)

      source_url = source.url
      if source.relative?
        base_src = module_src if module_src && Type::MODULES.include?(type)
        if base_src
          base_url = base_src.url
          base_url = Path.add_slash_end base_url
          source_url = Path.strip_slash_start(source_url)
          source_url = __url(base_src[:type], base_url, source_url)
        end
      end
      # puts "#{self.class.name}#url URL: #{source_url}"
      source_url
    end

    def __url(type, base_url, path)
      if Type::FILE == type
        Path.concat(base_url, path)
      else
        URI.join(base_url, path).to_s
      end
    end
  end
end
