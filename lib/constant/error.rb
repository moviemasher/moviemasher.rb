# frozen_string_literal: true

module MovieMasher
  module Error
    # base error
    class Runtime < RuntimeError
      def initialize(the_msg = nil)
        @msg = the_msg if the_msg
        super
      end

      def message
        to_s
      end

      def to_s
        @msg || ''
      end
    end

    # job related errors
    class Job < Runtime; end

    class JobOutput < Job; end

    class JobSyntax < Job; end

    # a problem rendering output
    class JobRender < JobOutput
      def initialize(ffmpeg_result, the_msg = 'failed to render')
        super(the_msg)
        error_lines = []
        error_lines << the_msg if the_msg
        if ffmpeg_result
          # puts ffmpeg_result
          lines = ffmpeg_result.split("\n")
          failure_words = %w[Error Invalid Failed]
          lines.reverse.each do |line|
            failure_words.each do |failure_word|
              if line.include? failure_word
                error_lines << line.split(/^\[.*\] /).last.strip
                break
              end
            end
          end
          error_lines << ffmpeg_result if error_lines.empty?
        end
        @msg = error_lines.join("\n") unless error_lines.empty?
      end
    end

    class JobUpload < Job; end

    class JobSource < Job; end

    class JobInput < Job; end

    class Todo < Job; end

    # serious code errors
    class Critical < Runtime; end

    class Parameter < Critical; end

    class Configuration < Critical; end

    class Object < Critical; end

    class State < Critical; end
  end
end
