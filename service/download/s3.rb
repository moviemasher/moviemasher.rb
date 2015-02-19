
require 'aws-sdk' unless defined? AWS
				
module MovieMasher
	class S3DownloadService < DownloadService

		def download options
			source = options[:source]
			cache_url_path = options[:path]
			
			# TODO: seems we should be using asset, no??
			asset = options[:asset]
			bucket = __s3_bucket source
			bucket_key = source.full_path
			object = bucket.objects[bucket_key]
			if configuration[:s3_read_at_once] then
				object_read_data = object.read
				File.open(cache_url_path, 'wb') { |f| f << object_read_data } if object_read_data
			else
				File.open(cache_url_path, 'wb') do |file|
					object.read do |chunk|
						file << chunk
					end
				end
			end
		end
		def __s3 source
			unless source[:s3] 
				region = ((source[:region] and not source[:region].empty?) ? source[:region] : configuration[:s3_region])
				source[:s3] = (region ? AWS::S3.new(:region => region) : AWS::S3.new)
			end
			source[:s3]
		end
		def __s3_bucket source
			source[:s3_bucket] ||= __s3(source).buckets[source[:bucket]]
		end
	end
end
