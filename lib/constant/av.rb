
module MovieMasher
  # potential combinations of audio and video
  module AV
    AUDIO_ONLY = 'audio'.freeze
    BOTH = 'both'.freeze
    NEITHER = 'neither'.freeze
    VIDEO_ONLY = 'video'.freeze
    def self.includes?(has, desired)
      (BOTH == desired) || (BOTH == has) || (desired == has)
    end
    def self.merge(type1, type2)
      return type1 unless type2 && type1 != type2
      BOTH
    end
  end
end
