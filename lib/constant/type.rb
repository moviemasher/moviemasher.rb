# frozen_string_literal: true

module MovieMasher
  # input, output and transfer types
  module Type
    ASSETS = %w[frame video audio image font].freeze
    AUDIO = 'audio'
    CHAIN = 'chain'
    EFFECT = 'effect'
    FILE = 'file'
    FONT = 'font'
    FRAME = 'frame'
    HTTP = 'http'
    HTTPS = 'https'
    IMAGE = 'image'
    IMAGES = %w[image sequence].freeze
    MASH = 'mash'
    MERGER = 'merger'
    MODULES = %w[theme font effect].freeze
    RAW = %w[audio image video]
    RAW_AVS = %w[audio video].freeze
    RAW_VISUALS = %w[image video].freeze
    S3 = 's3'
    SCALER = 'scaler'
    SEQUENCE = 'sequence'
    THEME = 'theme'
    TRACKS = %w[audio video].freeze
    TRANSITION = 'transition'
    VIDEO = 'video'
    VISUALS = %w[image video theme].freeze
    WAVEFORM = 'waveform'
  end
end
