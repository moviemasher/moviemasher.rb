
require_relative 'aws_helper'

module MovieMasher
  # handles upload to S3
  class S3UploadService < UploadService
    include AwsHelper

    def upload(options)
      path = options[:file]
      key = Path.strip_slash_start(options[:path])
      if File.directory?(options[:output][:rendered_file])
        key = Path.concat(key, File.basename(path))
      end
      bucket_options = __bucket_options(options)
      bucket_options[:key] = key
      # puts "put_object #{bucket_options}"
      File.open(path, 'rb') do |file|
        bucket_options[:body] = file
        s3_client.put_object(bucket_options)
      end
    end
    def __bucket_options(options)
      bucket_options = {}
      output_destination = options[:destination]
      bucket_options[:bucket] = output_destination[:bucket]
      if output_destination[:acl]
        bucket_options[:acl] = output_destination[:acl].gsub('_', '-')
      else
        puts "output_destination: #{output_destination}"
      end
      if options[:output] && options[:output][:mime_type]
        bucket_options[:content_type] = options[:output][:mime_type]
      end
      bucket_options
    end
  end
end
