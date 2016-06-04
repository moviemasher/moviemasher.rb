
module MovieMasher
  # input, output and transfer types
  module Type
    ASSETS = %w(frame video audio image font).freeze
    AUDIO = 'audio'.freeze
    EFFECT = 'effect'.freeze
    FILE = 'file'.freeze
    FONT = 'font'.freeze
    FRAME = 'frame'.freeze
    HTTP = 'http'.freeze
    HTTPS = 'https'.freeze
    IMAGE = 'image'.freeze
    IMAGES = %w(image sequence).freeze
    MASH = 'mash'.freeze
    MERGER = 'merger'.freeze
    MODULES = %w(theme font effect).freeze
    RAW_AVS = %w(audio video).freeze
    RAW_VISUALS = %w(image video).freeze
    S3 = 's3'.freeze
    SCALER = 'scaler'.freeze
    SEQUENCE = 'sequence'.freeze
    THEME = 'theme'.freeze
    TRACKS = %w(audio video).freeze
    TRANSITION = 'transition'.freeze
    VIDEO = 'video'.freeze
    VISUALS = %w(image video theme).freeze
    WAVEFORM = 'waveform'.freeze
  end
end
