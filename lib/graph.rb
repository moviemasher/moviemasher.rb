
module MovieMasher	
# Public: chain
	class Chain
		def << filter
			@filters << filter
		end
		def chain_command scope, job_output
			cmds = Array.new
			@filters.each do |filter|
				if filter.is_a? Filter
					cmd = filter.filter_command(scope, job_output)
				else
					cmd = filter.chain_command(scope, job_output)
				end
				cmds << cmd if cmd and not cmd.empty?
			end
			cmds.join(',')
		end
		def initialize input = nil, job_input = nil
			@input = input
			@job_input = job_input
			@filters = Array.new
			#puts "Chain calling #initialize_filters"
			initialize_filters
		end
		def initialize_filters
			# override me
		end
	end
	class ChainEffects < Chain
		def initialize_filters
			if @input[:effects] and @input[:effects].is_a?(Array) and not @input[:effects].empty? then
				@input[:effects].each do |effect|
					effect[:dimensions] = @input[:dimensions] unless effect[:dimensions]
					@filters << ChainModule.new(effect, @job_input, @input)
				end
			end
		end
	end
	class ChainModule < Chain
		attr_writer :input
		def initialize mod_input, mash_input, applied_input # is same as mod_input for themes
			raise Error::Parameter.new "no mod_input" unless mod_input
			raise Error::Parameter.new "no mash_input" unless mash_input
			raise Error::Parameter.new "no applied_input" unless applied_input
			
			@applied_input = applied_input
			super mod_input, mash_input
		end
		def initialize_filters
			if @input[:filters] and @input[:filters].is_a? Array and not @input[:filters].empty? then
				@input[:filters].each do |filter_config|
					@filters << FilterEvaluated.new(filter_config, @job_input, @applied_input)
				end
			else 
				raise Error::JobInput.new "ChainModule.initialize with no filters #{@input}"
			end
		end
		def chain_command scope, job_output
			scope = input_scope scope
			super
		end
		def input_scope scope
			scope = scope.dup # shallow copy, so any objects are just pointers
			if @input[:properties] and @input[:properties].is_a? Hash and not @input[:properties].empty? then
				@input[:properties].each do |property, ob|
					scope[property] = @input[property] || ob[:value]
				end
			end
			scope
		end
	end
	class ChainOverlay < Chain
		def initialize job_output
			super nil, job_output
		end
		def initialize_filters
			@filters << FilterHash.new('overlay', :x => 0, :y => 0)
		end
	end
	class ChainScaler < Chain
		def initialize input = nil, job_input = nil
			super
			@input_dimensions = @input[:dimensions]
			@fill = @input[:fill] || Fill::Stretch
		end
		def chain_command scope, job_output
			@filters = Array.new
			target_dims = scope[:mm_dimensions]
			orig_dims = @input_dimensions || target_dims
			raise Error::JobInput.new "input dimensions nil" unless orig_dims
			raise Error::JobInput.new "output dimensions nil" unless target_dims
			orig_dims = orig_dims.split('x')
			target_dims = target_dims.split('x')
			if orig_dims != target_dims then
				orig_w = orig_dims[0].to_i
				orig_h = orig_dims[1].to_i
				target_w = target_dims[0].to_i
				target_h = target_dims[1].to_i
				orig_w_f = orig_w.to_f
				orig_h_f = orig_h.to_f
				target_w_f = target_w.to_f
				target_h_f = target_h.to_f
				simple_scale = (Fill::Stretch == @fill)
				if not simple_scale then
					fill_is_scale = (Fill::Scale == @fill)
					ratio_w = target_w_f / orig_w_f
					ratio_h = target_h_f / orig_h_f
					ratio = (fill_is_scale ? FloatUtil.min(ratio_h, ratio_w) : FloatUtil.max(ratio_h, ratio_w))
					simple_scale = (Fill::None == @fill)
					if simple_scale then
						target_w = (orig_w_f * ratio).to_i
						target_h = (orig_h_f * ratio).to_i
						#puts "#{orig_w}x#{orig_h} / #{ratio} (FloatUtil.max(#{ratio_h}, #{ratio_w})) = #{target_w}x#{target_h}"
					else
						target_w_scaled = target_w_f / ratio
						target_h_scaled = target_h_f / ratio
						simple_scale = (FloatUtil.cmp(orig_w_f, target_w_scaled) and FloatUtil.cmp(orig_h_f, target_h_scaled))
					end
				end
				if not simple_scale then
					if (FloatUtil.gtr(orig_w_f, target_w_scaled) or FloatUtil.gtr(orig_h_f, target_h_scaled))
						@filters << FilterHash.new('crop', 
							:w => target_w_scaled.to_i, 
							:h => target_h_scaled.to_i, 
							:x => ((orig_w_f - target_w_scaled) / FloatUtil::Two).ceil.to_i,
							:y => ((orig_h_f - target_h_scaled) / FloatUtil::Two).ceil.to_i,
						)
					else
						backcolor = ((@job_input[:mash] and @job_input[:mash][:backcolor]) ? Graph.color_value(@job_input[:mash][:backcolor]) : 'black')
						@filters << FilterHash.new('pad', 
							:color => backcolor,
							:w => target_w_scaled.to_i, 
							:h => target_h_scaled.to_i, 
							:x => ((target_w_scaled - orig_w_f) / FloatUtil::Two).floor.to_i,
							:y => ((target_h_scaled - orig_h_f) / FloatUtil::Two).floor.to_i,
						)
					end
					simple_scale = ! ((orig_w == target_w) or (orig_h == target_h))
				end
				@filters << FilterHash.new('scale', :w => target_w, :h => target_h) if simple_scale
				@filters << FilterHash.new('setsar', :sar => 1, :max => 1) if Fill::Stretch == @fill
			end
			super
		end
	end
	class Filter 
		@@outsize = Hash.new
		attr_reader :id
		attr_writer :disabled
		def initialize id = nil
			@id = id || ''
			@disabled = false
		end
		def filter_command scope, job_output
			(@disabled ? '' : @id)
		end
		def filter_name
			@id
		end
	end
	class FilterEvaluated < Filter
		attr_reader :parameters
		def filter_command scope = nil, job_output = nil
			cmd = super
			unless cmd.empty?
				@evaluated = Hash.new
				cmds = Array.new
				cmds << cmd
				if scope
					if @@outsize['w'] and @@outsize['h']
						scope[:mm_in_w] = @@outsize['w'] 
						scope[:mm_in_h] = @@outsize['h'] 
						#puts "<< #{scope[:mm_in_w]}x#{scope[:mm_in_h]} #{@id}"
					else 
						scope[:mm_in_w] = 'in_w'
						scope[:mm_in_h] = 'in_h'
					end
				end
				cmd = command_parameters(scope, job_output)
				if cmd and not cmd.empty?
					cmds << '='
					cmds << cmd
				end
				cmd = cmds.join ''
				dimension_keys = __filter_dimension_keys @id
				if dimension_keys 
					dimension_keys.each do |w_or_h, keys|
						keys.each do |key|
							if @evaluated[key]
								evaluated = @evaluated[key]
								if evaluated.respond_to? :round
									@@outsize[w_or_h] = evaluated
									#puts ">> #{w_or_h} => #{@@outsize[w_or_h]} = #{@evaluated[key]} #{@id}"
								#else
								#puts "! >> #{evaluated} = #{@evaluated[key]} #{@id}"
								end
								break
							end
						end
					end 
				end
				@evaluated = nil
			end
			cmd
		end
		def command_parameters scope, job_output
			cmds = Array.new
			 if @parameters
				raise Error::JobInput.new "parameters must be an array" unless @parameters.is_a? Array
				@parameters.each do |parameter|
					raise Error::JobInput.new "parameter is not a hash #{parameter}" unless parameter.is_a? Hash
					#puts "#{parameter[:name]}=#{parameter[:value]}"
					name = parameter[:name]
					evaluated = parameter[:value]
					cmds << __command_name_value(name, evaluated, scope, job_output)
				end
			end
			cmds.join ':'
		end
		def initialize filter_config, mash_input = nil, applied_input = nil # same as filter_config for themes
			super filter_config[:id]
			@mash_input = mash_input
			@applied_input = applied_input
			@config = filter_config
			@parameters = @config[:parameters]
			unless @parameters
				sym = filter_config[:id].capitalize.to_sym
				@parameters = Parameters.const_get(sym) if Parameters.const_defined? sym
				@parameters = Array.new unless @parameters
			end
			raise Error::Parameter.new "no config" unless @config
			#raise Error::Parameter.new "no applied_input" unless @applied_input
			#raise Error::Parameter.new "no mash_input" unless @mash_input
	  	end
	  	def __command_name_value name, value, scope, job_output
	  		raise Error::JobInput.new "__command_name_value got nil value" unless value
			#puts "__command_name_value #{value}"
			result = value
			if value.is_a? Array 
				bind = __filter_scope_binding scope
				condition_is_true = false
				value.each do |conditional|
					condition = conditional[:condition]
					if conditional[:is]
						# not strict equality since we may have numbers and strings
						condition += '==' + conditional[:is].to_s;
					elsif conditional[:in]
						conditional[:in] = conditional[:in].split(',') unless conditional[:in].is_a? Array
						condition = '[' + conditional[:in].join(',') + '].include?((' + condition + ').' + (conditional[:in][0].is_a?(String) ? 'to_s' : 'to_i') + ')'
					end
					condition_is_true = bind.eval(condition)
					if condition_is_true then
						result = __filter_parse_scope_value scope, conditional[:value].to_s, job_output
						break
					end
				end
				raise Error::JobInput.new "no conditions were true" unless condition_is_true
			else
				result = __filter_parse_scope_value scope, value.to_s, job_output
			end
			result = Evaluate.equation result
	  		@evaluated[name] = result
			"#{name}=#{result.to_s}"
		end
		def __filter_parse_scope_value scope, value_str, job_output = nil
			if scope
				#puts "value_str = #{value_str}"
				level = 0
				deepest = 0
				esc = '~'
				# expand variables
				value_str = value_str.dup
				value_str.gsub!(/([\w]+)/) do |match|
					match_str = match.to_s
					match_sym = match_str.to_sym
					if scope[match_sym] then
						scope[match_sym].to_s 
					else
						match_str
					end
				end
				#puts "value_str = #{value_str}"

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
				#puts "value_str = #{value_str}"
				while 0 < deepest
					#puts "PRE #{deepest}: #{value_str}"
					value_str.gsub!(Regexp.new("([a-z_]+)[(]#{deepest}[#{esc}](.*?)[)]#{deepest}[#{esc}]")) do
						method = $1
						param_str = $2
						params = param_str.split(',')
						params.map! do |param|
							param.strip #!
							#param.gsub!(Regexp.new("([()])[0-9]+[#{esc}]")) { $1 }
						end
						func_sym = method.to_sym
						if FilterHelpers.respond_to? func_sym then
							result = FilterHelpers.send func_sym, params, @mash_input[:mash], scope, job_output
							raise Error::JobInput.new "got false from #{method}(#{params.join ','})" unless result
							result = result.to_s unless result.is_a? String
							raise Error::JobInput.new "got empty from #{method}(#{params.join ','})" if result.empty?
						else
							result = "#{method}(#{params.join ','})"
						end
						result			
					end
					#puts "POST METHODS #{deepest}: #{value_str}"
					# replace all simple equations in parentheses
					value_str.gsub!(Regexp.new("[(]#{deepest}[#{esc}](.*?)[)]#{deepest}[#{esc}]")) do
						evaluated = Evaluate.equation $1
						evaluated = "(#{evaluated})" unless evaluated.respond_to? :round
						evaluated.to_s
					end
					#puts "POST EQUATIONS #{deepest}: #{value_str}"
					deepest -= 1
				end
				# remove any lingering markers
				value_str.gsub!(Regexp.new("([()])[0-9]+[#{esc}]")) { $1 }
				# remove whitespace
				value_str.gsub!(/\s/, '')
				#puts "value_str = #{value_str}"
			end
			Evaluate.equation value_str
		end
		def __filter_dimension_keys filter_id
			case filter_id
			when 'crop'
				{:w => ['w', 'out_w'], :h => ['h', 'out_h'] }
			when 'scale', 'pad'
				{:w => ['w', 'width'], :h => ['h', 'height'] }
			else
				nil
			end
		end
		def __filter_is_source? filter_id
			case filter_id
			when 'color', 'movie'
				true
			else 
				false
			end
		end
		def __coerce s
			sf = s.to_f
			sfs = sf.to_s
			if s == sfs
				s = sf
			else
				si = s.to_i
				sis = si.to_s
				s = si if s == sis
			end
		end
		def __filter_scope_binding scope
			bind = binding
			if scope
				scope.each do |k,v|
					evaluate = "#{k.id2name} = __coerce '#{v}'"
					#puts "__filter_scope_binding evaluate = #{evaluate}"
					bind.eval evaluate
				end
			end
			bind
		end
	end
	class FilterHash < Filter
		def initialize id, hash = nil
			@hash = hash || Hash.new
			super id
		end
		def filter_command scope = nil, job_output = nil
			cmd = super
			unless cmd.empty? then # I'm not disabled
				cmds = Array.new
				@hash.each do |name, value|
					name = name.id2name if name.is_a? Symbol
					cmds << "#{name}=#{value}"
				end
				cmd = "#{cmd}=#{cmds.join ':'}" unless cmds.empty?
			end
			cmd
		end
		def hash
			@hash
		end
	end
	class FilterSetpts < FilterHash
		def initialize(expr = 'PTS-STARTPTS')
			super 'setpts', :expr => expr
		end
	end
	class FilterSource < FilterHash
		def initialize id, hash, dimensions = nil
			super id, hash
			@dimensions = dimensions
		end
		def filter_command scope, job_output
			cmd = super
			unless cmd.empty?
				@@outsize['w'], @@outsize['h'] = @dimensions.split 'x'
				#puts ">> #{@@outsize['w']}x#{@@outsize['h']} #{@id}"
			end
			cmd
		end
	end
	class FilterSourceMovie < FilterSource
		def initialize input, job_input
			@input = input
			@job_input = job_input
			super('movie', {:filename => input[:cached_file]}, input[:dimensions])
		end
		def filter_name
			"#{super} #{File.basename @hash[:filename]}"
		end
	end
	class FilterSourceColor < FilterSource
		def initialize duration, color
			raise Error::JobInput.new "#{filter_name} with no duration" unless duration
			raise Error::JobInput.new "#{filter_name} with no color" unless color
			super('color', {:color => Graph.color_value(color), :duration => duration}) # we don't know dimensions yet
		end
		def filter_command scope, job_output
			raise Error::JobInput.new "#{filter_name} with no size #{job_output}" unless job_output[:dimensions]
			raise Error::JobInput.new "#{filter_name} with no rate #{job_output}" unless job_output[:video_rate]
			@dimensions = @hash[:size] = job_output[:dimensions]
			@hash[:rate] = job_output[:video_rate]
			super
		end
		def filter_name
			"#{super} #{@hash[:color]} #{@dimensions}"
		end
	end
	class Graph
		def self.color_value color
			if color.is_a?(String) and color.end_with?(')') 
				if color.start_with?('rgb(') or color.start_with?('rgba(')
					color_split = color.split('(')
					method = color_split.shift.to_sym
					params = color_split.shift[0..-2]
					color = FilterHelpers.send method, params
				end
			end
			color
		end
		def graph_command output, job = nil
			@job = job
			@job_output = output
		end
		def duration
			@render_range.length_seconds
		end
		def initialize(job_input, render_range = nil, label_name = 'layer')
			@label_name = label_name
			@job_input = job_input
			@render_range = render_range
		end
		def graph_scope
			scope = Hash.new
			scope[:mm_job] = @job
			scope[:mm_render_range] = @render_range
			scope[:mm_fps] = @job_output[:video_rate]			
			scope[:mm_dimensions] = @job_output[:dimensions]
			scope[:mm_width], scope[:mm_height] = scope[:mm_dimensions].split 'x'
			scope
		end	
		def create_layer input
			raise Error::JobInput.new "input hash has no type #{input}" unless input[:type]
			
			case input[:type]
			when Mash::Video
				layer = LayerRawVideo.new input, @job_input
			when Mash::Transition
				layer = LayerTransition.new input, @job_input, @job
			when Mash::Image
				layer = LayerRawImage.new input, @job_input
			when Mash::Theme
				layer = LayerTheme.new input, @job_input
			else
				raise Error::JobInput.new "input hash type invalid #{input}" 
			end
			layer
		end
	end
	class GraphMash < Graph
		def add_new_layer input
			layer = create_layer input
			@layers << layer
			layer
		end
		def graph_command output, job = nil
			super
			graph_cmds = Array.new			
			layer_length = @layers.length
			layer_length.times do |i|
				layer = @layers[i]
				cmd = layer.layer_command graph_scope, @job_output
				cmd += layer.trim_command @render_range, @job_output
				cmd += "[#{@label_name}#{i}]" if 1 < layer_length
				graph_cmds << cmd
			end
			if 1 < layer_length then
				(1..layer_length-1).each do |i|
					raise Error::JobInput.new "layer_length #{layer_length} i #{i} #{@layers}" unless i < @layers.length
					layer = @layers[i]
					cmd = (1 == i ? "[#{@label_name}#{i-1}]" : "[#{@label_name}ed#{i-1}]")
					cmd += "[#{@label_name}#{i}]"
					merge_cmd = layer.merger_command(graph_scope)
				
					raise Error::JobInput.new "merger produced nothing #{layer.inspect}" unless merge_cmd and not merge_cmd.empty?
					cmd += merge_cmd
					if i + 1 < layer_length then
						cmd += "[#{@label_name}ed#{i}]"
					end
					graph_cmds << cmd
				end	
			end
	
			cmd = graph_cmds.join ';'
			cmd
		end
		def initialize(mash_input, render_range, label_name = 'layer') # a mash input, and a range within it to render
			super
			@layers = Array.new
			@layers << LayerColor.new(duration, mash_input[:mash][:backcolor])
		end
		def graph_scope
			scope = super
			backcolor = @backcolor
			if backcolor then
				backcolor = backcolor.to_s.strip
				# it might be an rgb
				backcolor = FilterHelpers.rgb(backcolor[4..-2]) if backcolor.start_with?('rgb(') and backcolor.end_with?(')') 
			else 
				backcolor = 'black'
			end
			scope
		end	
	end
	class GraphRaw < Graph
		def graph_command output, job = nil
			super
			cmd = @layer.layer_command graph_scope, @job_output
			cmd += @layer.trim_command @render_range, @job_output
			cmd
		end
		def initialize input # a video or image input
			super input, input[:range]
			@layer = create_layer input
		end
	end
	class Layer # all layers - LayerRaw, LayerModule
		def merger_command scope
			@merger_chain.chain_command scope, @job_output
		end
		def initialize input, job_input
			@input = input
			@job_input = job_input # will be different than input if we're in a mash
			@range = input[:range]
			@chains = Array.new
			initialize_chains
		end
		def initialize_chains
			if @input[:merger] 
				@input[:merger][:dimensions] = @input[:dimensions] unless @input[:merger][:dimensions]
				@merger_chain = ChainModule.new @input[:merger], @job_input, @input
			else 
				@merger_chain = ChainOverlay.new @job_input
			end
			if @input[:scaler]
				@input[:scaler][:dimensions] = @input[:dimensions] unless @input[:scaler][:dimensions]
				@scaler_chain = ChainModule.new @input[:scaler], @job_input, @input
			else
				@scaler_chain = ChainScaler.new @input, @job_input
			end
			@effects_chain = ChainEffects.new @input, @job_input
			@chains << @scaler_chain
			@chains << @effects_chain
		end 
		def layer_scope scope, job_output
			@job_output = job_output
			raise "no length" unless @input[:length]
			scope[:mm_duration] = @input[:length]
			scope[:mm_t] = "(t/#{scope[:mm_duration]})"
		end
		def layer_command scope, job_output
			layer_scope scope, job_output
			cmds = Array.new
			@chains.each do |chain|
				chain_cmd = chain.chain_command(scope, job_output)
				cmds << chain_cmd if chain_cmd and not chain_cmd.empty?
			end
			cmds.join(',')
		end
		def range
			(@input ? @input[:range] : nil)
		end
		def trim_command render_range, job_output
			input_range = range
			#puts "command_range_trim #{input_range}"
			cmd = ''
			if render_range and input_range and not input_range.equals?(render_range) then
				#puts "render_range #{render_range.inspect}"
				#puts "input_range #{input_range.inspect}"
				range_start = render_range.start_seconds
				range_end = render_range.end_seconds
				input_start = input_range.start_seconds
				input_end = input_range.end_seconds
				if range_start > input_start or range_end < input_end then
					cmd += ",trim=duration=#{render_range.length_seconds}"
					cmd += ":start=#{FloatUtil.precision(range_start - input_start)}" if range_start > input_start
					cmd += ',setpts=expr=PTS-STARTPTS'
				end
			end
			cmd
		end
	end
	class LayerColor 
		def initialize duration, color
			@filter = FilterSourceColor.new duration, color
		end
		def layer_command scope, job_output
			@filter.filter_command scope, job_output
		end
		def trim_command render_range, job_output
			''
		end
		def range 
			nil
		end
	end
	class LayerModule < Layer # LayerTheme, LayerTransition
		def layer_scope scope, job_output
			scope[:mm_input_dimensions] = scope[:mm_dimensions]
			raise "no input dimensions" unless scope[:mm_input_dimensions]
			scope[:mm_input_width], scope[:mm_input_height] = scope[:mm_input_dimensions].split 'x'
			super
		end
	end
	class LayerRaw < Layer # LayerRawVideo, LayerRawImage
		def layer_command scope, job_output
			scope[:mm_input_dimensions] = @input[:dimensions]
			raise "no input dimensions" unless scope[:mm_input_dimensions]
			#puts "setting input dimensions #{scope[:mm_input_dimensions]} for #{@input[:id]}"
			scope[:mm_input_width], scope[:mm_input_height] = scope[:mm_input_dimensions].split 'x'
			super
		end
	end
	class LayerRawImage < LayerRaw
		def initialize_chains
			chain = Chain.new nil, @job_input
			# we will need to change movie_filter path, since we'll be building video file from image for each output
			@movie_filter = FilterSourceMovie.new @input, @job_input
			chain << @movie_filter
			@filter_timestamps = FilterSetpts.new 'N'
			chain << @filter_timestamps
			@chains << chain
			super
		end
		def layer_command scope, job_output
			raise Error::JobInput.new "input has no cached_file #{@input.inspect}" unless @input[:cached_file]
			output_type_is_not_video = (Output::TypeVideo != job_output[:type])
			@movie_filter.hash[:loop] = (output_type_is_not_video ? 1 : (scope[:mm_fps].to_f * FloatUtil.precision(@input[:length])).round.to_i)
			@filter_timestamps.disabled = output_type_is_not_video
			@movie_filter.hash[:filename] = @input[:cached_file]
			super
		end
	end
	class LayerRawVideo < LayerRaw
		def initialize_chains
			#puts "LayerRawVideo#initialize_chains"
			chain = Chain.new nil, @job_input
			chain << FilterSourceMovie.new(@input, @job_input)
			# trim filter, if needed
			@trim_filter = __filter_trim_input
			chain << @trim_filter if @trim_filter
			# fps is placeholder since each output has its own rate
			@fps_filter = FilterHash.new('fps', :fps => 0)
			chain << @fps_filter
			# set presentation timestamp filter 
			@filter_timestamps = FilterSetpts.new
			chain << @filter_timestamps
			@chains << chain
			super
			#puts "LayerRawVideo.initialize_chains #{@chains}"
		end
		def layer_command scope, job_output
			raise Error::JobInput.new "layer_command with empty scope" unless scope
			output_type_is_not_video = (Output::TypeVideo != job_output[:type])
			#puts "output_type_is_not_video = #{output_type_is_not_video}"
			@fps_filter.disabled = output_type_is_not_video
			@trim_filter.disabled = output_type_is_not_video if @trim_filter
			@filter_timestamps.disabled = output_type_is_not_video
			@fps_filter.hash[:fps] = scope[:mm_fps]
			super
		end
		def __filter_trim_input
			filter = nil
			raise "no offset" unless @input[:offset]
			offset = @input[:offset]
			raise "no length" unless @input[:length]
			length = @input[:length]
			trim_beginning = FloatUtil.gtr(offset, FloatUtil::Zero)
			trim_end = FloatUtil.gtr(length, FloatUtil::Zero) and (@input[:duration].to_f > (offset + length))
			if trim_beginning or trim_end then
				# start and duration look at timestamp and change it
				filter = FilterHash.new('trim', :duration => FloatUtil.precision(length))
				filter.hash[:start] = FloatUtil.precision(offset) if trim_beginning
			end
			filter
		end
	end
	class LayerTheme < LayerModule
		def initialize_chains
			#puts "LayerTheme.initialize_chains"
			@chains << ChainModule.new(@input, @job_input, @input)
			super
		end
	end
	class LayerTransition < LayerModule
		def add_new_layer clip
			layer_letter = 'a'
			@graphs.length.times { layer_letter.next! }
			layer_label = "#{layer_letter}_#{Mash::Transition}"
			graph = GraphMash.new(@job_input, @input[:range], layer_label)
			graph.add_new_layer clip
			@graphs << graph
		end
		def initialize input, job_input, job
			@job = job
			super input, job_input
			@graphs = Array.new		
		end
		def layer_command scope, job_output
			layer_scope scope, job_output # sets @job_output and mm_duration, mm_t in scope
			layer_letter = 'a'
			cmds = Array.new
			merge_cmds = Array.new
			last_label = '[transback]'
			backcolor_cmd = @color_layer.layer_command(scope, @job_output) + last_label
			@graphs.length.times do |i|
				graph = @graphs[i]
				layer_label = "#{layer_letter}_#{Mash::Transition}"
				cmd = graph.graph_command job_output, @job
				layer_chain = @layer_chains[i]
				cmd += ','
				cmd += layer_chain[:scaler].chain_command scope, @job_output
				if layer_chain[:filters] then
					chain_cmd = layer_chain[:filters].chain_command scope, @job_output
					if chain_cmd and not chain_cmd.empty? then
						cmd += ','
						cmd += chain_cmd
					end
				end
				cur_label = "[#{layer_label}]"
				cmd += cur_label
				cmds << cmd		
				
				cmd = last_label
				cmd += cur_label
				cmd += @layer_chains[i][:merger].chain_command scope, @job_output
				last_label = "[#{layer_label}ed]"
				cmd += last_label if 0 == i
				merge_cmds << cmd
				
				layer_letter.next!
			end
			cmds << backcolor_cmd
			cmds += merge_cmds
			cmds.join ';'
		end
		def initialize_chains
			#puts "LayerTransition.initialize_chains #{@input}"
			super
			@layers = Array.new
			@layer_chains = [{},{}]
			@layer_chains[0][:filters] = ChainModule.new(@input[:from], @job_input, @input) if @input[:from][:filters] and not @input[:from][:filters].empty?
			@layer_chains[1][:filters] = ChainModule.new(@input[:to], @job_input, @input) if @input[:to][:filters] and not @input[:to][:filters].empty?
			@layer_chains[0][:merger] = ChainModule.new(@input[:from][:merger], @job_input, @input) 
			@layer_chains[1][:merger] = ChainModule.new(@input[:to][:merger], @job_input, @input)
			@layer_chains[0][:scaler] = ChainModule.new(@input[:from][:scaler], @job_input, @input) 
			@layer_chains[1][:scaler] = ChainModule.new(@input[:to][:scaler], @job_input, @input)
			mash_source = @job_input[:mash]
			mash_color = mash_source[:backcolor]
			@color_layer = LayerColor.new(@input[:range].length_seconds, mash_color)
		end
	end
end
