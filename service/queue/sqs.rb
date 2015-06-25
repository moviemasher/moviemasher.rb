
				
module MovieMasher
	class SqsQueueService < QueueService
		def __configure
			config = Hash.new
			configuration.each do |key, value|
				key_str = key.id2name
				if key_str.start_with? 'aws_'
					next if value.nil? || value.empty?
					key_str['aws_'] = ''
					config[key_str.to_sym] = value
				end
			end
			require 'aws-sdk' unless defined? AWS
			AWS.config config unless config.empty?
		end
		def __queue
			unless @queue
				__configure
				sqs = ((configuration[:queue_region].nil? or configuration[:queue_region].empty?) ? AWS::SQS.new : AWS::SQS.new(:region => configuration[:queue_region]))
				@queue = sqs.queues[configuration[:queue_url]]
			end
			@queue
		end
		def configure config
			not (config[:queue_url].nil? or config[:queue_url].empty?)
		end
		def initialize
			@queue = nil
			super
		end
		def receive_job
			job_hash = nil
			queue = __queue
			if queue
				message = queue.receive_message(:wait_time_seconds => configuration[:queue_wait_seconds])
				if message then
					message_body = message.body
					job_hash = Job.resolved_hash message_body
					if job_hash[:error] then
						job_hash = nil
					else
						job_hash[:id] = message.id if job_hash[:id].nil? or job_hash[:id].to_s.empty?
					end
					message.delete
				end
			end
			job_hash
		end
	end
end
