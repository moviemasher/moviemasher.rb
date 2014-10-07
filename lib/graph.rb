
module MovieMasher	
	class Graph
		def duration
			dur = @render_range.length_seconds
			#puts "Graph#duration #{dur} #{@render_range.inspect}"
			dur
		end
		def initialize job_input, render_range, backcolor = nil
			#puts "Graph #{render_range.inspect}"
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
			layer_options = output_options(output)
			case output[:type]
			when Type::Image, Type::Sequence
				graph_cmds << @layers[1].command(layer_options)
			else
				layer_length = @layers.length
				layer_length.times do |i|
					layer = @layers[i]
					cmd = layer.command layer_options
					cmd += command_range_trim(layer.range) if layer.range
					cmd += "[layer#{i}]" if 1 < layer_length
					graph_cmds << cmd
				end
				if 1 < layer_length then
					(1..layer_length-1).each do |i|
						raise Error::JobInput.new "layer_length #{layer_length} i #{i} #{@layers}" unless i < @layers.length
						layer = @layers[i]
						cmd = (1 == i ? "[layer#{i-1}]" : "[layered#{i-1}]")
						cmd += "[layer#{i}]"
						merge_cmd = layer.command_merger(layer_options)
					
						raise Error::JobInput.new "merger produced no command #{layer.inspect}" unless merge_cmd and not merge_cmd.empty?
						#puts "merge command: #{merge_cmd}"
						cmd += merge_cmd
						if i + 1 < layer_length then
							cmd += "[layered#{i}]"
						end
						graph_cmds << cmd
					end	
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
					cmd += ":start=#{Float.precision(range_start - input_start)}" if range_start > input_start
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
		def raw
			case @job_input[:type]
			when Type::Video, Type::Image
				true
			else 
				false
			end
		end
	end
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
			raise Error::JobInput.new "input is not a hash #{input}" unless input.is_a? Hash
			raise Error::JobInput.new "input hash has no type #{input}" unless input[:type]
			case input[:type]
			when MovieMasher::Type::Video
				layer = VideoLayer.new input
			when MovieMasher::Type::Transition
				layer = TransitionLayer.new input
			when MovieMasher::Type::Image
				layer = ImageLayer.new input
			when MovieMasher::Type::Theme
				layer = ThemeLayer.new input
			else
				raise Error::JobInput.new "input hash type invalid #{input}" 
			end
			layer
		end
		def command_merger options
			@merger_chain.command options
		end
		def initialize input
			@input = input
			super nil, input[:range]
			initialize_chains
			if @input[:merger] 
				@input[:merger][:dimensions] = @input[:dimensions] unless @input[:merger][:dimensions]
				@merger_chain = FilterChain.new @input[:merger]
			else 
				@merger_chain = OverlayMerger.new
			end
			if @input[:scaler]
				@input[:scaler][:dimensions] = @input[:dimensions] unless @input[:scaler][:dimensions]
				@scaler_chain = FilterChain.new @input[:scaler]
			else
				@scaler_chain = FillScaler.new @input
			end
			@effects_chain = EffectsChain.new @input
			@chains << @scaler_chain
			@chains << @effects_chain
		end
		def initialize_chains
			# override me
		end 
		def __filter_timestamps
			HashFilter.new 'setpts', :expr => 'PTS-STARTPTS'
		end
		def __get_length
			__get_time :length
		end
		def __get_range
			range = MovieMasher::FrameRange.new(@input[:start], 1, 1)
			range.scale(@input[:fps]) if Type::Video == @input[:type]
			range
		end	
		def __get_time key
			length = MovieMasher::Float::Zero
			if Float.gtr(@input[key], MovieMasher::Float::Zero) then
				sym = "#{key.id2name}_is_relative".to_sym
				if @input[sym] then
					if Float.gtr(@input[:duration], MovieMasher::Float::Zero) then
						if '%' == @input[sym] then
							length = (@input[key] * @input[:duration]) / MovieMasher::Float::Hundred
						else 
							length = @input[:duration] - @input[key]
						end
					end
				else 
					length = @input[key]
				end
			elsif :length == key and Float.gtr(@input[:duration], MovieMasher::Float::Zero) then
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
			@movie_filter = MovieFilter.new(@input[:cached_file], @input[:dimensions])
			chain << @movie_filter
			# fps is placeholder since each output has its own rate
			@fps_filter = HashFilter.new('fps', :fps => 0)
			chain << @fps_filter
			# we need a trim because the video we'll build from image will be artificially long
			@trim_filter = HashFilter.new('trim', :duration => Float.precision(@input[:length_seconds]))
			chain << @trim_filter
			@chains << chain
			chain << @fps_filter
		end
		def command options
			fps = options[:mm_fps]
			duration = @input[:length_seconds] || __get_length
			@fps_filter.parameters[:fps] = fps
			@trim_filter.parameters[:duration] = duration
			raise Error::JobInput.new "input has no cached_file #{@input.inspect}" unless @input[:cached_file]
			file = @input[:cached_file]
			output_type_is_video = (Type::Video == options[:mm_job_output][:type])
			@fps_filter.disabled = (not output_type_is_video)
			@trim_filter.disabled = (not output_type_is_video)
			file = __video_from_image(file, duration, fps) if output_type_is_video
			@movie_filter.parameters[:filename] = file
			super
		end
		def __video_from_image img_file, duration, fps
			frame_time = FrameTime.new ((duration.to_f) * fps.to_f).round.to_i, fps
			frame_time.scale 1, :ceil
			frame_time.frame += 1
			raise Error::JobInput.new "no frame_time from #{duration}@#{fps} #{frame_time.inspect}" unless 0 < frame_time.frame
			parent_dir = File.dirname img_file
			base_name = File.basename img_file
			out_file = "#{parent_dir}/#{base_name}-#{duration}-#{fps}.#{Intermediate::VideoExtension}" 
			unless File.exists?(out_file) then
				cmd = ''
				cmd += shell_switch('1', 'loop')
				cmd += shell_switch(frame_time.fps, 'r')
				cmd += shell_switch(img_file, 'i')
				cmd += shell_switch('format=pix_fmts=yuv420p', 'filter_complex')
				cmd += shell_switch(Intermediate::VideoFormat, 'f:v')
		
				cmd += shell_switch(frame_time.frame, 'vframes')
				cmd += shell_switch(Float.precision(frame_time.get_seconds), 't')
				MovieMasher::app_exec cmd, out_file
			end
			out_file
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
				raise Error::JobInput.new "options has no dimensions" unless options[:mm_dimensions]
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
	class VideoLayer < InputLayer
		def initialize_chains
			#puts "VideoLayer#initialize_chains"
			chain = Chain.new
			chain << MovieFilter.new(@input[:cached_file], @input[:dimensions])
			# trim filter, if needed
			@trim_filter = __filter_trim_input
			chain << @trim_filter if @trim_filter
			# fps is placeholder since each output has its own rate
			@fps_filter = HashFilter.new('fps', :fps => 0)
			chain << @fps_filter
			# set presentation timestamp filter 
			@filter_timestamps = __filter_timestamps
			chain << @filter_timestamps
			@chains << chain
			#puts "VideoLayer.initialize_chains #{@chains}"
		end
		def __filter_trim_input
			filter = nil
			trim_seconds = @input[:trim_seconds] || __get_trim
			length_seconds = @input[:length_seconds] || __get_length
			trim_beginning = Float.gtr(trim_seconds, MovieMasher::Float::Zero)
			trim_end = Float.gtr(length_seconds, MovieMasher::Float::Zero) and (@input[:duration].to_f > (trim_seconds + length_seconds))
			if trim_beginning or trim_end then
				# start and duration look at timestamp and change it
				filter = HashFilter.new('trim', :duration => Float.precision(length_seconds))
				filter.parameters[:start] = Float.precision(trim_seconds) if trim_beginning
			end
			filter
		end
		def command options
			raise Error::JobInput.new "command with empty options" unless options
			output_type_is_video = ((! options[:mm_job_output]) || (Type::Video == options[:mm_job_output][:type]))
			@fps_filter.disabled = (not output_type_is_video)
			@trim_filter.disabled = (not output_type_is_video) if @trim_filter
			@filter_timestamps.disabled = (not output_type_is_video)
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
			#puts "Chain.command #{@filters.length} filter(s)"
			@filters.each do |filter|
				cmd = filter.command(options)
				cmds << cmd if cmd and not cmd.empty?
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
			# override me
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
			else 
				raise Error::JobInput.new "FilterChain.initialize with no filters #{@input}"
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
			raise Error::JobInput.new "input has no range #{@input}" unless @input[:range]
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
	class Filter
		attr_reader :id, :parameters, :in_labels, :out_labels
		attr_writer :disabled
		@@outsize = Hash.new
		def __puts_scope scope
			puts '-' * 10
			scope.keys.each do |key|
				puts "#{key} = #{scope[key]}" unless scope[key].is_a?(Hash)
			end
		end
		def command scope = nil
			cmd = ''
			unless @disabled then
				@evaluated = Hash.new
				cmds = Array.new
				@in_labels.each do |label|
					next unless label and not label.empty?
					cmds << "[#{label}]"
				end unless __filter_is_source? @id 
				cmds << "#{@id}"
				if scope
					if @@outsize['w'] and @@outsize['h']
						unless scope[:mm_in_w] or scope[:mm_in_h]
							scope[:mm_in_w] = @@outsize['w'] 
							scope[:mm_in_h] = @@outsize['h'] 
							#puts "<< #{scope[:mm_in_w]}x#{scope[:mm_in_h]} #{@id}"
						end
					else 
						scope[:mm_in_w] = 'in_w'
						scope[:mm_in_h] = 'in_h'
					end
				end
				cmd = command_parameters(scope)
				if cmd and not cmd.empty?
					cmds << '='
					cmds << cmd
				end
				@out_labels.each do |label|
					next unless label and not label.empty?
					cmds << "[#{label}]"
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
								#	puts "! >> #{evaluated} = #{@evaluated[key]} #{@id}"
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
		def command_parameters scope
			cmds = Array.new
			 if @parameters
				 if @parameters.is_a? Hash
					@parameters.each do |name, evaluated|
						name = name.id2name if name.is_a? Symbol
						cmds << __command_name_value(name, evaluated, scope)
					end
				else
					@parameters.each do |parameter|
						raise Error::JobInput.new "parameter is not a Hash #{parameter}" unless  parameter.is_a? Hash
						#puts "#{parameter[:name]}=#{parameter[:value]}"
						name = parameter[:name]
						evaluated = parameter[:value]
						cmds << __command_name_value(name, evaluated, scope)
					end
				end
			end
			cmds.join ':'
		end
		def initialize id, parameters = Array.new
			@id = id
			@parameters = parameters
			@in_labels = Array.new
			@out_labels = Array.new
	  	end
	  	def __command_name_value name, value, scope
	  		raise Error::JobInput.new "__command_name_value got nil value" unless value
			#puts "__command_name_value #{value}"
			result = value
			if value.is_a? Array 
				bind = __filter_scope_binding scope
				condition_is_true = false
				value.each do |conditional|
					#puts "condition = #{conditional[:condition]}"
					condition = conditional[:condition]
					if conditional[:is]
						condition += '=' + conditional[:is].to_s;
					elsif conditional[:in]
						conditional[:in] = conditional[:in].split(',') unless conditional[:in].is_a? Array
						condition = '[' + conditional[:in].join(',') + '].include?(' + condition + ')'
					end
					condition_is_true = bind.eval(condition)
					if condition_is_true then
						result = __filter_parse_scope_value scope, conditional[:value].to_s
						break
					end
				end
				raise Error::JobInput.new "no conditions were true" unless condition_is_true
			else
				result = __filter_parse_scope_value scope, value.to_s
			end
			result = Evaluate.equation result
	  		@evaluated[name] = result
			"#{name}=#{result.to_s}"
		end
		def __filter_parse_scope_value scope, value_str
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
							result = FilterHelpers.send func_sym, params, scope
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
					next if :mm_job_input == k or  :mm_job_output == k
					evaluate = "#{k.id2name} = __coerce '#{v}'"
					#puts "evaluate = #{evaluate}"
					bind.eval evaluate
				end
			end
			bind
		end
	end
	class MovieFilter < Filter
		def initialize file, dimensions
			@dimensions = dimensions
			super 'movie', {:filename => file}
		end
		def command options
			@@outsize['w'], @@outsize['h'] = @dimensions.split 'x'
			#puts ">> #{@@outsize['w']}x#{@@outsize['h']} #{@id}"
			super
		end
	end
	class ColorLayer < Filter
		attr_writer :duration #, :color, :size, :rate
		def initialize duration = nil
			raise Error::JobInput.new "ColorLayer with no duration" unless duration
			@duration = duration
			super 'color', {}
		end
		def command options
			raise Error::JobInput.new "ColorLayer with no color #{options}" unless options[:mm_backcolor]
			raise Error::JobInput.new "ColorLayer with no size #{options}" unless options[:mm_dimensions]
			#raise Error::JobInput.new "ColorLayer with no rate #{options}" unless options[:mm_fps]
			@parameters[:color] = options[:mm_backcolor]
			@parameters[:size] = options[:mm_dimensions]
			@parameters[:duration] = @duration
			@parameters[:rate] = options[:mm_fps]
			@@outsize['w'] = options[:mm_width]
			@@outsize['h'] = options[:mm_height]
			super
		end
		def range
			nil
		end
	end

	class HashFilter < Filter
		def command_parameters scope
			cmds = Array.new
			raise Error::JobInput.new "@parameters is not a Hash #{@parameters}" unless @parameters.is_a? Hash
			@parameters.each do |k,v|
				#puts "#{k.id2name}=#{v}"
	  			evaluated = v
	  			raise Error::JobInput.new "#{k} is nil" if v.nil?
	  			cmds << __command_name_value(k.id2name, evaluated, scope) 
			end if @parameters
			cmds.join ':'
		end
	end
	class FillScaler < Chain
		def initialize input = nil
			super input
			@input_dimensions = @input[:dimensions]
			@fill = @input[:fill] || Mash::FillStretch
		end
		def command options
			@filters = Array.new
			target_dims = options[:mm_dimensions]
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
				simple_scale = (Mash::FillStretch == @fill)
				if not simple_scale then
					fill_is_scale = (Mash::FillScale == @fill)
					ratio_w = target_w_f / orig_w_f
					ratio_h = target_h_f / orig_h_f
					ratio = (fill_is_scale ? Float.min(ratio_h, ratio_w) : Float.max(ratio_h, ratio_w))
					simple_scale = (Mash::FillNone == @fill)
					if simple_scale then
						target_w = (orig_w_f * ratio).to_i
						target_h = (orig_h_f * ratio).to_i
						#puts "#{orig_w}x#{orig_h} / #{ratio} (Float.max(#{ratio_h}, #{ratio_w})) = #{target_w}x#{target_h}"
					else
						target_w_scaled = target_w_f / ratio
						target_h_scaled = target_h_f / ratio
						simple_scale = (Float.cmp(orig_w_f, target_w_scaled) and Float.cmp(orig_h_f, target_h_scaled))
					end
				end
				if not simple_scale then
					if (Float.gtr(orig_w_f, target_w_scaled) or Float.gtr(orig_h_f, target_h_scaled))
						@filters << HashFilter.new('crop', 
							:w => target_w_scaled.to_i, 
							:h => target_h_scaled.to_i, 
							:x => ((orig_w_f - target_w_scaled) / MovieMasher::Float::Two).ceil.to_i,
							:y => ((orig_h_f - target_h_scaled) / MovieMasher::Float::Two).ceil.to_i,
						)
					else
						@filters << HashFilter.new('pad', 
							:color => options[:mm_backcolor],
							:w => target_w_scaled.to_i, 
							:h => target_h_scaled.to_i, 
							:x => ((target_w_scaled - orig_w_f) / MovieMasher::Float::Two).floor.to_i,
							:y => ((target_h_scaled - orig_h_f) / MovieMasher::Float::Two).floor.to_i,
						)
					end
					simple_scale = ! ((orig_w == target_w) or (orig_h == target_h))
				end
				@filters << HashFilter.new('scale', :w => target_w, :h => target_h) if simple_scale
				@filters << SetsarFilter.new if Mash::FillStretch == @fill
			end
			#puts "FillScaler.command #{@filters.length} filter(s)"
			super
		end
	end
	class SetsarFilter < HashFilter
		def initialize
			super 'setsar', :sar => 1, :max => 1
		end
	end
	
	class OverlayMerger
		def command options
			'overlay=x=0:y=0'
		end
	end
end
