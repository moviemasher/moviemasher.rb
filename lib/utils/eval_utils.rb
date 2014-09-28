
def eval_split(s)
	s.to_s.split(/{([^}]*)}/)
end

def eval_path ob, path_array
	value = ob
	key = path_array.shift
	if key then
		if key.to_i.to_s == key then
			key = key.to_i
		else
			key = key.to_sym 
		end
		value = value[key]
		raise "#{key} not found in #{value.inspect}" if value.nil?
		value = eval_path(value, path_array) unless path_array.empty?
	end
	value
end

def eval_recursively data, scope = nil
	scope = Hash.new unless scope
	keys = (data.is_a?(Hash) ? data.keys : (0..(data.length-1)))
	values = (data.is_a?(Hash) ? data.values : data)
	keys.each do |k|
		v = data[k]
		if v.is_a?(Hash) or v.is_a?(Array) then
			eval_recursively v, scope
		else
			data[k] = eval_value v.to_s, scope
		end
	end
end
def eval_value value, scope
	split_value = eval_split value
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
				if scope_child 
					if scope_child.is_a?(Hash) or scope_child.is_a?(Array)
						evaled = eval_path(scope_child, split_bit)
					elsif scope_child.is_a? Proc
						evaled = scope_child.call
					else 
						evaled = scope_child.to_s
					end
				end
				value += evaled if evaled
			end
			is_static = ! is_static
		end
	end
	value
end
