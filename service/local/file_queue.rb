# frozen_string_literal: true

module MovieMasher
  # reads queue from local file system
  class FileQueueService < QueueService
    def configure(config)
      ok = !config[:queue_directory].to_s.empty?
      ok &&= File.directory?(config[:queue_directory])
      ok
    end

    def receive_job
      job_hash = nil
      files = Dir[Path.concat configuration[:queue_directory], '*']
      job_file = files.min_by { |f| File.mtime(f) }
      if job_file
        job_hash = Hashable.resolved_hash(job_file)
        File.delete(job_file)
      end
      job_hash
    end
  end
end
