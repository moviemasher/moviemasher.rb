
require_relative 'helpers/spec_helper'

describe File.basename(__FILE__) do
#	before(:all) do
#		spec_start_redis
#	end
#	context "__transfer_file_destination" do
#		it "correctly creates symlink for file destination" do
#			file = File.expand_path "#{__dir__}/helpers/media/image/windmills.jpg"
#			destination = spec_transfer 'file'
#			hash_keys_to_symbols! destination
#			destination[:directory] = File.dirname __dir__
#			destination[:name] = 'windmills'
#			destination[:extension] = 'jpg'
#			MovieMasher.__transfer_file_destination file, destination
#			destination_file = "#{destination[:directory]}/#{destination[:path]}/windmills.jpg"
#			#puts destination_file
#			expect(File.exists? destination_file).to be_true
#			expect(FileUtils.identical? file, destination_file).to be_true
#		end
#		it "correctly puts file for s3 destination" do
#			file = File.expand_path "#{__dir__}/helpers/media/image/windmills.jpg"
#			destination = spec_transfer 's3'
#			hash_keys_to_symbols! destination
#			#puts "destination[:bucket] = #{destination[:bucket]}"
#			bucket = S3.buckets.create destination[:bucket] 
#			MovieMasher.__transfer_file_destination file, destination
#			key = destination[:path] + '/' + File.basename(file)
#			data = bucket.objects[key].read
#			expect(data).to_not be_nil
#			tmp_file = File.expand_path "#{MovieMasher.configuration[:dir_temporary]}/s3-#{File.basename(file)}"
#			File.open(tmp_file, 'w') { |file| file.write(data) }
#			expect(FileUtils.identical? tmp_file, file).to be_true
#		end
#		it "correctly posts file for http destination" do
#			file = File.expand_path "#{__dir__}/helpers/media/image/windmills.jpg"
#			destination = spec_transfer 'http'
#			destination[:name] = 'windmills'
#			destination[:extension] = 'jpg'
#			hash_keys_to_symbols! destination
#			MovieMasher.__transfer_file_destination file, destination
#			key = destination[:path] + '/' + destination[:name] + '.' + destination[:extension] 
#			bucket = S3.buckets['test']
#			data = bucket.objects[key].read
#			expect(data).to_not be_nil
#			tmp_file = File.expand_path "#{MovieMasher.configuration[:dir_temporary]}/http-#{File.basename(file)}"
#			File.open(tmp_file, 'w') { |file| file.write(data) }
#			expect(FileUtils.identical? tmp_file, file).to be_true
#		end
#	end
#	
#	
end