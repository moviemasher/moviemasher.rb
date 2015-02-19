				
module MovieMasher
	class HttpsDownloadService < HttpDownloadService
		def secure
			true
		end	
	end
end
