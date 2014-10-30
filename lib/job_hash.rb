
module MovieMasher
# Mix-in functionality for mocking a Hash.
	module JobHash
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
# String - Unique identifier for object.
		def identifier; @identifier; end
# Set the actual Hash when creating.
		def initialize hash
			hash = Hash.new unless hash and hash.is_a? Hash
			@hash = hash
			@identifier = UUID.new.generate
		end
# Return deep copy of underlying Hash.
		def to_hash
			Marshal.load(Marshal.dump(@hash))
		end
# Return underlying Hash in JSON format.
		def to_json state = nil
			@hash.to_json state
		end
		protected
		def _set symbol, value
			self[symbol] = value
		end
		def _get symbol
			self[symbol]
		end
		
	end
end