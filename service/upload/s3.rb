

module MovieMasher
  # handles upload to S3
  class S3UploadService < UploadService
    def upload(options)
      file = options[:file]
      bucket_key = Path.strip_slash_start(options[:path])
      if File.directory?(options[:upload])
        bucket_key = Path.concat(bucket_key, File.basename(file))
      end
      bucket = __s3_bucket(options[:destination])
      bucket_object = bucket.objects[bucket_key]
      bucket_options = __bucket_options(options)
      bucket_object.write(Pathname.new(file), bucket_options)
    end

    def __bucket_options(options)
      bucket_options = {}
      output_destination = options[:destination]
      output = options[:output]
      output_content_type = output[:mime_type]
      if output_destination[:acl]
        bucket_options[:acl] = output_destination[:acl].to_sym
      end
      bucket_options[:content_type] = output_content_type if output_content_type
      bucket_options
    end

    def __s3(source)
      unless source[:s3]
        require 'aws-sdk' unless defined? AWS
        region = source[:region].to_s
        region = configuration[:s3_region] if region.empty?
        source[:s3] = (region ? AWS::S3.new(region: region) : AWS::S3.new)
      end
      source[:s3]
    end

    def __s3_bucket(source)
      source[:s3_bucket] ||= __s3(source).buckets[source[:bucket]]
    end
  end
end
