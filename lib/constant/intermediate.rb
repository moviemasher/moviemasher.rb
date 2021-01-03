# frozen_string_literal: true

module MovieMasher
  # ffmpeg formats for intermediate build files
  module Intermediate
    AUDIO_EXTENSION = 'wav' # file extension for audio portion
    VIDEO_EXTENSION = 'mpg' # used for piped and concat files
    VIDEO_FORMAT = 'yuv4mpegpipe' # -f:v switch for piped & concat files
  end
end
