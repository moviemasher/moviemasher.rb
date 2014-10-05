def hash_keys_to_symbols! hash
	if hash 
		if hash.is_a? Hash then
			hash.keys.each do |k|
				v = hash[k]
				if k.is_a? String then
					k_sym = k.downcase.to_sym
					hash[k_sym] = v
					hash.delete k
				end
				hash_keys_to_symbols! v
			end
		elsif hash.is_a? Array then
			hash.each do |v|
				hash_keys_to_symbols! v
			end
		end
	end
	hash
end
