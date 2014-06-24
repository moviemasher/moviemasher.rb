module MovieMasher
	class FilterHelpers
		def self.mm_textfile param_string, scope
			params = __params_from_str param_string, scope
			text = params.join ','
			job_path = MovieMasher.output_path scope[:mm_job_output]
			FileUtils.mkdir_p(job_path)
			job_path += UUID.new.generate
			job_path += '.txt'
			File.open(job_path, 'w') {|f| f.write(text) }
			job_path
		end
		def self.rgb param_string, scope
			params = __params_from_str param_string, scope
			"0x%02x%02x%02x" % params
		end
		def self.rgba param_string, scope
			params = __params_from_str param_string, scope
			params.push (params.pop.to_f * 255.to_f).to_i
			"0x%02x%02x%02x%02x" % params
		end
		def self.__font_from_scope font_id, scope
			mash = scope[:mm_job_input][:source]
			raise "found no mash source in job input #{scope[:mm_job_input]}" unless mash
			font = MovieMasher.mash_search(mash, font_id, :fonts)
			raise "found no font with id #{font_id} in mash #{mash}" unless font
			font
		end
		def self.mm_fontfile param_string, scope
			params = __params_from_str param_string, scope
			font_id = params.join ','
			font = __font_from_scope font_id, scope
			raise "font has not been cached #{font}" unless font[:cached_file]
			font[:cached_file] # font[:family]
		end
		def self.mm_fontfamily param_string, scope
			params = __params_from_str param_string, scope
			font_id = params.join ','
			font = __font_from_scope font_id, scope
			raise "font has no family" unless font[:family]
			font[:family]
		end
		def self.mm_horz param_string, scope
			params = __params_from_str param_string, scope
			param_string = params.join(',')
			param_sym = param_string.to_sym
			if scope[param_sym] then
				(scope[:mm_width].to_f * scope[param_sym].to_f).round.to_i.to_s
			else
				"(#{scope[:mm_width]}*#{param_string})"
			end
		end
		def self.mm_vert param_string, scope
			params = __params_from_str param_string, scope
			param_string = params.join(',')
			param_sym = param_string.to_sym
			if scope[param_sym] then
				(scope[:mm_height].to_f * scope[param_sym].to_f).round.to_i.to_s
			else
				"(#{scope[:mm_height]}*#{param_string})"
			end
		end
		def self.mm_dir_horz param_string, scope
			raise "mm_dir_horz no parameters #{param_string}" if param_string.empty?
			params = __params_from_str param_string, scope
			#puts "mm_dir_horz #{param_string}} #{params.join ','}"
			case params[0].to_i # direction value
			when 0, 2 # center with no change
				"((in_w-out_w)/2)"
			when 1, 4, 5
				"((#{params[2]}-#{params[1]})*#{params[3]})"
			when 3, 6, 7
				"((#{params[1]}-#{params[2]})*#{params[3]})"
			else 
				raise "unknown direction #{params[0]}"
			end
		end
		def self.mm_paren param_string, scope
			params = __params_from_str param_string, scope
			"(#{params.join ','})"
		end
		def self.mm_dir_vert param_string, scope
			raise "mm_dir_vert no parameters #{param_string}" if param_string.empty?
			params = __params_from_str param_string, scope
			#puts "mm_dir_vert #{param_string} #{params.join ','}"
			result = case params[0].to_i # direction value
			when 1, 3 # center with no change
				"((in_h-out_h)/2)"
			when 0, 4, 7
				"((#{params[1]}-#{params[2]})*#{params[3]})"
			when 2, 5, 6
				"((#{params[2]}-#{params[1]})*#{params[3]})"
			else 
				raise "unknown direction #{params[0]}"
			end
			result
		end
		def self.mm_max param_string, scope
			params = __params_from_str param_string, scope
			params.max
		end
		def self.mm_times param_string, scope
			params = __params_from_str param_string, scope
			total = FLOAT_ONE
			params.each do |param|
				total *= param.to_f
			end
			total
		end
		def self.mm_min param_string, scope
			params = __params_from_str param_string, scope
			params.min
		end
		def self.mm_cmp param_string, scope
			params = __params_from_str param_string, scope
			(params[0].to_f > params[1].to_f ? params[2] : params[3])
		end
		def self.__params_from_str param_string, scope
			(param_string.is_a?(String) ? param_string.split(',') : param_string)
		end
	end
end
