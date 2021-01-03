# frozen_string_literal: true

module MovieMasher
  # module filter
  class FilterEvaluated < Filter
    attr_reader :parameters

    def command_parameters(scope)
      cmds = []
      if @parameters
        __raise_unless(@parameters.is_a?(Array), 'parameters is not an array')
        @parameters.each do |parameter|
          __raise_unless(parameter.is_a?(Hash), 'parameter is not a hash')
          name = parameter[:name]
          evaluated = parameter[:value]
          cmds << __command_name_value(name, evaluated, scope)
        end
      end
      cmds.join(':')
    end

    def filter_command(scope = nil)
      cmd = super
      return cmd if cmd.empty?

      @evaluated = {}
      cmds = []
      cmds << cmd
      if scope
        if Filter.__outsize['w'] && Filter.__outsize['h']
          scope[:mm_in_w] = Filter.__outsize['w']
          scope[:mm_in_h] = Filter.__outsize['h']
          # puts "<< #{scope[:mm_in_w]}x#{scope[:mm_in_h]} #{@id}"
        else
          scope[:mm_in_w] = 'in_w'
          scope[:mm_in_h] = 'in_h'
        end
      end
      cmd = command_parameters(scope)
      unless cmd.to_s.empty?
        cmds << '='
        cmds << cmd
      end
      cmd = cmds.join
      __set_output_dimension

      @evaluated = {}
      cmd
    end

    def initialize(filter_config, mash_input = nil, applied_input = nil)
      # applied_input same as filter_config for themes
      @config = filter_config
      raise(Error::Parameter, 'no config') unless @config

      @parameters = @config[:parameters]
      @evaluated = {}
      @mash_input = mash_input
      @applied_input = applied_input
      unless @parameters
        sym = filter_config[:id].upcase.to_sym
        if Parameters.const_defined?(sym)
          @parameters = Parameters.const_get(sym)
        end
        @parameters ||= []
      end
      super @config[:id]
    end

    # only called directly from here and tests
    def scope_value(scope, value_str)
      if scope
        # puts "1 value_str = #{value_str}"
        level = 0
        deepest = 0
        esc = '~'
        # expand variables
        value_str = value_str.to_s.dup
        value_str.gsub!(/(\w+)/) do |match|
          match_str = match.to_s
          match_sym = match_str.to_sym
          if scope[match_sym]
            scope[match_sym].to_s
          else
            match_str
          end
        end
        # puts "2 value_str = #{value_str}"
        value_str.gsub!(/[()]/) do |paren|
          result = paren.to_s
          case result
          when '('
            level += 1
            deepest = [deepest, level].max
            result = "(#{level}#{esc}"
          when ')'
            result = ")#{level}#{esc}"
            level -= 1
          end
          result
        end
        # puts "3 value_str = #{value_str}"
        while deepest.positive?
          # puts "PRE #{deepest}: #{value_str}"
          reg_str = "([a-z_]+)[(]#{deepest}[#{esc}](.*?)[)]#{deepest}[#{esc}]"
          regexp = Regexp.new(reg_str)
          value_str = value_str.gsub(regexp) do
            Regexp.last_match.captures[0]
            method = Regexp.last_match.captures.first
            param_str = Regexp.last_match.captures.last
            params = param_str.split(',').map(&:strip)
            if __is_filter_helper(method)
              result = FilterHelpers.send(
                method.to_sym, params, @mash_input[:mash], scope
              )
              __raise_unless(result, "got false #{method}(#{params.join ','})")
              result = result.to_s
              __raise_if_empty(result, "empty #{method}(#{params.join(',')})")
            else
              result = "#{method}(#{params.join ','})"
            end
            result
          end
          # puts "POST METHODS #{deepest}: #{value_str}"
          # replace all simple equations in parentheses
          reg_str = "[(]#{deepest}[#{esc}](.*?)[)]#{deepest}[#{esc}]"
          value_str = value_str.gsub(Regexp.new(reg_str)) do
            evaluated = Evaluate.equation(Regexp.last_match[1])
            evaluated = "(#{evaluated})" unless evaluated.respond_to?(:round)
            evaluated.to_s
          end
          # puts "POST EQUATIONS #{deepest}: #{value_str}"
          deepest -= 1
        end
        # remove any lingering markers
        regexp = Regexp.new("([()])[0-9]+[#{esc}]")
        value_str = value_str.gsub(regexp) { Regexp.last_match[1] }
        # remove whitespace
        # value_str.gsub!(/\s/, '')
        # puts "4 value_str = #{value_str}"
      end
      Evaluate.equation(value_str)
    end

    private

    def __command_name_value(name, value, scope)
      __raise_unless(value, '__command_name_value got nil value')
      result = value
      if value.is_a?(Array)
        result = nil
        bind = __filter_scope_binding(scope)
        condition_is_true = false
        value.each do |conditional|
          condition = conditional[:condition]
          if conditional[:is]
            condition += "==#{conditional[:is]}"
          elsif conditional[:in]
            unless conditional[:in].is_a?(Array)
              conditional[:in] = conditional[:in].split(',')
            end
            condition = "include(#{condition}, #{conditional[:in].join(', ')})"
          end
          condition = "if ((#{condition}), 1, 0)"
          calculator = Dentaku::Calculator.new
          calculator.add_function(
            :include, :numeric, ->(n, *args) { args.include?(n) }
          )
          condition_is_true = !calculator.evaluate(condition, bind).zero?
          if condition_is_true
            result = scope_value(scope, conditional[:value])
            break
          end
        end
        raise(Error::JobInput, 'zero true conditions') unless condition_is_true
      else
        result = scope_value(scope, value)
      end
      result = Evaluate.equation(result)
      result = __coerce_if_numeric(result)
      name = ShellHelper.escape(name)
      result = ShellHelper.escape(result)
      @evaluated[name] = result
      "#{name}=#{result}"
    end

    def __is_filter_helper(func)
      func_sym = func.to_sym
      ok = FilterHelpers.respond_to?(func_sym)
      ok &&= func.start_with?('mm_') || %w[rgb rgba].include?(func)
      ok
    end

    def __filter_dimension_keys(filter_id)
      case filter_id
      when 'crop'
        { w: %w[w out_w], h: %w[h out_h] }
      when 'scale', 'pad'
        { w: %w[w width], h: %w[h height] }
      end
    end

    def __filter_is_source?(filter_id)
      %w[color movie].include?(filter_id)
    end

    def __filter_scope_binding(scope)
      bind = {}
      scope&.each { |k, v| bind[k.to_sym] = __coerce_if_numeric(v) }
      bind
    end

    def __set_output_dimension
      dimension_keys = __filter_dimension_keys(@id)
      dimension_keys&.each do |w_or_h, keys|
        keys.each do |key|
          next unless @evaluated[key]

          evaluated = @evaluated[key]
          Filter.__outsize[w_or_h] = evaluated if evaluated.respond_to?(:round)
          break
        end
      end
    end
  end

  # simplest filter
  class FilterHash < Filter
    attr_reader :hash

    def filter_command(scope = nil)
      cmd = super
      unless cmd.empty? # I'm not disabled
        cmds = []
        @hash.each do |name, value|
          name = name.id2name if name.is_a?(Symbol)
          value = __coerce_if_numeric(value)
          name = ShellHelper.escape(name)
          value = ShellHelper.escape(value)
          cmds << "#{name}=#{value}"
        end
        cmd = ShellHelper.escape(cmd)
        cmd = "#{cmd}=#{cmds.join(':')}" unless cmds.empty?
      end
      cmd
    end

    def initialize(id, hash = nil)
      @hash = hash || {}
      super id
    end
  end

  # simple setpts defaults to PTS-STARTPTS
  class FilterSetpts < FilterHash
    def initialize(expr = 'PTS-STARTPTS')
      super('setpts', expr: expr)
    end
  end

  # base filter source
  class FilterSource < FilterHash
    def filter_command(scope)
      cmd = super
      unless cmd.empty?
        Filter.__outsize['w'], Filter.__outsize['h'] = @dimensions.split('x')
      end
      cmd
    end

    def initialize(id, hash, dimensions = nil)
      super(id, hash)
      @dimensions = dimensions
    end
  end

  # base raw source
  class FilterSourceRaw < FilterSource
    class << self
      attr_accessor :input_index
    end
    FilterSourceRaw.input_index = 0
    def filter_name
      "#{super} #{File.basename(@hash[:filename])}"
    end

    def initialize(input, job_input)
      @input = input
      @job_input = job_input
      # filename: @input[:cached_file]
      super('movie', {}, @input[:dimensions])
    end

    def filter_command(*)
      Filter.__outsize['w'], Filter.__outsize['h'] = @dimensions.split('x')
      index = FilterSourceRaw.input_index
      FilterSourceRaw.input_index += 1
      "[#{index}:v]"
    end
  end

  # video source
  class FilterSourceVideo < FilterSourceRaw
    def inputs
      [{ i: @input[:cached_file] }]
    end
  end

  # image source
  class FilterSourceImage < FilterSourceRaw
    def inputs
      [{ loop: 1, i: @input[:cached_file] }]
    end
  end

  # simple color source
  class FilterSourceColor < FilterSource
    def filter_command(scope)
      output = scope[:mm_output]
      __raise_unless(output[:dimensions], "#{filter_name} with no dimensions")
      # __raise_unless(output[:video_rate], "#{filter_name} with no video_rate")
      @dimensions = @hash[:size] = output[:dimensions]
      @hash[:rate] = output[:video_rate] || 1
      super
    end

    def filter_name
      "#{super} #{@hash[:color]} #{@dimensions}"
    end

    def initialize(duration, color)
      __raise_unless(duration, 'FilterSourceColor with no duration')
      __raise_unless(color, 'FilterSourceColor with no color')
      # we don't know dimensions yet
      super('color', { color: Graph.color_value(color), duration: duration })
    end
  end
end
