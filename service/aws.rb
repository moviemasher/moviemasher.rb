
require 'aws-sdk' unless defined? AWS

module MovieMasher
	class AwsService < Service
		def configure_service config
			super
			AWS.config @service_config
		end
		def configure_queue config
			super
			raise Error::Configuration.new "queue_url must be defined" unless @queue_config[:queue_url]
		end
		def initialize
			@queue_config = nil
		end
		def _queue
			unless @queue
				sqs = ((@queue_config[:queue_region] and not @queue_config[:queue_region].empty?) ? AWS::SQS.new(:region => @queue_config[:queue_region]) : AWS::SQS.new)
				@queue = sqs.queues[@queue_config[:queue_url]]
			end
			@queue
		end
		def receive_job
			job_hash = nil
			message = _queue.receive_message(:wait_time_seconds => @queue_config[:queue_wait_seconds])
			if message then
				message_body = message.body
				job_hash = Job.resolved_hash message_body
				if job_hash[:error] then
					__log_transcoder(:error) { "SQS #{job_hash[:error]}: #{message_body}" }
					job_hash = nil
				else
					job_hash[:id] = message.id unless job_hash[:id] and not job_hash[:id].to_s.empty?
				end
				message.delete
			end
			job_hash
		end
	end
end
