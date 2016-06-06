
module MovieMasher
  # a chain of effects
  class ChainEffects < Chain
    def initialize_filters
      if __is_and_not_empty(@input[:effects]) && @input[:effects].is_a?(Array)
        @input[:effects].reverse.each do |effect|
          effect[:dimensions] = @input[:dimensions] unless effect[:dimensions]
          @filters << ChainModule.new(effect, @job_input, @input)
        end
      end
    end
  end
  # a theme or transition filter chain
  class ChainModule < Chain
    attr_writer :input
    def chain_command(scope)
      scope = input_scope(scope)
      super
    end
    def initialize(mod_input, mash_input, applied_input)
      # applied_input is same as mod_input for themes
      raise(Error::Parameter, 'no mod_input') unless mod_input
      # raise(Error::Parameter, 'no mash_input') unless mash_input
      # raise(Error::Parameter, 'no applied_input') unless applied_input
      @applied_input = applied_input
      super(mod_input, mash_input)
    end
    def initialize_filters
      if __is_and_not_empty(@input[:filters]) && @input[:filters].is_a?(Array)
        @filters += @input[:filters].map do |filter_config|
          FilterEvaluated.new(filter_config, @job_input, @applied_input)
        end
      else
        raise(Error::JobInput, "ChainModule with no filters #{@input}")
      end
    end
    def input_scope(scope)
      scope = scope.dup # shallow copy, so any objects are just pointers
      properties = @input[:properties]
      if __is_and_not_empty(properties) && properties.is_a?(Hash)
        properties.each do |property, ob|
          scope[property] = @input[property] || ob[:value]
          # puts "#{property} = #{scope[property]}"
        end
      end
      scope
    end
  end
  # an overlay filter chain
  class ChainOverlay < Chain
    def initialize(job_output)
      super nil, job_output
    end
    def initialize_filters
      @filters << FilterHash.new('overlay', x: 0, y: 0)
    end
  end
  # a scaler filter chain
  class ChainScaler < Chain
    def chain_command(scope)
      @filters = []
      target_dims = scope[:mm_dimensions]
      orig_dims = @input_dimensions || target_dims
      __raise_unless(orig_dims, 'input dimensions nil')
      __raise_unless(target_dims, 'output dimensions nil')
      orig_dims = orig_dims.split('x')
      target_dims = target_dims.split('x')
      if orig_dims != target_dims
        orig_w = orig_dims[0].to_i
        orig_h = orig_dims[1].to_i
        target_w = target_dims[0].to_i
        target_h = target_dims[1].to_i
        orig_w_f = orig_w.to_f
        orig_h_f = orig_h.to_f
        target_w_f = target_w.to_f
        target_h_f = target_h.to_f
        simple_scale = (Fill::STRETCH == @fill)
        unless simple_scale
          fill_is_scale = (Fill::SCALE == @fill)
          ratio_w = target_w_f / orig_w_f
          ratio_h = target_h_f / orig_h_f
          ratio = __min_or_max(fill_is_scale, ratio_h, ratio_w)
          simple_scale = (Fill::NONE == @fill)
          if simple_scale
            target_w = (orig_w_f * ratio).to_i
            target_h = (orig_h_f * ratio).to_i
          else
            w_scaled = target_w_f / ratio
            h_scaled = target_h_f / ratio
            simple_scale = FloatUtil.cmp(orig_w_f, w_scaled)
            simple_scale &&= FloatUtil.cmp(orig_h_f, h_scaled)
          end
        end
        unless simple_scale
          gtr = FloatUtil.gtr(orig_w_f, w_scaled)
          gtr ||= FloatUtil.gtr(orig_h_f, h_scaled)
          @filters << __crop_or_pad(gtr, w_scaled, h_scaled, orig_w_f, orig_h_f)
          simple_scale = !((orig_w == target_w) || (orig_h == target_h))
        end
        if simple_scale
          @filters << FilterHash.new('scale', w: target_w, h: target_h)
        end
        if Fill::STRETCH == @fill
          @filters << FilterHash.new('setsar', sar: 1, max: 1)
        end
      end
      super
    end
    def initialize(input = nil, job_input = nil)
      super
      @input_dimensions = @input[:dimensions]
      @fill = @input[:fill] || Fill::STRETCH
    end
    def __crop_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
      FilterHash.new(
        'crop',
        w: w_scaled.to_i,
        h: h_scaled.to_i,
        x: ((orig_w_f - w_scaled) / FloatUtil::TWO).ceil.to_i,
        y: ((orig_h_f - h_scaled) / FloatUtil::TWO).ceil.to_i
      )
    end
    def __crop_or_pad(gtr, w_scaled, h_scaled, orig_w_f, orig_h_f)
      if gtr
        __crop_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
      else
        __pad_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
      end
    end
    def __min_or_max(fill_is_scale, ratio_h, ratio_w)
      if fill_is_scale
        FloatUtil.min(ratio_h, ratio_w)
      else
        FloatUtil.max(ratio_h, ratio_w)
      end
    end
    def __pad_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
      backcolor = 'black'
      if @job_input[:mash] && @job_input[:mash][:backcolor]
        backcolor = Graph.color_value(@job_input[:mash][:backcolor])
      end
      FilterHash.new(
        'pad',
        color: backcolor,
        w: w_scaled.to_i, h: h_scaled.to_i,
        x: ((w_scaled - orig_w_f) / FloatUtil::TWO).floor.to_i,
        y: ((h_scaled - orig_h_f) / FloatUtil::TWO).floor.to_i
      )
    end
  end
end
