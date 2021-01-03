# frozen_string_literal: true

module MovieMasher
  # a time span at a rate
  class TimeRange
    class << self
      def input_length(input)
        input_time(input, :length)
      end

      def input_time(input, key)
        time = FloatUtil::ZERO
        duration = input[:duration].to_f
        rel_key = "#{key.id2name}_is_relative".to_sym
        val_key = "#{key.id2name}_relative_value".to_sym
        if input[rel_key] && input[val_key]
          if FloatUtil.gtr(duration, FloatUtil::ZERO)
            time = relative_time(input[rel_key], input[val_key], duration)
          end
        elsif FloatUtil.gtr(input[key], FloatUtil::ZERO)
          time = input[key]
        elsif key == :length && FloatUtil.gtr(duration, FloatUtil::ZERO)
          time = duration - input_trim(input)
        end
        FloatUtil.precision(time)
      end

      def input_trim(input)
        input_time(input, :offset)
      end

      def input_trim_range(input)
        range = new(input_trim(input), 1, 1)
        range.length = input_length(input)
        range
      end

      def update(inputs, outputs)
        output_duration = update_inputs(inputs)
        update_outputs(outputs, output_duration)
        output_duration
      end

      def update_inputs(inputs)
        start_audio = FloatUtil::ZERO
        start_video = FloatUtil::ZERO
        inputs.each do |input|
          if FloatUtil.cmp(input[:start], FloatUtil::NEG_ONE)
            input[:start] =
              if input[:no_video] || input[:no_audio]
                (input[:no_video] ? start_audio : start_video)
              else
                input[:start] = [start_audio, start_video].max
              end
          end
          length = input_length(input)
          start_video = input[:start] + length unless input[:no_video]
          start_audio = input[:start] + length unless input[:no_audio]
          input[:length] = length
          input[:range] = input_trim_range(input)
          input[:offset] = input_trim(input)
        end

        FloatUtil.max(start_video, start_audio)
      end

      def update_outputs(outputs, output_duration)
        outputs.each do |output|
          output[:duration] = output_duration
          if Type::SEQUENCE == output[:type]
            padding = (output[:video_rate].to_f * output_duration)
            output[:sequence] = "%0#{padding.floor.to_i.to_s.length}d"
          end
        end
      end

      private

      def gcd(rate1, rate2)
        while rate2 != 0
          t = rate2
          rate2 = rate1 % rate2
          rate1 = t
        end
        rate1
      end

      def lcm(rate1, rate2)
        (rate1 * rate2 / gcd(rate1, rate2))
      end

      def relative_time(char, value, duration)
        if char == '%'
          (value * duration) / FloatUtil::HUNDRED
        else
          duration + value
        end
      end

      def scale(time, rate, rounding = :round)
        if !time.empty?
          scale_time(time, rate, rounding)
        elsif rate.positive? && time.rate != rate
          if time.rate.positive?
            floated = time.length.to_f / (time.rate.to_f / rate)
            floated = floated.send(rounding) if rounding
            time.length = [1, floated].max
          end
          scale_time(time, rate, rounding)
        end
      end

      def scale_time(time, rate, rounding = :round)
        rate = rate.to_i if rate.respond_to? :to_i
        return unless rate.positive? && rate != time.rate

        if time.rate.positive?
          floated = time.start.to_f / (time.rate.to_f / rate)
          floated = floated.send(rounding) if rounding
          time.start = floated
        end
        time.rate = rate
      end
    end

    attr_accessor :length, :rate, :start

    def dup
      TimeRange.new @start, @length, @rate
    end

    def end_seconds
      TimeRange.new(stop, rate).start_seconds
    end

    def equals?(range)
      return false unless range
      return false unless rate.positive? && !range.start.negative?

      if rate == range.rate
        ((start == range.start) && (length == range.length))
      else
        # make copies so neither range is changed
        range1 = dup
        range2 = range.dup
        range1.synchronize range2
        range1.start == range2.start && range1.length == range2.length
      end
    end

    def initialize(start = 0, rate = 0, length = 1)
      @length = length
      @start = start.to_i
      @rate = rate.to_i
    end

    def intersection(range)
      result = nil
      range1 = self
      range2 = range
      if range1.rate != range2.rate
        range1 = range1.dup
        range2 = range2.dup
        range1.synchronize range2
      end
      last_start = [range1.start, range2.start].max
      first_end = [range1.stop, range2.stop].min
      if last_start < first_end
        result = TimeRange.new(last_start, range1.rate, first_end - last_start)
      end
      result
    end

    def length_seconds(precision = 3)
      FloatUtil.precision((@length.to_f / @rate), precision)
    end

    def start_seconds(precision = 3)
      FloatUtil.precision((@start.to_f / @rate), precision)
    end

    def stop
      start + length
    end

    def synchronize(time, rounding = :round)
      return unless time
      return unless time.respond_to?(:rate) && time.respond_to?(:scale)
      return if time.rate == @rate

      gcf = TimeRange.lcm(time.rate, @rate)
      scale(gcf, rounding)
      TimeRange.scale(time, gcf, rounding)
    end
  end
end
