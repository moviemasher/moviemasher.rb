module MovieMasher
	class FilterHelpers
		def self.mm_textfile param_string, mash, scope
			params = __params_from_str param_string
			text = params.join ','
			job_path = MovieMasher.output_path true
			MovieMasher.file_safe job_path
			job_path = "#{job_path}/#{UUID.new.generate}.txt"
			File.open(job_path, 'w') {|f| f.write(text) }
			job_path
		end
		def self.rgb param_string, mash = nil, scope = nil
			params = __params_from_str param_string
			"0x%02x%02x%02x" % params
		end
		def self.rgba param_string, mash = nil, scope = nil
			params = __params_from_str param_string
			alpha = params.pop.to_f
			result = "0x%02x%02x%02x" % params
			result = "#{result}@#{alpha}"
			MovieMasher.__log(:debug) { "rgba(#{param_string}) #{result}" }
			result
		end
		def self.mm_fontfile param_string, mash, scope
			params = __params_from_str param_string
			font_id = params.join ','
			font = __font_from_scope font_id, mash, scope
			raise Error::JobInput.new "font has not been cached #{font}" unless font[:cached_file]
			font[:cached_file] 
		end
		def self.mm_fontfamily param_string, mash, scope
			params = __params_from_str param_string
			font_id = params.join ','
			font = __font_from_scope font_id, mash, scope
			raise Error::JobInput.new "font has no family" unless font[:family]
			font[:family]
		end
		def self.mm_horz param_string, mash, scope
			params = __params_from_str param_string
			value = params.join(',')
			param_sym = value.to_sym
			value = scope[param_sym] if scope[param_sym]
			value = Evaluate.equation value
			if value.respond_to? :round
				result = (scope[:mm_width].to_f * value.to_f).round.to_i.to_s
			else
				result = "(#{scope[:mm_width]}*#{value})"
			end
			#MovieMasher.__log(:info) { "mm_horz(#{param_string}) = #{result}" }
			result
		end
		def self.mm_vert param_string, mash, scope
			params = __params_from_str param_string
			value = params.join(',')
			param_sym = value.to_sym
			value = scope[param_sym] if scope[param_sym]
			value = Evaluate.equation value
			if value.respond_to? :round
				result = (scope[:mm_height].to_f * value).round.to_i.to_s 
			else
				result = "(#{scope[:mm_height]}*#{value})"
			end
			#MovieMasher.__log(:info) { "mm_vert(#{param_string}) = #{result}" }
		end
		def self.mm_dir_horz param_string, mash, scope
			raise Error::JobInput.new "mm_dir_horz no parameters #{param_string}" if param_string.empty?
			params = __params_from_str param_string
			#puts "mm_dir_horz #{param_string}} #{params.join ','}"
			case params[0].to_i # direction value
			when 0, 2 # center with no change
				"((in_w-out_w)/2)"
			when 1, 4, 5
				"((#{params[2]}-#{params[1]})*#{params[3]})"
			when 3, 6, 7
				"((#{params[1]}-#{params[2]})*#{params[3]})"
			else 
				raise Error::JobInput.new "unknown direction #{params[0]}"
			end
		end
		def self.mm_paren param_string, mash, scope
			params = __params_from_str param_string
			"(#{params.join ','})"
		end
		def self.mm_dir_vert param_string, mash, scope
			raise Error::JobInput.new "mm_dir_vert no parameters #{param_string}" if param_string.empty?
			params = __params_from_str param_string
			#puts "mm_dir_vert #{param_string} #{params.join ','}"
			result = case params[0].to_i # direction value
			when 1, 3 # center with no change
				"((in_h-out_h)/2)"
			when 0, 4, 7
				"((#{params[1]}-#{params[2]})*#{params[3]})"
			when 2, 5, 6
				"((#{params[2]}-#{params[1]})*#{params[3]})"
			else 
				raise Error::JobInput.new "unknown direction #{params[0]}"
			end
			result
		end
		def self.mm_max param_string, mash, scope
			params = __params_from_str param_string
			all_ints = true
			evaluated_all = true
			params.map! do |p|
				p = Evaluate.equation p
				if p.respond_to? :round
					all_ints = false if all_ints and not Float.cmp(p.floor, p)
				else
					evaluated_all = false
				end
				p
			end
			if evaluated_all 
				p = params.max
				p = p.to_i if all_ints
			else
				p = "max(#{params.join ','})"
			end
			p
		end
		def self.mm_min param_string, mash, scope
			params = __params_from_str param_string
			all_ints = true
			evaluated_all = true
			params.map! do |p|
				p = Evaluate.equation p
				if p.respond_to? :round
					all_ints = false if all_ints and not Float.cmp(p.floor, p)
				else
					evaluated_all = false
				end
				p
			end
			if evaluated_all 
				p = params.max
				p = p.to_i if all_ints
			else
				p = "min(#{params.join ','})"
			end
			p
		end
		def self.mm_cmp param_string, mash, scope
			params = __params_from_str param_string
			#puts "mm_cmp (#{params[0].to_f} > #{params[1].to_f} ? #{params[2]} : #{params[3]}) = #{(params[0].to_f > params[1].to_f ? params[2] : params[3])}"
			param_0 = Evaluate.equation params[0], true
			param_1 = Evaluate.equation params[0], true
			(param_0 > param_1 ? params[2] : params[3])
		end
		def self.__font_from_scope font_id, mash, scope
			font = Mash.media_search Type::Font, font_id, mash
			raise Error::JobInput.new "found no font with id #{font_id} in mash #{mash}" unless font
			font
		end
		def self.__params_from_str param_string
			param_string = param_string.split(',') if param_string.is_a?(String)
			param_string.map! { |p| p.is_a?(String) ? p.strip : p }
			param_string
		end
	end
end
