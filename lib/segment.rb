# frozen_string_literal: true

module MovieMasher
  module Render
    # a slice of a job, with potentially multiple layers containing inputs
    module Segment 
      module Layer
        module Chain
          module Filter# base for all filters
            class FilterClass
              attr_reader :id

              def initialize(id)
                @id = id
              end

              def dynamic_filter(_scope)
                h = {}
                h[:name] = id
                h[:arguments] = {}
                h
              end
            end
            
            module FilterEvaluated
              class << self
                def create(*args)
                  # puts "#{self.name}##{__method__} args: #{args}"
                  
                  FilterEvaluatedClass.new(*args)
                end
              end
            
              class FilterEvaluatedClass < Filter::FilterClass
                attr_reader :parameters, :evaluated, :config

                def command_parameters(scope)
                  # puts "#{self.class.name}##{__method__} parameters: #{parameters}"
                  item = {}
                  if parameters
                    Render.raise_if_false(parameters.is_a?(Array), 'parameters is not an array')
                    parameters.each do |parameter|
                      Render.raise_if_false(parameter.is_a?(Hash), 'parameter is not a hash')
                      name = parameter[:name]
                      value = parameter[:value]
                      Render.raise_if_false(name && value, "name: '#{name}' value: '#{value}'")
          
                      name, value = __command_name_value(name, value, scope)
                      # puts "#{self.class.name}##{__method__} #{name.class.name} #{name}, #{value.class.name} #{value}"

                      item[name] = value
                    end
                  end
                  item
                end

                def reset_evaluated
                  @evaluated = {}
                end

                def initialize(config)
                  @config = config
                  raise(Error::Parameter, 'no config') unless @config

                  @parameters = @config[:parameters]
                  # puts parameters
                  reset_evaluated
                  unless @parameters
                    sym = config[:id].upcase.to_sym
                    if Parameters.const_defined?(sym)
                      @parameters = Parameters.const_get(sym)
                    end
                    @parameters ||= []
                  end
                  super(@config[:id])
                end

                # only called directly from here and tests
                def scope_value(name, scope, value_str)
                  # do_puts = %i[x y].include?(name)
                  if scope
                    # puts "#{name} 1 value_str = #{value_str}" if do_puts
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
                    # puts "#{name} 2 value_str = #{value_str}" if do_puts
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
                    # puts "#{name} 3 value_str = #{value_str}" if do_puts
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
                            method.to_sym, params, scope
                          )
                          Render.raise_if_false(result, "got false #{method}(#{params.join ','})")
                          result = result.to_s
                          Render.raise_if_empty(result, "empty #{method}(#{params.join(',')})")
                        else
                          result = "#{method}(#{params.join ','})"
                        end
                        result
                      end
                      # puts "POST METHODS #{deepest}: #{value_str}"
                      # replace all simple equations in parentheses
                      reg_str = "[(]#{deepest}[#{esc}](.*?)[)]#{deepest}[#{esc}]"
                      value_str = value_str.gsub(Regexp.new(reg_str)) do
                        value = Evaluate.equation(Regexp.last_match[1])
                        value = "(#{value})" unless value.respond_to?(:round)
                        value.to_s
                      end
                      # puts "POST EQUATIONS #{deepest}: #{value_str}"
                      deepest -= 1
                    end
                    # remove any lingering markers
                    regexp = Regexp.new("([()])[0-9]+[#{esc}]")
                    value_str = value_str.gsub(regexp) { Regexp.last_match[1] }
                    # remove whitespace
                    # value_str.gsub!(/\s/, '')
                    # puts "#{name} 4 value_str = #{value_str}" if do_puts
                  end
                  Evaluate.equation(value_str)
                end

                def dynamic_filter(scope)
                  h = super
                  
                  reset_evaluated
      
                  h[:arguments] = command_parameters(scope)
                  
                  __set_output_dimension(scope)
                  reset_evaluated
                  h
                end

                private


                def __command_name_value(name, value, scope)
                  name = name.to_sym
                  Render.raise_if_false(value, '__command_name_value got nil value')
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
                        result = scope_value(name, scope, conditional[:value])
                        break
                      end
                    end
                    # puts "__command_name_value #{name.class.name} #{name}, #{result.class.name} #{result}"
                    raise(Error::JobInput, 'zero true conditions') unless condition_is_true
                  else
                    result = scope_value(name, scope, value)
                  end
                  result = Evaluate.equation(result)
                  result = Evaluate.coerce_number(result) # ShellHelper.escape(result)

                  # puts "#{self.class.name}##{__method__} #{name.class.name} #{name}, #{result.class.name} #{result}"
                  @evaluated[name] = result
                  [name, result]
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
                  scope&.each { |k, v| bind[k.to_sym] = Evaluate.coerce_number(v) }
                  bind
                end

                def __set_output_dimension(scope)
                  dimension_keys = __filter_dimension_keys(@id)
                  dimension_keys&.each do |w_or_h, keys|
                    keys.each do |key|
                      next unless @evaluated[key]

                      value = @evaluated[key]
                      
                      if value.respond_to?(:round)
                        # puts "#{id} #{w_or_h} = #{evaluated}"
                        scope["mm_in_#{w_or_h}".to_sym] = evaluated 
                      end
                      break
                    end
                  end
                end
              end
            end

            module FilterHash
              class << self
                def create(*args)
                  # puts "#{self.name}##{__method__} args: #{args}"
                  
                  FilterHashClass.new(*args)
                end
              end
              
              class FilterHashClass < Filter::FilterClass
                attr_reader :hash

                def initialize(id, hash)
                  # puts "#{self.class.name}##{__method__}(#{id}, #{hash})"

                  # either coerce values to numeric or shell escape them
                  @hash = hash.map do |name, value|
                    [name, Evaluate.coerce_number(value)] # ShellHelper.escape(value)]
                  end
                  super(id)
                end

                def dynamic_filter(*)
                  # puts "#{self.class.name}##{__method__} hash: #{hash}"
                  super.merge(arguments: hash)
                end
              end
              
              module FilterSource
              
                # base filter source
                class FilterSourceClass < FilterHash::FilterHashClass
                  attr_reader :input
                  
                  def initialize(input)
                    @input = input
                    # filename: @input[:cached_file]
                    super('movie', {})
                  end
                  
                  def filter_scope(scope)
                    return unless input[:dimensions]

                    scope[:mm_in_w], scope[:mm_in_h] = input[:dimensions].split('x').map(&:to_f)
                    scope
                  end

                  def dynamic_filter(scope)
                    super(filter_scope(scope))
                  end
                end
                
                module FilterSourceRaw

                  # base raw source
                  class FilterSourceRawClass < FilterSource::FilterSourceClass
                   
                  end

                  # video source
                  module FilterSourceVideo
                    class << self
                      def create(*args)
                        # puts "#{self.name}##{__method__} args: #{args}"
                        
                        FilterSourceVideoClass.new(*args)
                      end
                    end
                    
                    class FilterSourceVideoClass < FilterSourceRaw::FilterSourceRawClass
                      def inputs
                        [{ i: @input[:cached_file] }]
                      end
                    end
                  end
                  
                  # image source
                  module FilterSourceImage
                    class << self
                      def create(*args)
                        # puts "#{self.name}##{__method__} args: #{args}"
                        
                        FilterSourceImageClass.new(*args)
                      end
                    end

                    class FilterSourceImageClass < FilterSourceRaw::FilterSourceRawClass
                      def inputs
                        [{ loop: 1, i: @input[:cached_file] }]
                      end
                    end
                  end
                end
              end
            end
          end

          class << self
            def create(*args)
              # puts "#{self.name}##{__method__} args: #{args}"
                  
              ChainClass.new(*args)
            end
          end
          
          class ChainClass
            attr_reader :filters

            def dynamic_filters(scope)
              # puts "#{self.class.name}##{__method__} filter count: #{filters.count}"
              array = []
              filters.each do |filter|
                if filter.is_a?(Filter::FilterClass)
                  array << filter.dynamic_filter(scope)
                else
                  array.concat(filter.dynamic_filters(scope))
                end
              end
              array.compact
            end

            def initialize
              @filters = []
              initialize_filters
            end

            def initialize_filters
              # override me
            end

            def add_filter(filter)
              filters << filter
            end
          end
          
          # a chain of effects
          module ChainEffects
            class << self
              def create(*args)
                # puts "#{self.name}##{__method__} args: #{args}"
                
                ChainEffectsClass.new(*args)
              end
            end
        
            class ChainEffectsClass < Chain::ChainClass
              attr_reader :input
              def initialize(input)
                @input = input
                super()
              end
              
              def initialize_filters
                return unless Render.populated?(input[:effects]) && input[:effects].is_a?(Array)

                input[:effects].reverse.each do |effect|
                  effect[:dimensions] = input[:dimensions] unless effect[:dimensions]
                  filters << ChainModule.create(effect)
                end
              end
            end
          end
          
          # a theme or transition filter chain
          module ChainModule
            class << self
              def create(*args)
                # puts "#{self.name}##{__method__} args: #{args}"
                
                ChainModuleClass.new(*args)
              end
            end
            
            class ChainModuleClass < Chain::ChainClass
              attr_reader :input_module
              
              def initialize_filters
                unless Render.populated?(input_module[:filters]) && input_module[:filters].is_a?(Array)
                  raise(Error::JobInput, "no filters #{input_module}")
                end
                module_filters = input_module[:filters].map do |config|
                  # puts "#{self.class.name}##{__method__} config: #{config}"
                  Filter::FilterEvaluated.create(config)
                end
                filters.concat(module_filters)
              end
              
              def initialize(input_module)
                @input_module = input_module
                super()
              end
              
              def input_scope(scope)
                scope = scope.dup # shallow copy, so any objects are just pointers
                properties = input_module[:properties]
                if Render.populated?(properties) && properties.is_a?(Hash)
                  properties.each do |property, ob|
                    scope[property] = input_module[property] || ob[:value]
                    # puts "#{property} = #{scope[property]}"
                  end
                end
                scope
              end

              def dynamic_filters(scope)
                super(input_scope(scope))
              end
            end
          end
          
          # an overlay filter chain
          module ChainOverlay
            class << self
              def create(*args)
                # puts "#{self.name}##{__method__} args: #{args}"
                
                ChainOverlayClass.new(*args)
              end
            end
            
            class ChainOverlayClass < Chain::ChainClass
              def initialize_filters
                @filters << Filter::FilterHash.create('overlay', x: 0, y: 0)
              end
            end
          end

          # a scaler filter chain
          module ChainScaler
            class << self
              def create(*args)
                # puts "#{self.name}##{__method__} args: #{args}"
                
                ChainScalerClass.new(*args)
              end
            end
            
            class ChainScalerClass < Chain::ChainClass
              attr_reader :input
              def initialize(input)
                @input = input
                super()
              end

              def dynamic_filters(scope)
                super(chain_scaler_scope(scope))
              end

              def chain_command_resize(scope, orig_dims, target_dims)
                orig_dims = orig_dims.split('x')
                target_dims = target_dims.split('x')
                orig_w = orig_dims[0].to_i
                orig_h = orig_dims[1].to_i
                target_w = target_dims[0].to_i
                target_h = target_dims[1].to_i
                orig_w_f = orig_w.to_f
                orig_h_f = orig_h.to_f
                target_w_f = target_w.to_f
                target_h_f = target_h.to_f
                simple_scale = (Fill::STRETCH == fill)
                unless simple_scale
                  fill_is_scale = (Fill::SCALE == fill)
                  ratio_w = target_w_f / orig_w_f
                  ratio_h = target_h_f / orig_h_f
                  ratio = __min_or_max(fill_is_scale, ratio_h, ratio_w)
                  simple_scale = (Fill::NONE == fill)
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
                  @filters << __crop_or_pad(scope, gtr, w_scaled, h_scaled, orig_w_f, orig_h_f)
                  simple_scale = !((orig_w == target_w) || (orig_h == target_h))
                end
                return unless simple_scale

                @filters << Filter::FilterHash.create('scale', w: target_w, h: target_h)
              end

              def fill
                @fill ||= input[:fill] || Fill::STRETCH
              end

              def chain_scaler_scope(scope)
                @filters = []
                target_dims = scope[:mm_dimensions]
                orig_dims = input[:dimensions] || target_dims
                Render.raise_if_false(orig_dims, 'input dimensions nil')
                Render.raise_if_false(target_dims, 'output dimensions nil')
                chain_command_resize(scope, orig_dims, target_dims) if orig_dims != target_dims
                if Fill::STRETCH == fill
                  @filters << Filter::FilterHash.create('setsar', sar: 1, max: 1)
                end
                scope
              end

              def __crop_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
                Filter::FilterHash.create(
                  'crop',
                  w: w_scaled.to_i,
                  h: h_scaled.to_i,
                  x: ((orig_w_f - w_scaled) / FloatUtil::TWO).ceil.to_i,
                  y: ((orig_h_f - h_scaled) / FloatUtil::TWO).ceil.to_i
                )
              end

              def __crop_or_pad(scope, gtr, w_scaled, h_scaled, orig_w_f, orig_h_f)
                if gtr
                  __crop_filter(w_scaled, h_scaled, orig_w_f, orig_h_f)
                else
                  __pad_filter(scope, w_scaled, h_scaled, orig_w_f, orig_h_f)
                end
              end

              def __min_or_max(fill_is_scale, ratio_h, ratio_w)
                if fill_is_scale
                  FloatUtil.min(ratio_h, ratio_w)
                else
                  FloatUtil.max(ratio_h, ratio_w)
                end
              end

              def __pad_filter(scope, w_scaled, h_scaled, orig_w_f, orig_h_f)
                Filter::FilterHash.create(
                  'pad',
                  color: Segment::Mash.color_value(scope[:backcolor]),
                  w: w_scaled.to_i, h: h_scaled.to_i,
                  x: ((w_scaled - orig_w_f) / FloatUtil::TWO).floor.to_i,
                  y: ((h_scaled - orig_h_f) / FloatUtil::TWO).floor.to_i
                )
              end
            end
          end
          
        end
        
        # base for all layers - LayerRaw, LayerModule, and descendents
        class LayerClass
          attr_reader :output, :input, :chains,  :merger_chain, :scaler_chain, :effects_chain
          # :range,

          def dynamic_filters(scope, render_range = nil)
            scope = layer_scope(scope)
            # chains include effects and scaling, but not trim
            filters = chains.map { |chain| chain.dynamic_filters(scope) }.flatten
            filters.concat(__trim_filters(render_range)) if render_range
            filters
          end

          def initialize(input, output)
            @output = output
            @input = input
            @chains = []
            initialize_chains
          end

          def initialize_chains
            @merger_chain =
              if input[:merger]
                input[:merger][:dimensions] ||= input[:dimensions]
                Chain::ChainModule.create(input[:merger])
              else
                Chain::ChainOverlay.create
              end

            if input[:scaler]
              input[:scaler][:dimensions] ||= input[:dimensions]
              @scaler_chain = Chain::ChainModule.create(input[:scaler])
            else
              @scaler_chain = Chain::ChainScaler.create(input)
            end
            @effects_chain = Chain::ChainEffects.create(input)
            chains << @scaler_chain
            chains << @effects_chain
          end

          def inputs
            []
          end

          def layer_scope(scope)
            Render.raise_if_false(input[:length], "no input length #{input}")
            scope[:mm_duration] = input[:length]
            scope[:mm_t] = "(t/#{scope[:mm_duration]})"
            
            scope
          end

          def dynamic_overlay(scope)
            merger_chain.dynamic_filters(layer_scope(scope)).first[:arguments]
          end

          def range
            (input ? input[:range] : nil)
          end

          private
        
          def __trim_filters(render_range)
            array = []
            if render_range && range && range != render_range
              range_start = render_range.start_seconds
              range_end = render_range.end_seconds
              input_start = range.start_seconds
              input_end = range.end_seconds
              if range_start > input_start || range_end < input_end
                item = {
                  name: 'trim',
                  arguments: { duration: Evaluate.coerce_if_numeric(render_range.length_seconds) }
                }
                if range_start > input_start
                  item[:arguments][:start] =  Evaluate.coerce_if_numeric(
                    FloatUtil.precision(range_start - input_start)
                  )
                end
                array << item
                array << {
                  name: 'setpts',
                  arguments: { expr: 'PTS-STARTPTS' }
                }
              end
            end
            array
          end
        end

        module LayerModule
          # base class for a theme or transition layer
          # LayerTheme, LayerTransition
          class LayerModuleClass < Layer::LayerClass
            def layer_scope(scope)
              scope = super(scope)
              # puts "LayerModule setting scope input dimensions to mm_dimensions #{scope[:mm_dimensions]}"
              scope[:mm_input_dimensions] = scope[:mm_dimensions]
              raise('no input dimensions') unless scope[:mm_input_dimensions]

              w, h = scope[:mm_input_dimensions].split('x')
              scope[:mm_input_width] = w
              scope[:mm_input_height] = h

              scope
            end
          end
          
          module LayerTheme
            class << self
              def create(*args)
                # puts "#{self.name}##{__method__} args: #{args}"
                
                LayerThemeClass.new(*args)
              end
            end
                      
            # a theme layer
            class LayerThemeClass < LayerModule::LayerModuleClass
              def initialize_chains
                # puts "#{self.class.name}##{__method__}"
                chains << Chain::ChainModule.create(input)
                super
              end
            end
          end
          
        end

        module LayerRaw
          # base class for LayerRawVideo, LayerRawImage
          class LayerRawClass < Layer::LayerClass
            def inputs
              [input]
            end

            def layer_scope(scope)
              scope = super(scope)

              # puts "LayerRaw setting scope input dimensions #{input[:dimensions]}"
              
              scope[:mm_input_dimensions] = input[:dimensions]
              raise 'no input dimensions' unless scope[:mm_input_dimensions]

              w, h = scope[:mm_input_dimensions].split('x')
              scope[:mm_input_width] = w
              scope[:mm_input_height] = h
     
              scope
            end            
          end
          
          # a raw image layer
          module LayerRawImage
           class << self
            def create(*args)
              # puts "#{self.name}##{__method__} args: #{args}"
              
                LayerRawImageClass.new(*args)
              end
            end
            
            class LayerRawImageClass < LayerRaw::LayerRawClass
              # def initialize_chains
              #   chain = Chain.create
              #   @filter_movie = Chain::Filter::FilterHash::FilterSource::FilterSourceRaw::FilterSourceImage.create(input)
              #   chain.add_filter(@filter_movie)
              #   chains << chain
              #   super
              # end
            end            
          end
          
          module LayerRawVideo
           class << self
            def create(*args)
              # puts "#{self.name}##{__method__} args: #{args}"
              
                LayerRawVideoClass.new(*args)
              end
            end
            
            # a raw video layer
            class LayerRawVideoClass < LayerRaw::LayerRawClass
              def initialize_chains
                # puts "#{self.class.name}##{__method__}"
                #   @filter_movie = Chain::Filter::FilterHash::FilterSource::FilterSourceRaw::FilterSourceVideo.create(input)
                # chain.add_filter(@filter_movie)
                
                if (Type::VIDEO == output[:type]) 
                  chain = Chain.create
                  # these will cause problems if added to image output
                  # trim filter, if needed
                  trim_filter = __filter_trim_input
                  chain.add_filter(trim_filter) if trim_filter
                  # set frame rate
                  chain.add_filter(Chain::Filter::FilterHash.create('fps', fps: output[:video_rate]))
                  # set presentation timestamp filter
                  chains << chain
                end
                super
                # puts "#{self.class.name}##{__method__} #{chains}"
              end

              def __filter_trim_input
                filter = nil
                raise 'no offset' unless input[:offset]

                offset = input[:offset]
                raise 'no length' unless input[:length]

                length = input[:length]
                trim_beginning = FloatUtil.gtr(offset, FloatUtil::ZERO)
                trim_end = FloatUtil.gtr(length, FloatUtil::ZERO)
                trim_end &&= (input[:duration].to_f > (offset + length))
                if trim_beginning || trim_end
                  # start and duration look at timestamp and change it
                  filter = Chain::Filter::FilterHash.create('trim', duration: FloatUtil.precision(length))
                  filter.hash[:start] = FloatUtil.precision(offset) if trim_beginning
                end
                filter
              end
            end
          end
        end
      end

    end
    
    class << self
      def command_from_chain(filters)
        array = []
        filters_length = filters.length
        filters.each do |filter|
          array << Render.command_from_filter(filter)
        end
        Render.join_commands(array)
      end

      def command_from_filter(filter)
        filter_name = filter[:name]
        
        array = []
        array << filter_name
        args = filter[:arguments]
        arguments_length = args.count
        unless arguments_length.zero?
          array << args.keys.map { |k| "#{k}=#{args[k]}" }.join(':')
        end
        array.join('=')
      end

      def join_commands(cmds)
        joined_commands = []
        cmds = cmds.reject(&:empty?)
        c = cmds.length
        cmds.each_with_index do |cmd, i|
          cmd = "#{cmd}," unless (i.zero? && cmd.end_with?(':v]')) || i == c - 1
          joined_commands << cmd
        end
        joined_commands.join
      end
      def populated?(thing)
        thing && !thing.empty?
      end
      
      def raise_if_empty(string, msg)
        raise(Error::JobInput, msg) if string.empty?
      end     
       
      def raise_if_false(boolean, msg)
        raise(Error::JobInput, msg) unless boolean
      end
    end
  end
end
