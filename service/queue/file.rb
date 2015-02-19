		
module MovieMasher
	class FileQueueService < QueueService
		def configure config
			(not (config[:queue_directory].nil? or config[:queue_directory].empty?)) and File.directory?(config[:queue_directory])
		end
		def receive_job
			job_hash = nil
			job_file = Dir[Path.concat configuration[:queue_directory], '*'].sort_by{ |f| File.mtime(f) }.first
			if job_file then
				job_hash = Job.resolved_hash job_file
				File.delete job_file
			end
			job_hash
		end
	end
end


			
