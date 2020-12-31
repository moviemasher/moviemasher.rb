# frozen_string_literal: true

module MovieMasher
  # included by all aws service instances
  module AwsHelper
    class << self
      attr_accessor :__s3, :__s3_resource, :__sqs
    end

    def aws_configuration
      prefixed_configuration('aws_', configuration)
    end

    def prefixed_configuration(key, hash)
      config = {}
      hash.each do |k, value|
        k_str = k.id2name
        next unless k_str.start_with?(key)
        next if value.to_s.empty?

        k_str[key] = ''
        config[k_str.to_sym] = value
      end
      config
    end

    def s3_client
      __require_sdk
      AwsHelper.__s3 ||= Aws::S3::Client.new(s3_configuration)
    end

    def s3_resource
      __require_sdk
      AwsHelper.__s3_resource ||= Aws::S3::Resource.new(s3_configuration)
    end

    def s3_configuration
      aws_configuration.merge(prefixed_configuration('s3_', configuration))
    end

    def sqs_client
      __require_sdk
      AwsHelper.__sqs ||= Aws::SQS::Client.new(sqs_configuration)
    end

    def sqs_configuration
      aws_configuration.merge(prefixed_configuration('sqs_', configuration))
    end

    def __require_sdk
      require 'aws-sdk' unless defined?(Aws)
    end
  end
end
