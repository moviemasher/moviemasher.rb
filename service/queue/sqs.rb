
module MovieMasher
  # reads queue from sqs
  class SqsQueueService < QueueService
    def configure(config)
      !config[:queue_url].to_s.empty?
    end
    def initialize
      @queue = nil
      super
    end
    def receive_job
      job_hash = nil
      queue = __queue
      if queue
        options = { wait_time_seconds: configuration[:queue_wait_seconds] }
        message = queue.receive_message(options)
        if message
          message_body = message.body
          job_hash = Hashable.resolved_hash(message_body)
          if job_hash[:error]
            job_hash = nil
          elsif job_hash[:id].to_s.empty?
            job_hash[:id] = message.id
          end
          message.delete
        end
      end
      job_hash
    end
    def __configure
      config = {}
      configuration.each do |key, value|
        key_str = key.id2name
        next unless key_str.start_with?('aws_')
        next if value.to_s.empty?
        key_str['aws_'] = ''
        config[key_str.to_sym] = value
      end
      require 'aws-sdk' unless defined?(AWS)
      AWS.config(config) unless config.empty?
    end
    def __queue
      unless @queue
        __configure
        options = {}
        unless configuration[:queue_region].to_s.empty?
          options[:region] = configuration[:queue_region]
        end
        sqs = AWS::SQS.new(options)
        @queue = sqs.queues[configuration[:queue_url]]
      end
      @queue
    end
  end
end
