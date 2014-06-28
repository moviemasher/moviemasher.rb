
module MovieMasher	
	class Layer
		attr_reader :range
		def initialize chain = nil, range = nil
			@chains = Array.new
			@chains << chain if chain
			@range = range
		end
		def command options
			cmds = Array.new
			@chains.each do |chain|
				chain_cmd = chain.command(options)
				#puts "Layer#command got no chain command from #{chain}" unless chain_cmd and not chain_cmd.empty?
				#puts "\nchain_cmd = #{chain_cmd}\n"
				cmds << chain_cmd if chain_cmd and not chain_cmd.empty?
			end
			cmds.join(',')
		end
	end
	class InputLayer < Layer # VideoLayer, ImageLayer, ThemeLayer, TransitionLayer
		attr_reader :input
		def self.create input = nil
			raise "input is not a hash #{input}" unless input.is_a? Hash
			raise "input hash has no type #{input}" unless input[:type]
			case input[:type]
			when MovieMasher::TypeVideo
				layer = VideoLayer.new input
			when MovieMasher::TypeTransition
				layer = TransitionLayer.new input
			when MovieMasher::TypeImage
				layer = ImageLayer.new input
			when MovieMasher::TypeTheme
				layer = ThemeLayer.new input
			else
				raise "input hash type invalid #{input}" 
			end
			layer
		end
		
		def initialize input
			@input = input
			super nil, input[:range]
			#puts "InputLayer calling #initialize_chains"
			initialize_chains
			@input[:merger][:dimensions] = @input[:dimensions] if @input[:merger] and not @input[:merger][:dimensions]
			@input[:scaler][:dimensions] = @input[:dimensions] if @input[:scaler] and not @input[:scaler][:dimensions]
			#puts "input has no dimensions #{@input}" unless @input[:dimensions]
			@merger_chain = (@input[:merger] ? FilterChain.new(@input[:merger]) : OverlayChain.new)
			@scaler_chain = (@input[:scaler] ? FilterChain.new(@input[:scaler]) : FillChain.new(@input[:dimensions], @input[:fill]))
			@effects_chain = EffectsChain.new @input
			@chains << @scaler_chain
			@chains << @effects_chain
		end
		
		def command_merger options
			@merger_chain.command options
		end
		def initialize_chains
			#puts "InputLayer#initialize_chains"
		end
		
		def __filter_timestamps
			HashFilter.new 'setpts', :expr => 'PTS-STARTPTS'
		end

		def __get_length
			__get_time :length
		end
		def __get_range
			range = MovieMasher::FrameRange.new(@input[:start], 1, 1)
			range.scale(@input[:fps]) if TypeVideo == @input[:type]
			range
		end	
		def __get_time key
			length = FLOAT_ZERO
			if float_gtr(@input[key], FLOAT_ZERO) then
				sym = "#{key.id2name}_is_relative".to_sym
				if @input[sym] then
					if float_gtr(@input[:duration], FLOAT_ZERO) then
						if '%' == @input[sym] then
							length = (@input[key] * @input[:duration]) / FLOAT_HUNDRED
						else 
							length = @input[:duration] - @input[key]
						end
					end
				else 
					length = @input[key]
				end
			elsif :length == key and float_gtr(@input[:duration], FLOAT_ZERO) then
				@input[key] = @input[:duration] - __get_trim
				length = @input[key]
			end
			length
		end
		def __get_trim
			__get_time :trim
		end
	end
	class ImageLayer < InputLayer
		def initialize_chains
			#puts "ImageLayer#initialize_chains"
			chain = Chain.new
			# path is a placeholder, since we'll be building video file from image for each output
			@movie_filter = HashFilter.new('movie', :filename => @input[:cached_file])
			chain << @movie_filter
			# fps is placeholder since each output has its own rate
			@fps_filter = HashFilter.new('fps', :fps => 0)
			chain << @fps_filter
			# we need a trim because the video we'll build from image will be artificially long
			@trim_filter = HashFilter.new('trim', :duration => float_precision(@input[:length_seconds]))
			chain << @trim_filter
			@chains << chain
			chain << @fps_filter
		end
		def command options
			fps = options[:mm_fps]
			duration = @input[:length_seconds] || __get_length
			@fps_filter.parameters[:fps] = fps
			@trim_filter.parameters[:duration] = duration
			file = __video_from_image @input[:cached_file], duration, fps
			@movie_filter.parameters[:filename] = file
			super
		end
		def __video_from_image img_file, duration, fps
			frame_time = FrameTime.new ((duration.to_f) * fps.to_f).round.to_i, fps
			frame_time.scale 1, :ceil
			frame_time.frame += 1
			raise "no frame_time from #{duration}@#{fps} #{frame_time.inspect}" unless 0 < frame_time.frame
			parent_dir = File.dirname img_file
			base_name = File.basename img_file
			out_file = "#{parent_dir}/#{base_name}-#{duration}-#{fps}.#{PIPE_VIDEO_EXTENSION}" # INTERMEDIATE_VIDEO_EXTENSION
		
			unless File.exists?(out_file) then
				cmd = ''
				cmd += MovieMasher::__cache_switch('1', 'loop')
				cmd += MovieMasher::__cache_switch(frame_time.fps, 'r')
				cmd += MovieMasher::__cache_switch(img_file, 'i')
				cmd += MovieMasher::__cache_switch('format=pix_fmts=yuv420p', 'filter_complex')
				cmd += MovieMasher::__cache_switch(PIPE_VIDEO_FORMAT, 'f:v')
		
				# (fps.to_f * duration.to_f).floor
				cmd += MovieMasher::__cache_switch(frame_time.frame, 'vframes')
				cmd += MovieMasher::__cache_switch(float_precision(frame_time.get_seconds), 't')
				MovieMasher::__ffmpeg_command cmd, out_file
				#file_duration = __cache_get_info out_file, 'duration'
				#raise "Durations don't match #{file_duration} #{duration}" unless float_cmp(file_duration, duration)
			end
			out_file
		end
	end
	class VideoLayer < InputLayer
		def initialize_chains
			#puts "VideoLayer#initialize_chains"
			chain = Chain.new
			chain << HashFilter.new('movie', :filename => @input[:cached_file])
			# trim filter, if needed
			filter = __filter_trim_input
			chain << filter if filter
			# fps is placeholder since each output has its own rate
			@fps_filter = HashFilter.new('fps', :fps => 0)
			chain << @fps_filter
			# set presentation timestamp filter 
			chain << __filter_timestamps
			@chains << chain
			#puts "VideoLayer.initialize_chains #{@chains}"
		end
		def __filter_trim_input
			filter = nil
			trim_seconds = @input[:trim_seconds] || __get_trim
			length_seconds = @input[:length_seconds] || __get_length
			trim_beginning = float_gtr(trim_seconds, FLOAT_ZERO)
			trim_end = float_gtr(length_seconds, FLOAT_ZERO) and (@input[:duration] > (trim_seconds + length_seconds))
			if trim_beginning or trim_end then
				# start and duration look at timestamp and change it
				filter = HashFilter.new('trim', :duration => float_precision(length_seconds))
				filter.parameters[:start] = float_precision(trim_seconds) if trim_beginning
			end
			filter
		end
		def command options
			@fps_filter.parameters[:fps] = options[:mm_fps]
			super
		end
	end
	class Chain
		def << filter
			@filters << filter
		end
		def command options
			cmds = Array.new
			@filters.each do |filter|
				cmds << filter.command(options)
			end
			cmds.join(',')
		end
		def initialize input = nil
			@input = input
			@filters = Array.new
			#puts "Chain calling #initialize_filters"
			initialize_filters
		end
		def initialize_filters
			#puts "Chain#initialize_filters"
		end
	end
	class FillChain
		def initialize input_dimensions = nil, fill = MASH_FILL_STRETCH
			@input_dimensions = input_dimensions
			@fill = fill
		end
		def command options
			cmds = Array.new
			target_dims = options[:mm_dimensions]
			orig_dims = @input_dimensions || target_dims
			raise "input dimensions nil" unless orig_dims
			raise "output dimensions nil" unless target_dims
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
				simple_scale = (MASH_FILL_STRETCH == @fill)
				if not simple_scale then
					fill_is_scale = (MASH_FILL_SCALE == @fill)
					ratio_w = target_w_f / orig_w_f
					ratio_h = target_h_f / orig_h_f
					ratio = (! fill_is_scale ? float_max(ratio_h, ratio_w) : float_min(ratio_h, ratio_w))
					target_w_scaled = target_w_f / ratio
					target_h_scaled = target_h_f / ratio
					simple_scale = (float_cmp(orig_w_f, target_w_scaled) and float_cmp(orig_h_f, target_h_scaled))
				end
				if not simple_scale then
					if (float_gtr(orig_w_f, target_w_scaled) or float_gtr(orig_h_f, target_h_scaled))
						cmd = 'crop='
						cmd += "w=#{target_w_scaled.to_i}"
						cmd += ":h=#{target_h_scaled.to_i}"
						cmd += ":x=#{((orig_w_f - target_w_scaled) / FLOAT_TWO).ceil.to_i}"
						cmd += ":y=#{((orig_h_f - target_h_scaled) / FLOAT_TWO).ceil.to_i}"
						cmds << cmd	
					else
						cmd = 'pad='
						cmd += "w=#{target_w_scaled.to_i}"
						cmd += ":h=#{target_h_scaled.to_i}"
						cmd += ":x=#{((target_w_scaled - orig_w_f) / FLOAT_TWO).floor.to_i}"
						cmd += ":y=#{((target_h_scaled - orig_h_f) / FLOAT_TWO).floor.to_i}"
						cmd += ":color=#{options[:mm_backcolor]}"
						cmds << cmd	
					end
					simple_scale = ! ((orig_w == target_w) or (orig_h == target_h))
				end
				cmds << "scale=w=#{target_w}:h=#{target_h}" if simple_scale
				cmds << 'setsar=sar=1:max=1' if MASH_FILL_STRETCH == @fill
			end
			cmds.join ','
		end
	end
	class OverlayChain
		def command options
			'overlay=x=0:y=0'
		end
	end
	class FilterChain < Chain
		attr_writer :input
		def initialize input, command_input = nil
			super input
			if @input[:filters] and @input[:filters].is_a? Array and not @input[:filters].empty? then
				@input[:filters].each do |filter_config|
					@filters << Filter.new(filter_config[:id], filter_config[:parameters])
				end
				#puts "FilterChain.initialize filters #{@filters}"
			else 
				raise "FilterChain.initialize with no filters #{@input}"
			end
			@input = command_input if command_input
		end
		def command options
			options = input_options options
			super options
		end
		def input_options options
			options = options.dup # shallow copy, so mm_job_input and mm_job_output are just pointers
			#puts "input has no dimensions #{@input}" unless @input[:dimensions]
			raise "input has no range #{@input}" unless @input[:range]
			options[:mm_input_dimensions] = @input[:dimensions] || options[:mm_dimensions]
			options[:mm_input_width], options[:mm_input_height] = options[:mm_input_dimensions].split 'x'
			options[:mm_duration] = @input[:range].length_seconds
			options[:mm_t] = "(t/#{options[:mm_duration]})"
			if @input[:properties] and @input[:properties].is_a? Hash and not @input[:properties].empty? then
				@input[:properties].each do |property, ob|
					options[property] = @input[property] || ob[:value]
				end
			end
			options
		end
	end
	class EffectsChain < Chain
		def initialize_filters
			#puts "EffectsChain#initialize_filters"
			if @input[:effects] and @input[:effects].is_a?(Array) and not @input[:effects].empty? then
				@input[:effects].each do |effect|
					effect[:dimensions] = @input[:dimensions] unless effect[:dimensions]
					@filters << FilterChain.new(effect)
				end
			end
		end
	end
	class ThemeLayer < InputLayer
		def initialize_chains
			#puts "ThemeLayer.initialize_chains"
			@chains << FilterChain.new(@input)
		end
	end
	class TransitionLayer < InputLayer
		attr_reader :layers
		def initialize_chains
			#puts "TransitionLayer.initialize_chains #{@input}"
			super
			@layers = Array.new
			@layer_chains = [{},{}]
			@layer_chains[0][:filters] = FilterChain.new(@input[:from], @input) if @input[:from][:filters] and not @input[:from][:filters].empty?
			@layer_chains[1][:filters] = FilterChain.new(@input[:to], @input) if @input[:to][:filters] and not @input[:to][:filters].empty?
			@layer_chains[0][:merger] = FilterChain.new(@input[:from][:merger], @input) 
			@layer_chains[1][:merger] = FilterChain.new(@input[:to][:merger], @input)
			@layer_chains[0][:scaler] = FilterChain.new(@input[:from][:scaler], @input) 
			@layer_chains[1][:scaler] = FilterChain.new(@input[:to][:scaler], @input)
			@color_layer = ColorLayer.new @input[:range].length_seconds
		end
		def command options
			cmd = ''
			if 0 < @layers.length then
				raise "options has no dimensions" unless options[:mm_dimensions]
				@input[:dimensions] = options[:mm_dimensions]
				duration = @input[:range].length_seconds
				@layers << ColorLayer.new(duration) unless 1 < @layers.length
				cmds = Array.new
				2.times do |i|
					layer = @layers[i]
					#puts "layer input #{layer.input}"
					layer_chain = @layer_chains[i]
					cmd = layer.command options
					cmd += ','
					cmd += layer_chain[:scaler].command options
					if layer_chain[:filters] then
						chain_cmd = layer_chain[:filters].command options
						if chain_cmd and not chain_cmd.empty? then
							cmd += ','
							cmd += chain_cmd
						end
					end
					cmd += "[transition#{i}]"
					cmds << cmd
				end
				cmd = cmds.join ';'
			end
			cmd += ';'
			cmd += @color_layer.command options
			cmd += '[transback];'
			
			cmd += '[transback][transition0]'
			cmd += @layer_chains[0][:merger].command options
			cmd += '[transitioned0];'

			cmd += '[transitioned0][transition1]'
			cmd += @layer_chains[1][:merger].command options
			#cmd += ",trim=duration=#{duration}"
			#cmd += ",fps=fps=#{options[:mm_fps]}"
			#cmd += ',setpts=expr=PTS-STARTPTS'
			cmd
		end
	end
	class Filter
		attr_reader :id, :parameters, :in_labels, :out_labels
		def command scope = nil
			cmds = Array.new
			@in_labels.each do |label|
				next unless label and not label.empty?
				cmds << "[#{label}]"
			end unless __filter_is_source? @id 
			
			cmds << "#{@id}="
			cmd = cmds.join ''
			cmd += command_parameters(scope)
			cmds = Array.new
			@out_labels.each do |label|
				next unless label and not label.empty?
				cmds << "[#{label}]"
			end 
			cmd += cmds.join ''
			cmd
		end
		def command_parameters scope
			cmds = Array.new
			@parameters.each do |parameter|
				raise "parameter is not a Hash #{parameter}" unless  parameter.is_a? Hash
				#puts "#{parameter[:name]}=#{parameter[:value]}"
	  			evaluated = parameter[:value]
	  			evaluated = __filter_scope_value(scope, evaluated) if scope
				cmds << "#{parameter[:name]}=#{evaluated.to_s}"
			end
			cmds.join ':'
		end
		def initialize id, parameters = Array.new
			@id = id
			@parameters = parameters
			@in_labels = Array.new
			@out_labels = Array.new
	  	end
	  	def __filter_scope_value scope, value
	  		raise "__filter_scope_value got nil value" unless value
			#puts "__filter_scope_value #{value}"
			result = nil
			if value.is_a? Array 
				bind = __filter_scope_binding scope
				condition_is_true = false
				value.each do |conditional|
					#puts "condition = #{conditional[:condition]}"
					condition_is_true = bind.eval(conditional[:condition])
					if condition_is_true then
						result = __filter_parse_scope_value scope, conditional[:value].to_s
						#puts "__filter_scope_value\n#{conditional[:value]}\n#{result}"
						break
					end
				end
				raise "no conditions were true" unless condition_is_true
			else
				result = __filter_parse_scope_value scope, value.to_s
			end
			result
		end
		def __filter_parse_scope_value scope, value_str
			#puts "value_str = #{value_str}"
			level = 0
			deepest = 0
			esc = '.'
			# expand variables
			value_str = value_str.dup
			value_str.gsub!(MovieMasher::RegexVariables) do |match|
				match_str = match.to_s
				#puts "MATCH: #{match_str}"
				match_sym = match_str.to_sym
				#puts "RGBA: #{scope[match_sym]}" if 'rgba' == match_str
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
					result = result + level.to_s + esc
				when ')'
					result = result + level.to_s + esc
					level -= 1
				end
				result
			end
			#puts "value_str = #{value_str}"
			while 0 < deepest
				value_str.gsub!(Regexp.new("([a-z_]+)[(]#{deepest}[.]([^)]+)[)]#{deepest}[.]")) do |m|
					#puts "level #{level} #{m}"
					method = $1
					param_str = $2
					params = param_str.split(',')
					params.each do |param|
						param.strip!
						param.gsub!(/([()])[0-9]+[.]/) {$1}
					end
					func_sym = method.to_sym
					if FilterHelpers.respond_to? func_sym then
						result = FilterHelpers.send func_sym, params, scope
						raise "got false from #{method}(#{params.join ','})" unless result
						result = result.to_s unless result.is_a? String
						raise "got empty from #{method}(#{params.join ','})" if result.empty?
					else
						result = "#{method}(#{params.join ','})"
					end
					result			
				end
				deepest -= 1
				#puts "value_str = #{value_str}"
			end
			# remove any lingering markers
			value_str.gsub!(/([()])[0-9]+[.]/) { $1 }
			# remove whitespace
			value_str.gsub!(/\s/, '')
			#puts "value_str = #{value_str}"
			value_str
		end
		def __filter_is_source? filter_id
			case filter_id
			when 'color', 'movie'
				true
			else 
				false
			end
		end
		def __filter_scope_binding scope
			bind = binding
			scope.each do |k,v|
				next if :mm_job_input == k or  :mm_job_output == k
				evaluate = "#{k.id2name}='#{v}'"
				#puts "evaluate = #{evaluate}"
				bind.eval evaluate
			end
			bind
		end

	end
	class HashFilter < Filter
		def command_parameters scope
			cmds = Array.new
			raise "@parameters is not a Hash #{@parameters}" unless @parameters.is_a? Hash
			@parameters.each do |k,v|
				#puts "#{k.id2name}=#{v}"
	  			evaluated = v
	  			evaluated = __filter_scope_value(scope, evaluated) if scope
				cmds << "#{k.id2name}=#{evaluated.to_s}"
			end
			cmds.join ':'
		end
		
	end
	class ColorLayer 
		attr_writer :color, :duration, :size, :rate
		def initialize duration = nil
			raise "ColorLayer with no duration" unless duration
			@duration = duration
		end
		def command options
			raise "ColorLayer with no color #{options}" unless options[:mm_backcolor]
			raise "ColorLayer with no size #{options}" unless options[:mm_dimensions]
			raise "ColorLayer with no rate #{options}" unless options[:mm_fps]
			"color=color=#{options[:mm_backcolor]}:duration=#{@duration}:size=#{options[:mm_dimensions]}:rate=#{options[:mm_fps]}"
		end
		def range
			nil
		end
	end
	class Graph
		def duration
			@render_range.length_seconds
		end
		def initialize job_input, render_range, backcolor = nil
			@job_input = job_input
			@render_range = render_range
			@backcolor = backcolor
			@layers = Array.new
			@color_chain = ColorLayer.new duration
			@layers << @color_chain
		end
		def << layer
			@layers << layer
		end
		def command output
			graph_cmds = Array.new
			layer_length = @layers.length
			layer_options = output_options(output)
			layer_length.times do |i|
				layer = @layers[i]
				cmd = layer.command layer_options
				cmd += command_range_trim(layer.range) if layer.range
				cmd += "[layer#{i}]" if 1 < layer_length
				graph_cmds << cmd
			end
			if 1 < layer_length then
				(1..layer_length-1).each do |i|
					raise "layer_length #{layer_length} i #{i} #{@layers}" unless i < @layers.length
					layer = @layers[i]
					cmd = (1 == i ? "[layer#{i-1}]" : "[layered#{i-1}]")
					cmd += "[layer#{i}]"
					merge_cmd = layer.command_merger(layer_options)
					
					raise "merger produced no command #{layer.inspect}" unless merge_cmd and not merge_cmd.empty?
					#puts "merge command: #{merge_cmd}"
					cmd += merge_cmd
					if i + 1 < layer_length then
						cmd += "[layered#{i}]"
					end
					graph_cmds << cmd
				end	
			end
			cmd = graph_cmds.join ';'
			
			#cmd += ",fps=fps=#{layer_options[:mm_fps]}"
			cmd
		end
		def output_options job_output
			scope = Hash.new
			scope[:mm_job_input] = @job_input
			scope[:mm_job_output] = job_output
			backcolor = @backcolor || job_output[:backcolor]
			if backcolor then
				backcolor = backcolor.to_s.strip
				# it might be an rgb
				if backcolor.start_with?('rgb(') and backcolor.end_with?(')') then
					backcolor['rgb('] = ''
					backcolor[')'] = ''
					backcolor = FilterHelpers.rgb(backcolor)
				end
			else 
				backcolor = 'black'
			end
			scope[:mm_backcolor] = backcolor
			scope[:mm_fps] = job_output[:fps]			
			scope[:mm_dimensions] = job_output[:dimensions]
			scope[:mm_width], scope[:mm_height] = scope[:mm_dimensions].split 'x'
			scope
		end
	
		def command_range_trim input_range
			cmd = ''
			if @render_range and not input_range.is_equal_to_time_range?(@render_range) then
				#puts "@render_range #{@render_range.inspect}"
				#puts "input_range #{input_range.inspect}"
				range_start = @render_range.get_seconds
				range_end = @render_range.end_time.get_seconds
				input_start = input_range.get_seconds
				input_end = input_range.end_time.get_seconds
				if range_start > input_start or range_end < input_end then
					cmd += ",trim=duration=#{@render_range.length_seconds}"
					cmd += ":start=#{float_precision(range_start - input_start)}" if range_start > input_start
					cmd += ',setpts=expr=PTS-STARTPTS'
				end
			end
			cmd
		end			
		def create_layer input
			layer = new_layer input
			@layers << layer
			layer
		end
		def new_layer input
			InputLayer.create input
		end
	end
	
end
