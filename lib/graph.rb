
module MovieMasher
  # base class for most other graph related classes
  class GraphUtility
    def __coerce_if_numeric(value)
      Evaluate.coerce_if_numeric(value)
    end
    def __is_and_not_empty(thing)
      thing && !thing.empty?
    end
    def __raise_if_empty(s, msg)
      raise(Error::JobInput, msg) if s.empty?
    end
    def __raise_unless(tf, msg)
      raise(Error::JobInput, msg) unless tf
    end
  end
  # top level interface
  class Graph < GraphUtility
    def self.color_value(color)
      if color.is_a?(String) && color.end_with?(')')
        if color.start_with?('rgb(', 'rgba(')
          color_split = color.split('(')
          method = color_split.shift.to_sym
          params = color_split.shift[0..-2]
          color = FilterHelpers.send(method, params)
        end
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
      @id = id || ''
      @disabled = false
    end
  end
  # base for all filter chains
  class Chain < GraphUtility
    def chain_command(scope)
      cmds = []
      @filters.each do |filter|
        cmd =
          if filter.is_a?(Filter)
            filter.filter_command(scope)
          else
            filter.chain_command(scope)
          end
        cmds << cmd unless cmd.to_s.empty?
      end
      cmds.join(',')
    end
    def initialize(input = nil, job_input = nil)
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
  class Layer < GraphUtility # all layers - LayerRaw, LayerModule
    def initialize(input, job_input)
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
        @merger_chain = ChainModule.new(@input[:merger], @job_input, @input)
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
      cmds = []
      @chains.each do |chain|
        chain_cmd = chain.chain_command(scope)
        cmds << chain_cmd unless chain_cmd.to_s.empty?
      end
      cmds.join(',')
    end
    def layer_scope(scope)
      __raise_unless(@input[:length], "no input length #{@input}")
      scope[:mm_duration] = @input[:length]
      scope[:mm_t] = "(t/#{scope[:mm_duration]})"
      if @input[:dimensions]
        scope[:overlay_w], scope[:overlay_h] = @input[:dimensions].split('x')
      end
    end
    def merger_command(scope)
      @merger_chain.chain_command(scope)
    end
    def range
      (@input ? @input[:range] : nil)
    end
    def trim_command(render_range)
      input_range = range
      # puts "command_range_trim #{input_range}"
      cmd = ''
      if render_range && input_range && !input_range.equals?(render_range)
        # puts "render_range #{render_range.inspect}"
        # puts "input_range #{input_range.inspect}"
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
    def graph_command(*)
      super
      graph_cmds = []
      layer_length = @layers.length
      layer_length.times do |i|
        layer = @layers[i]
        cmd = layer.layer_command(graph_scope)
        cmd += layer.trim_command(@render_range)
        cmd += "[#{@label_name}#{i}]" if 1 < layer_length
        graph_cmds << cmd
      end
      if 1 < layer_length
        (1..layer_length - 1).each do |i|
          layer = @layers[i]
          cmd = (1 == i ? "[#{@label_name}0]" : "[#{@label_name}ed#{i - 1}]")
          cmd += "[#{@label_name}#{i}]"
          merge_cmd = layer.merger_command(graph_scope)
          __raise_if_empty(merge_cmd, "merger produced nothing #{layer}")
          cmd += merge_cmd
          cmd += "[#{@label_name}ed#{i}]" if i + 1 < layer_length
          graph_cmds << cmd
        end
      end
      cmd = graph_cmds.join ';'
      cmd
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
    def initialize(input) # a video or image input
      super(input, nil, input[:range])
      @layer = create_layer(input)
    end
    def inputs
      @layer.inputs
    end
  end
end
