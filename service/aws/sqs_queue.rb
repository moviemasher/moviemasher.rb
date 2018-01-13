require_relative 'aws_helper'

module MovieMasher
  # reads queue from sqs
  class SqsQueueService < QueueService
    include AwsHelper
    def configure(config)
      problem = config[:queue_url].to_s.empty?
      problem &&= config[:queue_name].to_s.empty?
      !problem
    end
    def initialize
      @queue_url = nil
      super
    end
    def queue_url
      @queue_url ||= __queue_url
    end
    def __queue_url
      if configuration[:queue_url].to_s.empty?
        options = { queue_name: configuration[:queue_name] }
        sqs_client.get_queue_url(options).queue_url
      else
        configuration[:queue_url]
      end
    end
    def receive_job
      receive_options = {
        max_number_of_messages: 1, queue_url: queue_url,
        wait_time_seconds: configuration[:queue_wait_seconds]
      }
      message = sqs_client.receive_message(receive_options).messages.first
      job_hash = nil
      if message
        message_body = message.body
        job_hash = Hashable.resolved_hash(message_body)
        if job_hash[:error]
          job_hash = nil
        elsif job_hash[:id].to_s.empty?
          job_hash[:id] = message.message_id
        end
        sqs_client.delete_message(
          queue_url: queue_url, receipt_handle: message.receipt_handle
        )
      end
      job_hash
    end
  end
end
