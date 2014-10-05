def shell_switch(value, prefix = '', suffix = '')
	switch = ''
	value = value.to_s.strip
	if value #and not value.empty? then
		switch += ' ' # always add a leading space
		if value.start_with? '-' then # it's a switch, just include and ignore rest
			switch += value 
		else # prepend value with prefix and space
			switch += '-' unless prefix.start_with? '-'
			switch += prefix + ' ' + value
			switch += suffix unless switch.end_with? suffix # note lack of space!
		end
	end
	switch
end
