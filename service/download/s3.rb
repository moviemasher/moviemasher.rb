

module MovieMasher
  # downloads assets via s3
  class S3DownloadService < DownloadService
    def download(options)
      source = options[:source]
      cache_url_path = options[:path]
      bucket = __s3_bucket(source)
      bucket_key = source.full_path
      object = bucket.objects[bucket_key]
      if configuration[:s3_read_at_once]
        object_read_data = object.read
        if object_read_data
          File.open(cache_url_path, 'wb') { |f| f << object_read_data }
        end
      else
        File.open(cache_url_path, 'wb') do |file|
          object.read do |chunk|
            file << chunk
          end
        end
      end
    end
    def __s3(source)
      unless source[:s3]
        require 'aws-sdk' unless defined?(AWS)
        options = {}
        unless configuration[:queue_region].to_s.empty?
          options[:region] = configuration[:queue_region]
        end
        source[:s3] = AWS::S3.new(options)
      end
      source[:s3]
    end
    def __s3_bucket(source)
      source[:s3_bucket] ||= __s3(source).buckets[source[:bucket]]
    end
  end
end
