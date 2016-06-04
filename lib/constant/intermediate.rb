
module MovieMasher
  # ffmpeg formats for intermediate build files
  module Intermediate
    AUDIO_EXTENSION = 'wav'.freeze # file extension for audio portion
    VIDEO_EXTENSION = 'mpg'.freeze # used for piped and concat files
    VIDEO_FORMAT = 'yuv4mpegpipe'.freeze # -f:v switch for piped & concat files
  end
end
