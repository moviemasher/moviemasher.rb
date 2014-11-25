
module MovieMasher
# A Transfer object used as Job#destination or Output#destination representing a remote host
# ready to accept rendered file(s). 
#
# 
# 	Destination.create {
# 		:type => Transfer::TypeHttp,
# 		:host => 'example.com',             # http://example.com/cgi-bin/error.cgi?i=123
# 		:path => 'cgi-bin/upload.cgi',
# 		:parameters => {:i => '{job.id}'}  # Scalar - Job#id
# 	}
	class Destination < Transfer		
# Returns a new instance.
		def self.create hash = nil
			(hash.is_a?(Destination) ? hash : Destination.new(hash))
		end
		def self.create_if hash
			(hash ? create(hash) : nil)
		end
		def self.init_hash hash
			Transfer.init_hash hash
		end
		def error?	
			error = nil
			if name.to_s.include? '/'
				error = "destination name contains slash - use path instead #{name}" 
			end
			error
		end
	
	end
end