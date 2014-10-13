
module MovieMasher
	module Evaluate
		def self.equation s, raise_on_fail = nil
			# change all numbers to floats
			fs = s.to_s.gsub(/([0-9]+[.]?[0-9]*)/) { $1.to_f }
			evaluated = s
			begin
				evaluated = eval fs
				evaluated = evaluated.to_f
			rescue Exception => e
				#MovieMasher.__log(:debug) { "could not evaluate '#{fs}' #{e.message}" }
				raise Error::JobInput.new "evaluation of equation failed #{fs} #{e.message}" if raise_on_fail
			end
			evaluated
		end
		def self.split(s)
			s.to_s.split(/{([^}]*)}/)
		end
		def self.path ob, path_array
			value = ob
			key = path_array.shift
			if key then
				if key.to_i.to_s == key then
					key = key.to_i
				else
					key = key.to_sym 
				end
				value = value[key]
				if value.is_a?(Array) or value.is_a?(Hash) then
					value = path(value, path_array) unless path_array.empty?
				else
					value = value.to_s
				end
			else
				raise Error::State.new "path got empty path_array for #{ob}"
			end
			value
		end
		def self.recursively data, scope = nil
			scope = Hash.new unless scope
			keys = (data.is_a?(Hash) ? data.keys : (0..(data.length-1)))
			values = (data.is_a?(Hash) ? data.values : data)
			keys.each do |k|
				v = data[k]
				if v.is_a?(Hash) or v.is_a?(Array) then
					recursively v, scope
				else
					data[k] = value v.to_s, scope
				end
			end
		end
		def self.value value, scope
			split_value = split value
			if 1 < split_value.length then # otherwise there are no curly braces
				value = ''
				is_static = true
				#puts "value is split #{split_value.inspect}"
				split_value.each do |bit|
					if is_static then
						value += bit
					else
						split_bit = bit.split '.'
						first_key = split_bit.shift
						scope_child = scope[first_key.to_sym]
						evaled = nil
						if scope_child 
							if scope_child.is_a?(Hash) or scope_child.is_a?(Array)
								evaled = path(scope_child, split_bit)
							elsif scope_child.is_a? Proc
								evaled = scope_child.call
							else 
								evaled = scope_child
							end
						end
						if evaled.is_a?(Hash) or evaled.is_a?(Array)
							value = evaled
						else
							value = "#{value}#{evaled}"
						end
					end
					is_static = ! is_static
				end
			end
			value
		end
	end
end