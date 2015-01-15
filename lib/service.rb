
module MovieMasher
	class Service
	
		def configure_service config
			@service_config = config
		end
		def configure_queue config
			@queue_config = config
		end
		def receive_job
			nil
		end
	end
end
