
require_relative 'aws_helper'

module MovieMasher
  # downloads assets via s3
  class S3DownloadService < DownloadService
    include AwsHelper
    def download(options)
      source = options[:source]
      path = options[:path]
      bucket = source[:bucket]
      key = source.full_path
      s3_client.get_object(
        response_target: path, bucket: bucket, key: key
      )
    end
  end
end
