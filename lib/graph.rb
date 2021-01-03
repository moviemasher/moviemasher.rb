# frozen_string_literal: true

module MovieMasher
  # base class for most other graph related classes
  class GraphUtility
    def __join_commands(cmds)
      joined_commands = []
      cmds = cmds.reject(&:empty?)
      c = cmds.length
      c.times do |i|
        cmd = cmds[i]
        cmd = "#{cmd}," unless (i.zero? && cmd.end_with?(':v]')) || i == c - 1
        joined_commands << cmd
      end
      joined_commands.join
    end

    def __coerce_if_numeric(value)
      Evaluate.coerce_if_numeric(value)
    end

    def _present(thing)
      thing && !thing.empty?
    end

    def __raise_if_empty(string, msg)
      raise(Error::JobInput, msg) if string.empty?
    end

    def __raise_unless(boolean, msg)
      raise(Error::JobInput, msg) unless boolean
    end
  end

  # top level interface
  class Graph < GraphUtility
    def self.color_value(color)
      if color.is_a?(String) && color.end_with?(')') && color.start_with?(
        'rgb(', 'rgba('
      )
        color_split = color.split('(')
        method = color_split.shift.to_sym
        params = color_split.shift[0..-2]
        color = FilterHelpers.send(method, params)
      end
      color
    end

    def create_layer(input)
      raise('no job') unless @job

      __raise_unless(input[:type], "input with no type #{input}")
      case input[:type]
      when Type::VIDEO
        layer = LayerRawVideo.new(input, @job_input)
      when Type::TRANSITION
        layer = LayerTransition.new(@job, input, @job_input)
      when Type::IMAGE
        layer = LayerRawImage.new(input, @job_input)
      when Type::THEME
        layer = LayerTheme.new(input, @job_input)
      else
        raise(Error::JobInput, "input hash type invalid #{input}")
      end
      layer
    end

    def duration
      @render_range.length_seconds
    end

    def graph_command(output)
      FilterSourceRaw.input_index = 0
      @job_output = output
    end

    def graph_scope
      raise('no job') unless @job

      scope = {}
      scope[:mm_job] = @job
      scope[:mm_output] = @job_output
      scope[:mm_render_range] = @render_range
      scope[:mm_fps] = @job_output[:video_rate] || 1
      scope[:mm_dimensions] = @job_output[:dimensions]
      scope[:mm_width], scope[:mm_height] = scope[:mm_dimensions].split 'x'
      scope
    end

    def initialize(job = nil, job_input = nil, render_range = nil)
      super()
      @job = job
      @job_input = job_input
      @render_range = render_range
    end

    def inputs
      []
    end
  end

  # base for all filters
  class Filter < GraphUtility
    class << self
      attr_accessor :__outsize
    end
    Filter.__outsize = {}
    attr_reader :id
    attr_writer :disabled

    def filter_command(_scope)
      (@disabled ? '' : @id)
    end

    def filter_name
      @id
    end

    def initialize(id = nil)
      super()
      @id = id || ''
      @disabled = false
    end
  end

  # base for all filter chains
  class Chain < GraphUtility
    def chain_command(scope)
      cmds = @filters.map do |f|
        f.send(f.is_a?(Filter) ? :filter_command : :chain_command, scope)
      end
      __join_commands(cmds)
    end

    def chain_labels(label, index)
      "[#{label}#{index == 1 ? '' : 'ed'}#{index - 1}][#{label}#{index}]"
    end

    def initialize(input = nil, job_input = nil)
      super()
      @input = input
      @job_input = job_input
      @filters = []
      # puts "Chain calling #initialize_filters"
      initialize_filters
    end

    def initialize_filters
      # override me
    end

    def <<(filter)
      @filters << filter
    end
  end

  # base for all layers
  # all layers - LayerRaw, LayerModule
  class Layer < GraphUtility
    def initialize(input, job_input)
      super()
      @input = input
      @job_input = job_input # will be different than input if we're in a mash
      raise('no input') unless input

      @range = input[:range]
      @chains = []
      initialize_chains
    end

    def initialize_chains
      if @input[:merger]
        @input[:merger][:dimensions] ||= @input[:dimensions]
        @merger_chain =
          if @input[:merger][:id] == 'com.moviemasher.merger.blend'
            ChainBlend.new(@input[:merger], @job_input, @input)
          else
            ChainModule.new(@input[:merger], @job_input, @input)
          end
      else
        @merger_chain = ChainOverlay.new(@job_input)
      end
      if @input[:scaler]
        @input[:scaler][:dimensions] ||= @input[:dimensions]
        @scaler_chain = ChainModule.new(@input[:scaler], @job_input, @input)
      else
        @scaler_chain = ChainScaler.new(@input, @job_input)
      end
      @effects_chain = ChainEffects.new(@input, @job_input)
      @chains << @scaler_chain
      @chains << @effects_chain
    end

    def inputs
      []
    end

    def layer_command(scope)
      layer_scope(scope)
      __join_commands(@chains.map { |chain| chain.chain_command(scope) })
    end

    def layer_scope(scope)
      __raise_unless(@input[:length], "no input length #{@input}")
      scope[:mm_duration] = @input[:length]
      scope[:mm_t] = "(t/#{scope[:mm_duration]})"
      return unless @input[:dimensions]

      scope[:overlay_w], scope[:overlay_h] = @input[:dimensions].split('x')
    end

    def merger_command(scope, label, index)
      merge_cmd = @merger_chain.chain_command(scope)
      __raise_if_empty(merge_cmd, "merger produced nothing #{self}")
      "#{@merger_chain.chain_labels(label, index)}#{merge_cmd}"
    end

    def range
      (@input ? @input[:range] : nil)
    end

    def trim_command(render_range)
      input_range = range
      # puts "command_range_trim #{input_range}"
      cmd = ''
      if render_range && input_range && !input_range.equals?(render_range)
        range_start = render_range.start_seconds
        range_end = render_range.end_seconds
        input_start = input_range.start_seconds
        input_end = input_range.end_seconds
        if range_start > input_start || range_end < input_end
          dur = __coerce_if_numeric(render_range.length_seconds)
          cmd += ",trim=duration=#{dur}"
          if range_start > input_start
            start = FloatUtil.precision(range_start - input_start)
            start = __coerce_if_numeric(start)
            cmd += ":start=#{start}"
          end
          cmd += ',setpts=expr=PTS-STARTPTS'
        end
      end
      cmd
    end
  end

  # a mash represented as a graph
  class GraphMash < Graph
    def add_new_layer(input)
      layer = create_layer(input)
      @layers << layer
      layer
    end

    # LayerTransition
    def graph_command(output, dont_set_input_index: false)
      FilterSourceRaw.input_index = 0 unless dont_set_input_index
      @job_output = output
      graph_cmds = []
      layer_length = @layers.length
      layer_length.times do |index|
        layer = @layers[index]
        cmd = layer.layer_command(graph_scope)
        cmd += layer.trim_command(@render_range)
        cmd += "[#{@label_name}#{index}]" if layer_length > 1
        graph_cmds << cmd
      end
      if layer_length > 1
        (1..layer_length - 1).each do |index|
          layer = @layers[index]
          cmd = layer.merger_command(graph_scope, @label_name, index)
          cmd += "[#{@label_name}ed#{index}]" if index + 1 < layer_length
          graph_cmds << cmd
        end
      end
      graph_cmds.join ';'
    end

    def initialize(job, mash_input, render_range = nil, label_name = 'layer')
      @label_name = label_name
      super(job, mash_input, render_range)
      @layers = []
      @layers << LayerColor.new(duration, mash_input[:mash][:backcolor])
    end

    def inputs
      layer_inputs = []
      @layers.each { |layer| layer_inputs += layer.inputs }
      layer_inputs
    end
  end

  # a video or image represented as a graph
  class GraphRaw < Graph
    def graph_command(*)
      super
      cmd = @layer.layer_command(graph_scope)
      cmd += @layer.trim_command(@render_range)
      cmd
    end

    # a video or image input
    def initialize(input)
      super(input, nil, input[:range])
      @layer = create_layer(input)
    end

    def inputs
      @layer.inputs
    end
  end
end
