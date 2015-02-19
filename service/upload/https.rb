			
require_relative 'http'

module MovieMasher
	class HttpsUploadService < HttpUploadService
		def secure
			true
		end	
	end
end
