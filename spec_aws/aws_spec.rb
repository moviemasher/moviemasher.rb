
require_relative '../spec/helpers/spec_helper'
require_relative 'helpers/clientside_aws'

describe File.basename(__FILE__) do
	before(:all) do
		spec_start_redis
	end
	after(:all) do
		spec_stop_redis
	end
	context "__cache_input" do
		it "correctly saves cached file when source is s3 object" do
			job = hash_keys_to_symbols!(spec_job_simple 'image_s3')
			input = job[:inputs].first
			source = input[:source]
			source_path = "#{__dir__}/../spec/#{source[:path]}"
			s3 = MovieMasher.__s3 source
			s3.buckets.create source[:bucket] 
			bucket = s3.buckets[source[:bucket]]
			path_name = Pathname.new("#{__dir__}/../spec/helpers/media/#{source[:path]}")
			bucket.objects[source[:path]].write(path_name, :content_type => 'image/jpeg')
			path = MovieMasher.__cache_input input
			url = "#{source[:type]}://#{source[:bucket]}.s3.amazonaws.com/#{source[:path]}"
			url = MovieMasher.__hash url
			expect(path).to eq "#{MovieMasher.configuration[:dir_cache]}#{url}/cached#{File.extname(source[:path])}"
			expect(File.exists? path).to be_true
			expect(FileUtils.identical? path, path_name).to be_true
		end
		it "correctly saves cached file when source is url" do
			# grab the file we saved to s3 via http 
			job = hash_keys_to_symbols!(spec_job_simple 'image_url')
			input = job[:inputs].first
			input = MovieMasher.__init_input(input)
			source = input[:source]
			path = MovieMasher.__cache_input input
			url = MovieMasher.__hash source
			expect(path).to eq "#{MovieMasher.configuration[:dir_cache]}#{url}/cached#{File.extname(source)}"
			expect(File.exists? path).to be_true
		end
	end
end