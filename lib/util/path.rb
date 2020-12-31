# frozen_string_literal: true

module MovieMasher
  # add and strip slashes from start and/or end of string
  module Path
    SLASH = '/'

    class << self
      def add_slashes(string)
        add_slash_start(add_slash_end(string))
      end

      def add_slash_end(string)
        string ||= ''
        string = "#{string}#{SLASH}" unless string.end_with?(SLASH)
        string
      end

      def add_slash_start(string)
        string ||= ''
        string = "#{SLASH}#{string}" unless string.start_with?(SLASH)
        string
      end

      def concat(string1, string2)
        string1 ||= ''
        string2 ||= ''
        if string1.empty? || string2.empty?
          string1 += string2
        else
          string1 = add_slash_end(string1) + strip_slash_start(string2)
        end
        string1
      end

      def strip_slashes(string)
        strip_slash_start(strip_slash_end(string))
      end

      def strip_slash_end(string)
        string ||= ''
        string = string[0..-2] if string.end_with?(SLASH)
        string
      end

      def strip_slash_start(string)
        string ||= ''
        string = string[1..] if string.start_with?(SLASH)
        string
      end
    end
  end
end
