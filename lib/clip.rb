# frozen_string_literal: true

module MovieMasher
  # represents a clip in a mash
  class Clip < Asset
    # Returns a new instance.
    def self.create(hash = nil)
      (hash.is_a?(Clip) ? hash : Clip.new(hash))
    end

    def id
      _get(__method__)
    end


    # Transfer - Resolves relative URLs.
    # Default - job's base_source
    # Types - Just Type::MASH.
    def base_source
      _get(__method__)
    end

    def duration
      _get(__method__)
    end

    # Float - Seconds of Clip available for presentation.
    # Default - Probed from downloaded.
    # Types - All except Type::IMAGE.
    def duration=(value)
      _set(__method__, value)
    end

    def error?
      nil
    end

    def length
      _get(__method__)
    end

    # Float - Seconds the Clip appears in the mashup.
    # Default - #duration - #offset
    def length=(value)
      _set(__method__, value)
    end

    def loop
      _get(__method__)
    end

    # Integer - Number of times to loop Clip.
    # Types - Just Type::AUDIO.
    def loop=(value)
      _set(__method__, value)
    end

    # Transfer - Resolves relative font URLs for modules.
    # Default - job's module_source
    # Types - Just Type::MASH.
    def module_source
      _get(__method__)
    end

    def start
      _get(__method__)
    end

    # Float - Seconds from start of mashup to introduce the Clip.
    # Default - -1.0 means after previous audio in mashup completes.
    # Types - Just Type::AUDIO.
    def start=(value)
      _set(__method__, value)
    end
  end
end
