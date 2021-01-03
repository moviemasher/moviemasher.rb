# frozen_string_literal: true

module MovieMasher
  # a background color layer
  class LayerColor
    def initialize(duration, color)
      @filter = FilterSourceColor.new duration, color
    end

    def inputs
      []
    end

    def layer_command(scope)
      @filter.filter_command(scope)
    end

    def range
      nil
    end

    def trim_command(*)
      ''
    end
  end

  # base class for a theme or transition layer
  # LayerTheme, LayerTransition
  class LayerModule < Layer
    def layer_scope(scope)
      scope[:mm_input_dimensions] = scope[:mm_dimensions]
      raise('no input dimensions') unless scope[:mm_input_dimensions]

      w, h = scope[:mm_input_dimensions].split('x')
      scope[:mm_input_width] = w
      scope[:mm_input_height] = h
      super
    end
  end

  # base class for a video or image layer
  # LayerRawVideo, LayerRawImage
  class LayerRaw < Layer
    def inputs
      @filter_movie.inputs
    end

    def layer_command(scope)
      scope[:mm_input_dimensions] = @input[:dimensions]
      raise 'no input dimensions' unless scope[:mm_input_dimensions]

      w, h = scope[:mm_input_dimensions].split('x')
      scope[:mm_input_width] = w
      scope[:mm_input_height] = h
      super
    end
  end

  # a raw image layer
  class LayerRawImage < LayerRaw
    def initialize_chains
      chain = Chain.new(nil, @job_input)
      @filter_movie = FilterSourceImage.new(@input, @job_input)
      chain << @filter_movie
      @filter_timestamps = FilterSetpts.new
      chain << @filter_timestamps
      @chains << chain
      super
    end

    def layer_command(scope)
      unless @input[:cached_file]
        raise(Error::JobInput, "no cached_file #{@input}")
      end

      @filter_timestamps.disabled = (Type::VIDEO != scope[:mm_output][:type])
      super
    end
  end

  # a raw video layer
  class LayerRawVideo < LayerRaw
    def initialize_chains
      # puts "LayerRawVideo#initialize_chains"
      chain = Chain.new(nil, @job_input)
      @filter_movie = FilterSourceVideo.new(@input, @job_input)
      chain << @filter_movie
      # trim filter, if needed
      @trim_filter = __filter_trim_input
      chain << @trim_filter if @trim_filter
      # fps is placeholder since each output has its own rate
      @fps_filter = FilterHash.new('fps', fps: 0)
      chain << @fps_filter
      # set presentation timestamp filter
      @filter_timestamps = FilterSetpts.new
      chain << @filter_timestamps
      @chains << chain
      super
      # puts "LayerRawVideo.initialize_chains #{@chains}"
    end

    def layer_command(scope)
      raise(Error::JobInput, 'layer_command with empty scope') unless scope

      output_type_is_not_video = (Type::VIDEO != scope[:mm_output][:type])
      # puts "output_type_is_not_video = #{output_type_is_not_video}"
      @fps_filter.disabled = output_type_is_not_video
      @trim_filter.disabled = output_type_is_not_video if @trim_filter
      @filter_timestamps.disabled = output_type_is_not_video
      @fps_filter.hash[:fps] = scope[:mm_fps]
      super
    end

    def __filter_trim_input
      filter = nil
      raise 'no offset' unless @input[:offset]

      offset = @input[:offset]
      raise 'no length' unless @input[:length]

      length = @input[:length]
      trim_beginning = FloatUtil.gtr(offset, FloatUtil::ZERO)
      trim_end = FloatUtil.gtr(length, FloatUtil::ZERO)
      trim_end &&= (@input[:duration].to_f > (offset + length))
      if trim_beginning || trim_end
        # start and duration look at timestamp and change it
        filter = FilterHash.new('trim', duration: FloatUtil.precision(length))
        filter.hash[:start] = FloatUtil.precision(offset) if trim_beginning
      end
      filter
    end
  end

  # a theme layer
  class LayerTheme < LayerModule
    def initialize_chains
      # puts "LayerTheme.initialize_chains"
      @chains << ChainModule.new(@input, @job_input, @input)
      super
    end
  end

  # a transition layer
  class LayerTransition < LayerModule
    def add_new_layer(clip)
      layer_letter = ('a'..'z').to_a[@graphs.length]
      layer_label = "#{layer_letter}_#{Type::TRANSITION}"
      graph = GraphMash.new(@job, @job_input, @input[:range], layer_label)
      graph.add_new_layer(clip)
      @graphs << graph
    end

    def initialize(job, input, job_input)
      @job = job
      raise('no job') unless @job

      super(input, job_input)
      @graphs = []
    end

    def initialize_chains
      # puts "LayerTransition.initialize_chains #{@input}"
      super
      @layers = []
      c1 = {}
      c2 = {}
      @layer_chains = [c1, c2]
      if _present(@input[:from][:filters])
        c1[:filters] = ChainModule.new(@input[:from], @job_input, @input)
      end
      if _present(@input[:to][:filters])
        c2[:filters] = ChainModule.new(@input[:to], @job_input, @input)
      end
      c1[:merger] = ChainModule.new(@input[:from][:merger], @job_input, @input)
      c2[:merger] = ChainModule.new(@input[:to][:merger], @job_input, @input)
      c1[:scaler] = ChainModule.new(@input[:from][:scaler], @job_input, @input)
      c2[:scaler] = ChainModule.new(@input[:to][:scaler], @job_input, @input)
      mash_source = @job_input[:mash]
      mash_color = mash_source[:backcolor]
      @color_layer = LayerColor.new(@input[:range].length_seconds, mash_color)
    end

    def inputs
      graph_inputs = []
      @graphs.each { |graph| graph_inputs += graph.inputs }
      graph_inputs
    end

    def layer_command(scope)
      layer_scope(scope)
      layer_letters = ('a'..'z').to_a.cycle
      cmds = []
      merge_cmds = []
      last_label = '[transback]'
      backcolor_cmd = @color_layer.layer_command(scope)
      backcolor_cmd += last_label
      @graphs.length.times do |i|
        graph = @graphs[i]
        layer_label = "#{layer_letters.next}_#{Type::TRANSITION}"
        cmd = graph.graph_command(scope[:mm_output], dont_set_input_index: true)
        layer_chain = @layer_chains[i]
        cmd += ',' unless cmd.end_with?(':v]')
        cmd += layer_chain[:scaler].chain_command(scope)
        if layer_chain[:filters]
          chain_cmd = layer_chain[:filters].chain_command(scope)
          unless chain_cmd.to_s.empty?
            cmd += ',' unless cmd.end_with?(':v]')
            cmd += chain_cmd
          end
        end
        cur_label = "[#{layer_label}]"
        cmd += cur_label
        cmds << cmd
        cmd = last_label
        cmd += cur_label
        cmd += @layer_chains[i][:merger].chain_command(scope)
        last_label = "[#{layer_label}ed]"
        cmd += last_label if i.zero?
        merge_cmds << cmd
      end
      cmds << backcolor_cmd
      cmds += merge_cmds
      cmds.join(';')
    end
  end
end
