
module MovieMasher
# Base class for mocking a Hash.
	class Hashable
# Convenience getter for underlying data Hash.
#
# symbol - Symbol key into hash.
#
# Returns value of key or nil if no such key exists.
		def [] symbol
			@hash[symbol]
		end
# Convenience setter for underlying data Hash.
#
# symbol - Symbol key into hash.
# value - Object to set at key.
#
# Returns *value*.
		def []=(symbol, value)
			@hash[symbol] = value
		end
# Returns Symbol of lowercased class name without namespace qualifiers.
		def class_symbol
			self.class.name.downcase.split('::').last.to_sym
		end
		def hash
			@hash
		end
# String - Unique identifier for object.
		def identifier
			@identifier
		end
# Set the actual Hash when creating.
		def initialize hash = nil
			unless hash.is_a? Hash
				#puts "Hashable#initialize NOT HASH #{hash}"
				hash = Hash.new
			end
			@hash = hash
			@identifier = UUID.new.generate if defined? UUID
		end
		def keys
			@hash.keys
		end
# Return deep copy of underlying Hash.
		def to_hash
			Marshal.load(Marshal.dump(@hash))
		end
# Return underlying Hash in JSON format.
		def to_json state = nil
			@hash.to_json state
		end
		def values
			@hash.values
		end
		protected
		def _set symbol, value
			symbol = symbol.to_s[0..-2].to_sym
			@hash[symbol] = value
		end
		def _get symbol
			@hash[symbol]
		end
		def self._init_key hash, key, default
			if hash
				value = hash[key]
				overwrite = value.nil?
				unless overwrite
					if default.is_a? Array or default.is_a? Hash then
						overwrite = ! (value.is_a? Array or value.is_a? Hash)
						overwrite = value.empty? unless overwrite
					else
						overwrite = value.to_s.empty?
					end
				end
				hash[key] = default if overwrite
			end
		end
		
	end
end