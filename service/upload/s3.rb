
				
module MovieMasher
	class S3UploadService < UploadService

		def upload options
			#TODO: we should be using output, no??
			output = options[:output] 
			upload = options[:upload]
			output_content_type = output[:mime_type]
			destination_path = options[:path]
			output_destination = options[:destination]
			file = options[:file]
			bucket_key = Path.strip_slash_start destination_path
			bucket_key = Path.concat(bucket_key, File.basename(file)) if File.directory?(upload)
			#puts "bucket_key = #{bucket_key}"
			bucket = __s3_bucket output_destination
			bucket_object = bucket.objects[bucket_key]
			bucket_options = Hash.new
			bucket_options[:acl] = output_destination[:acl].to_sym if output_destination[:acl]
			bucket_options[:content_type] = output_content_type if output_content_type
			bucket_object.write(Pathname.new(file), bucket_options)
		end
		def __s3 source
			unless source[:s3] 
				require 'aws-sdk' unless defined? AWS
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
