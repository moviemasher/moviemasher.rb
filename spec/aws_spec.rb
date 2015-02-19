
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
	context "__cache_asset" do
		it "correctly saves cached file when source is s3 object" do
			image_path = MagickGenerator.image_file
			image_input = {
				"id" => "image_s3",
				"type" => "image",
				"source" => {
					"type" => "s3",
					"bucket" => "test",
					"path" => "media/image",
					"name" => "small-1x1",
					"extension" => "png"
				}
			}

			job = spec_job_from_files image_input
			input = job[:inputs].first
			source = input[:source]
			source_frag = MovieMasher::Path.concat source[:path], "#{source[:name]}.#{source[:extension]}"
			source_path = "#{File.dirname(__FILE__)}/../spec/#{source_frag}"
			job_object = MovieMasher::Job.create job
			job_object.preflight
			
			s3 = job_object.send(:__s3, MovieMasher::Source.new(source))
			s3.buckets.create source[:bucket].to_s
			bucket = s3.buckets[source[:bucket]]
			
			expect(File.exists? image_path).to be_true
			bucket.objects[source_frag].write(Pathname.new(image_path), :content_type => 'image/png')
			input = job_object[:inputs].first
			path = job_object.send(:__cache_url_path, input.url)
			job_object.send(:__cache_asset, input)
			expect(path).to eq job_object.send(:__cache_url_path, input[:input_url])
			expect(File.exists? path).to be_true
			expect(FileUtils.identical? path, image_path).to be_true
		end
		
	end
end
