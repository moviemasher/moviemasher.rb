
require_relative 'http'

module MovieMasher
	class HttpsDownloadService < HttpDownloadService
		def secure
			true
		end	
	end
end
