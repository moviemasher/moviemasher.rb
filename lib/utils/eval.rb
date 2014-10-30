
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
				raise Error::JobInput.new "evaluation of equation failed #{fs} #{e.message}" if raise_on_fail
			end
			evaluated
		end
		def self.object data, scope = nil
			scope = Hash.new unless scope
			keys = (data.is_a?(Array) ? (0..(data.length-1)) : data.keys)
			values = (data.is_a?(Array) ? data : data.values)
			keys.each do |k|
				v = data[k]
				if __is_eval_object? v
					object v, scope
				else
					data[k] = value v.to_s, scope
				end
			end
		end
		def self.value v, scope
			split_value = __split v
			if 1 < split_value.length then # otherwise there are no curly braces
				v = ''
				is_static = true
				split_value.each do |bit|
					if is_static then
						v += bit
					else
						split_bit = bit.split '.'
						scope_child = __scope_target split_bit, scope # shifts off of split_bit
						evaled = nil
						if scope_child 
							if __is_eval_object? scope_child
								evaled = __value(scope_child, split_bit)
							elsif scope_child.is_a? Proc
								evaled = scope_child.call
							else 
								evaled = scope_child
							end
						end
						if __is_eval_object? evaled
							v = evaled
						else
							v = "#{v}#{evaled}"
						end
					end
					is_static = ! is_static
				end
			end
			v
		end
		private
		def self.__is_eval_object? object
			(object.is_a?(Hash) or object.is_a?(Array) or object.is_a?(JobHash))
		end
		def self.__scope_target split_bit, scope
			scope_child = nil
			while not split_bit.empty?
				first_key = split_bit.shift
				scope_child = scope[first_key.to_sym]
				break if scope_child
			end
			scope_child
		end
		def self.__split(s)
			s.to_s.split(/{([^}]*)}/)
		end
		def self.__value ob, path_array
			v = ob
			key = path_array.shift
			if key then
				if key.to_i.to_s == key then
					key = key.to_i
				else
					key = key.to_sym 
				end
				v = v[key]
				if __is_eval_object? v
					v = __value(v, path_array) unless path_array.empty?
				else
					v = v.to_s		
				end
			else
				raise Error::State.new "__value got empty path_array for #{ob}"
			end
			v
		end
	end
end