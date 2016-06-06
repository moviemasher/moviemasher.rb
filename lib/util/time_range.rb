
module MovieMasher
  # a time span at a rate
  class TimeRange
    def self.input_length(input)
      input_time(input, :length)
    end
    def self.input_time(input, key)
      time = FloatUtil::ZERO
      duration = input[:duration].to_f
      rel_key = :"#{key.id2name}_is_relative"
      val_key = :"#{key.id2name}_relative_value"
      if input[rel_key] && input[val_key]
        if FloatUtil.gtr(duration, FloatUtil::ZERO)
          time = __relative_time(input[rel_key], input[val_key], duration)
        end
      elsif FloatUtil.gtr(input[key], FloatUtil::ZERO)
        time = input[key]
      elsif :length == key && FloatUtil.gtr(duration, FloatUtil::ZERO)
        time = duration - input_trim(input)
      end
      FloatUtil.precision(time)
    end
    def self.input_trim(input)
      input_time(input, :offset)
    end
    def self.input_trim_range(input)
      range = new(input_trim(input), 1, 1)
      range.length = input_length(input)
      range
    end
    def self.update(inputs, outputs)
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
      output_duration = FloatUtil.max(start_video, start_audio)
      outputs.each do |output|
        output[:duration] = output_duration
        if Type::SEQUENCE == output[:type]
          padding = (output[:video_rate].to_f * output_duration)
          output[:sequence] = "%0#{padding.floor.to_i.to_s.length}d"
        end
      end
      output_duration
    end
    def self.__gcd(a, b) # uint
      while b != 0
        t = b
        b = a % b
        a = t
      end
      a
    end
    def self.__lcm(a, b)
      (a * b / __gcd(a, b))
    end
    def self.__relative_time(char, value, duration)
      if '%' == char
        (value * duration) / FloatUtil::HUNDRED
      else
        duration + value
      end
    end
    def self.__scale(time, rate, rounding = :round)
      if !time.empty?
        __scale_time(time, rate, rounding)
      elsif 0 < rate && time.rate != rate
        if 0 < time.rate
          floated = time.length.to_f / (time.rate.to_f / rate.to_f)
          floated = floated.send(rounding) if rounding
          time.length = [1, floated].max
        end
        __scale_time(time, rate, rounding)
      end
    end
    def self.__scale_time(time, rate, rounding = :round)
      rate = rate.to_i if rate.respond_to? :to_i
      if 0 < rate && rate != time.rate
        if 0 < time.rate
          floated = time.start.to_f / (time.rate.to_f / rate.to_f)
          floated = floated.send(rounding) if rounding
          time.start = floated
        end
        time.rate = rate
      end
    end
    attr_accessor :length
    attr_accessor :rate
    attr_accessor :start
    def dup
      TimeRange.new @start, @length, @rate
    end
    def end_seconds
      TimeRange.new(stop, rate).start_seconds
    end
    def equals?(range)
      equal = false
      if range && 0 < range.rate && 0 <= range.start
        if rate == range.rate
          equal = ((start == range.start) && (length == range.length))
        else
          # make copies so neither range is changed
          range1 = dup
          range2 = range.dup
          range1.synchronize range2
          equal = range1.start == range2.start && range1.length == range2.length
        end
      end
      equal
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
      FloatUtil.precision((@length.to_f / @rate.to_f), precision)
    end
    def start_seconds(precision = 3)
      FloatUtil.precision((@start.to_f / @rate.to_f), precision)
    end
    def stop
      start + length
    end
    def synchronize(time, rounding = :round)
      if time && time.respond_to?(:rate) && time.respond_to?(:scale)
        if time.rate != @rate
          gcf = TimeRange.__lcm(time.rate, @rate)
          scale(gcf, rounding)
          TimeRange.__scale(time, gcf, rounding)
        end
      end
    end
  end
end
