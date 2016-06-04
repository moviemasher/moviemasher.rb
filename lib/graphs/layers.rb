
module MovieMasher
  # a background color layer
  class LayerColor
    def initialize(duration, color)
      @filter = FilterSourceColor.new duration, color
    end
    def layer_command(scope)
      @filter.filter_command(scope)
    end
    def trim_command(*)
      ''
    end
    def range
      nil
    end
  end
  # base class for a theme or transition layer
  class LayerModule < Layer # LayerTheme, LayerTransition
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
  class LayerRaw < Layer # LayerRawVideo, LayerRawImage
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
      chain = Chain.new nil, @job_input
      # we will need to change movie_filter path, since we'll be building
      # video file from image for each output
      @movie_filter = FilterSourceMovie.new(@input, @job_input)
      chain << @movie_filter
      @filter_timestamps = FilterSetpts.new('N')
      chain << @filter_timestamps
      @chains << chain
      super
    end
    def layer_command(scope)
      unless @input[:cached_file]
        raise(Error::JobInput, "no cached_file #{@input}")
      end
      output_type_is_not_video = (Type::VIDEO != scope[:mm_output][:type])
      @movie_filter.hash[:loop] = 1
      unless output_type_is_not_video
        loops = scope[:mm_fps].to_f * FloatUtil.precision(@input[:length])
        @movie_filter.hash[:loop] = loops.round.to_i
      end
      @filter_timestamps.disabled = output_type_is_not_video
      @movie_filter.hash[:filename] = @input[:cached_file]
      super
    end
  end
  # a raw video layer
  class LayerRawVideo < LayerRaw
    def initialize_chains
      # puts "LayerRawVideo#initialize_chains"
      chain = Chain.new nil, @job_input
      chain << FilterSourceMovie.new(@input, @job_input)
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
      layer_letter = 'a'
      @graphs.length.times { layer_letter.next! }
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
    def layer_command(scope)
      layer_scope(scope)
      layer_letter = 'a'
      cmds = []
      merge_cmds = []
      last_label = '[transback]'
      backcolor_cmd = @color_layer.layer_command(scope)
      backcolor_cmd += last_label
      @graphs.length.times do |i|
        graph = @graphs[i]
        layer_label = "#{layer_letter}_#{Type::TRANSITION}"
        cmd = graph.graph_command(scope[:mm_output])
        layer_chain = @layer_chains[i]
        cmd += ','
        cmd += layer_chain[:scaler].chain_command(scope)
        if layer_chain[:filters]
          chain_cmd = layer_chain[:filters].chain_command(scope)
          unless chain_cmd.to_s.empty?
            cmd += ','
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
        cmd += last_label if 0 == i
        merge_cmds << cmd
        layer_letter.next!
      end
      cmds << backcolor_cmd
      cmds += merge_cmds
      cmds.join(';')
    end
    def initialize_chains
      # puts "LayerTransition.initialize_chains #{@input}"
      super
      @layers = []
      c1 = {}
      c2 = {}
      @layer_chains = [c1, c2]
      if __is_and_not_empty(@input[:from][:filters])
        c1[:filters] = ChainModule.new(@input[:from], @job_input, @input)
      end
      if __is_and_not_empty(@input[:to][:filters])
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
  end
end
