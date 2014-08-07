
require_relative 'spec_helper'

describe "Sources..." do
	before(:all) do
		spec_start_redis
	end
	
	context "__directory_path_name" do
		it "correctly deals with leading and trailing slashes" do
			source = {:directory => 'DIR/', :path => '/PATH.ext'}
			expect(MovieMasher.__directory_path_name source).to eq 'DIR/PATH.ext'
		end
	end
	context "__source_url" do
		it "correctly returns url if defined" do
			source = {:url => 'URL'}
			expect(MovieMasher.__source_url source).to eq source[:url]
		end
		it "correctly returns file url for file source with just path" do
			source = {:type => 'file', :path => 'PATH'}
			expect(MovieMasher.__source_url source).to eq "#{source[:type]}://#{source[:path]}"
		end
		it "correctly returns file url for file source with path, name and extension" do
			source = {:type => 'file', :path => 'PATH', :name => 'NAME', :extension => 'EXTENSION'}
			expect(MovieMasher.__source_url source).to eq "#{source[:type]}://#{source[:path]}/#{source[:name]}.#{source[:extension]}"
		end
	end
	context "__input_url" do
		it "correctly returns url when source is simple url" do
			job = MovieMasher.__change_keys_to_symbols!(spec_job_simple 'image_url')
			input = job[:inputs].first
			input = MovieMasher.__init_input(input)
			url = MovieMasher.__input_url input
			expect(url).to eq input[:url]
		end
		it "correctly returns file url when source is file object" do
			job = MovieMasher.__change_keys_to_symbols!(spec_job_simple 'image_file')
			input = job[:inputs].first
			url = MovieMasher.__input_url input
			source = input[:source]
			expect(url).to eq "#{source[:type]}://#{source[:path]}/#{source[:name]}.#{source[:extension]}"
		end
	end
	context "__cache_input" do
		it "correctly saves cached file when source is file object" do
			job = MovieMasher.__change_keys_to_symbols!(spec_job_simple 'image_file')
			input = job[:inputs].first
			source = input[:source]
			source[:directory] = __dir__
			path = MovieMasher.__cache_input input
			url = "#{source[:type]}://#{__dir__}/#{source[:path]}/#{source[:name]}.#{source[:extension]}"
			url = MovieMasher.__hash url
			expect(path).to eq "#{CONFIG['dir_cache']}/#{url}/cached.#{source[:extension]}"
			expect(File.exists? path).to be_true
			expect(File.symlink? path).to be_true
		end
		it "correctly saves cached file when source is s3 object" do
			job = MovieMasher.__change_keys_to_symbols!(spec_job_simple 'image_s3')
			input = job[:inputs].first
			source = input[:source]
			source_path = "#{__dir__}/#{source[:path]}"
			bucket = S3.buckets[source[:bucket]]
			path_name = Pathname.new("#{__dir__}/media/#{source[:path]}")
			S3.buckets.create source[:bucket] 
			bucket.objects[source[:path]].write(path_name, :content_type => 'image/jpeg')
			path = MovieMasher.__cache_input input
			url = "#{source[:type]}://#{source[:bucket]}.s3.amazonaws.com/#{source[:path]}"
			url = MovieMasher.__hash url
			expect(path).to eq "#{CONFIG['dir_cache']}/#{url}/cached#{File.extname(source[:path])}"
			expect(File.exists? path).to be_true
			expect(FileUtils.identical? path, path_name).to be_true
		end
		it "correctly saves cached file when source is url" do
			# grab the file we saved to s3 via http (clientside_aws must be running with RACK_ENV=test on port 4568)
			job = MovieMasher.__change_keys_to_symbols!(spec_job_simple 'image_url')
			input = job[:inputs].first
			input = MovieMasher.__init_input(input)
			source = input[:source]
			path = MovieMasher.__cache_input input
			url = MovieMasher.__hash source
			expect(path).to eq "#{CONFIG['dir_cache']}/#{url}/cached#{File.extname(source)}"
			expect(File.exists? path).to be_true
		end
	end
end