
require_relative 'helpers/clientside_aws'

describe File.basename(__FILE__) do
	before(:all) do
		spec_start_redis
		@directory = MovieMasher.configuration[:download_directory]
		@directory = MovieMasher.configuration[:render_directory] unless @directory and not @directory.empty?
	end
	after(:all) do
		spec_stop_redis
	end
	context "__cache_input" do
		it "correctly saves cached file when source is s3 object" do
			job = MovieMasher::Job.send(:__hash_keys_to_symbols!,spec_job_from_files('image_s3'))
			input = job[:inputs].first
			source = input[:source]
			source_frag = MovieMasher::Path.concat source[:path], "#{source[:name]}.#{source[:extension]}"
			source_path = "#{File.dirname(__FILE__)}/../spec/#{source_frag}"
			job_object = MovieMasher::Job.new job, MovieMasher.configuration
			#puts "BUCKET: #{source[:bucket]}"
			s3 = job_object.send(:__s3, MovieMasher::Source.new(source))
			s3.buckets.create source[:bucket].to_s
			bucket = s3.buckets[source[:bucket]]
			path_name = Pathname.new("#{File.dirname(__FILE__)}/../spec/helpers/#{source_frag}")
			path_name = File.expand_path path_name
			#puts "path_name = #{path_name}"
			#puts "source_frag = #{source_frag}"
			expect(File.exists? path_name).to be_true
			bucket.objects[source_frag].write(Pathname.new(path_name), :content_type => 'image/png')
			input_url = MovieMasher::Job.send(:__url_for_input, input)
			#puts "INPUT_URL: #{input_url}"
			path = job_object.send(:__cache_input, input, input_url)
			
			expect(path).to eq job_object.send(:__cache_url_path, input_url)
			#MovieMasher::Path.concat @directory, "#{url}/cached#{File.extname(source_frag)}"
			expect(File.exists? path).to be_true
			expect(FileUtils.identical? path, path_name).to be_true
		end
		
	end
end