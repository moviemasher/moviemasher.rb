
def eval_split(s)
	result = Array.new
	if (s)
		pattern = Regexp.new(/{([^}]*)}/)
		return s.split(pattern)
		i = 1
		s.match(pattern) do |match|
			#puts i
			i += 1
			#puts match.inspect
			#puts $~ # is equivalent to ::last_match;
			$& # contains the complete matched text;
			$` # contains string before match;
			#puts $' # contains string after match;
			#puts $1
			#puts $2
			#puts $3
			#, $2 and so on contain text matching first, second, etc capture group;
			$+ # contains last capture group.
		
		end
		matches = s.scan(pattern)
#		params = Array.new
#		if (matches[1])
#			puts matches.inspect
#			puts matches[0].inspect
#			puts matches[1].inspect
#			result = preg_split(pattern, s, -1, PREG_SPLIT_DELIM_CAPTURE)
#		end
	end
	result
end