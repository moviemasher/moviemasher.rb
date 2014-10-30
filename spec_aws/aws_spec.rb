
require_relative '../spec/helpers/spec_helper'
require_relative 'helpers/clientside_aws'

describe File.basename(__FILE__) do
	before(:all) do
		spec_start_redis
		@directory = @configuration[:download_directory]
		@directory = @configuration[:render_directory] unless @directory and not @directory.empty?

	end
	after(:all) do
		spec_stop_redis
	end
	context "__cache_input" do
		it "correctly saves cached file when source is s3 object" do
			job = MovieMasher::Job.send(:__hash_keys_to_symbols!,spec_job_from_files 'image_s3')
			input = job[:inputs].first
			source = input[:source]
			source_frag = MovieMasher::Path.concat source[:path], "#{source[:name]}.#{source[:extension]}"
			source_path = "#{__dir__}/../spec/#{source_frag}"
			s3 = MovieMasher.send :__s3, source
			s3.buckets.create source[:bucket] 
			bucket = s3.buckets[source[:bucket]]
			path_name = Pathname.new("#{__dir__}/../spec/helpers/#{source_frag}")
			path_name = File.expand_path path_name
			#puts "path_name = #{path_name}"
			expect(File.exists? path_name).to be_true
			bucket.objects[source_frag].write(path_name, :content_type => 'image/jpeg')
			path = MovieMasher.send :__cache_input, (input, MovieMasher.send :__url_for_input, (input))
			url = "#{source[:type]}://#{source[:bucket]}.s3.amazonaws.com/#{source_frag}"
			url = Digest::SHA2.new(256).hexdigest url
			expect(path).to eq MovieMasher::Path.concat @directory, "#{url}/cached#{File.extname(source_frag)}"
			expect(File.exists? path).to be_true
			expect(FileUtils.identical? path, path_name).to be_true
		end
		it "correctly saves cached file when source is url" do
			# grab the file we saved to s3 via http 
			job = MovieMasher::Job.send(:__hash_keys_to_symbols!,spec_job_from_files 'image_url')
			input = job[:inputs].first
			input = MovieMasher::Job.send :__init_input, input
			source = input[:source]
			path = MovieMasher.send :__cache_input, (input, MovieMasher.send :__url_for_input, (input))
			url = Digest::SHA2.new(256).hexdigest source
			expect(path).to eq MovieMasher::Path.concat @directory, "#{url}/cached#{File.extname(source)}"
			expect(File.exists? path).to be_true
		end
	end
end